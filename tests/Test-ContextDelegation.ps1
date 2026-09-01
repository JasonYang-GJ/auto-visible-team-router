[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Resolve-ContextPlan([pscustomobject]$Case) {
    $roles = [System.Collections.Generic.List[string]]::new()
    $initialScopes = [ordered]@{}
    $finalScopes = [ordered]@{}

    if ($Case.ArchitectureScope -eq 'Global') {
        $roles.Add('Architect')
        $initialScopes.Architect = 2
        $finalScopes.Architect = 2
    }

    if ($Case.ParallelWriters -ge 2) {
        $roles.Add('Frontend')
        $roles.Add('Backend')
        $initialScopes.Frontend = 1
        $initialScopes.Backend = 1
        $finalScopes.Frontend = 1
        $finalScopes.Backend = 1
    } elseif ($Case.RequiresImplementation) {
        $roles.Add('Developer')
        $initialScopes.Developer = 1
        $finalScopes.Developer = 1
    }

    $scopeEscalation = $null
    if ($Case.RequiresQA) {
        $roles.Add('QA')
        $initialScopes.QA = 1
        $finalScopes.QA = 1
        if ($Case.QACrossModuleEvidence) {
            $finalScopes.QA = 3
            $scopeEscalation = [pscustomobject]@{
                role = 'QA'
                from = 1
                to = 3
                reason = 'direct test evidence shows a cross-module side effect'
            }
        }
    }

    $parallelAllowed = (
        $Case.ParallelWriters -ge 2 -and
        $Case.DisjointOwnership -and
        $Case.MaterialTimeBenefit
    )

    $packetMode = if ($Case.RepairRound -gt 0) { 'ContextDelta' } else { 'FullPacket' }
    $delta = if ($packetMode -eq 'ContextDelta') {
        [pscustomobject]@{
            packet_id = 'case-e-dev-01'
            packet_version = 1
            previous_sha = '1111111'
            new_sha = '2222222'
            changed_files = @('bridge.ts')
            unchanged_constraints = 'packet case-e-dev-01 v1'
        }
    } else { $null }

    [pscustomobject]@{
        name = $Case.Name
        roles = @($roles)
        initialScopes = $initialScopes
        finalScopes = $finalScopes
        maxAllowedScope = $(if ($Case.ArchitectureScope -eq 'Global') { 4 } else { 3 })
        repositoryWideAllowed = ($Case.ArchitectureScope -eq 'Global')
        fullRepositoryScan = $false
        scopeEscalation = $scopeEscalation
        packetMode = $packetMode
        contextDelta = $delta
        duplicateContextRisk = $Case.DuplicateContextRisk
        parallelAllowed = $parallelAllowed
        newWorktreeAllowed = $parallelAllowed
    }
}

$cases = @(
    [pscustomobject]@{Name='A-single-file-bug';RequiresImplementation=$true;RequiresQA=$false;ArchitectureScope='Local';ParallelWriters=1;DisjointOwnership=$false;MaterialTimeBenefit=$false;QACrossModuleEvidence=$false;RepairRound=0;DuplicateContextRisk='Low'},
    [pscustomobject]@{Name='B-local-bridge';RequiresImplementation=$true;RequiresQA=$true;ArchitectureScope='Local';ParallelWriters=1;DisjointOwnership=$false;MaterialTimeBenefit=$false;QACrossModuleEvidence=$false;RepairRound=0;DuplicateContextRisk='Medium'},
    [pscustomobject]@{Name='C-architecture-refactor';RequiresImplementation=$false;RequiresQA=$false;ArchitectureScope='Global';ParallelWriters=0;DisjointOwnership=$false;MaterialTimeBenefit=$false;QACrossModuleEvidence=$false;RepairRound=0;DuplicateContextRisk='Medium'},
    [pscustomobject]@{Name='D-qa-cross-module';RequiresImplementation=$true;RequiresQA=$true;ArchitectureScope='Local';ParallelWriters=1;DisjointOwnership=$false;MaterialTimeBenefit=$false;QACrossModuleEvidence=$true;RepairRound=0;DuplicateContextRisk='Medium'},
    [pscustomobject]@{Name='E-context-delta-loop';RequiresImplementation=$true;RequiresQA=$true;ArchitectureScope='Local';ParallelWriters=1;DisjointOwnership=$false;MaterialTimeBenefit=$false;QACrossModuleEvidence=$false;RepairRound=1;DuplicateContextRisk='Medium'},
    [pscustomobject]@{Name='F-disjoint-parallel-writers';RequiresImplementation=$true;RequiresQA=$false;ArchitectureScope='Local';ParallelWriters=2;DisjointOwnership=$true;MaterialTimeBenefit=$true;QACrossModuleEvidence=$false;RepairRound=0;DuplicateContextRisk='Low'}
)

$results = @($cases | ForEach-Object { Resolve-ContextPlan $_ })
$a, $b, $c, $d, $e, $f = $results

Assert-True ($a.roles.Count -le 1 -and -not $a.fullRepositoryScan) 'Case A must use at most one specialist and no full scan.'
Assert-True ($a.initialScopes.Developer -eq 1) 'Case A Developer must start at Scope 1.'
Assert-True (($b.roles -join ',') -eq 'Developer,QA') 'Case B must use Developer plus QA.'
Assert-True ($b.initialScopes.Developer -eq 1 -and $b.initialScopes.QA -eq 1) 'Case B must start both roles at Scope 1.'
Assert-True (-not $b.fullRepositoryScan) 'Case B must not perform a full scan.'
Assert-True ($c.roles -contains 'Architect' -and $c.repositoryWideAllowed -and $c.maxAllowedScope -eq 4) 'Case C must allow justified Architect expansion to Scope 4.'
Assert-True ($d.scopeEscalation.role -eq 'QA' -and $d.scopeEscalation.from -eq 1 -and $d.scopeEscalation.to -eq 3) 'Case D must record QA Scope escalation.'
Assert-True (-not [string]::IsNullOrWhiteSpace($d.scopeEscalation.reason)) 'Case D escalation requires a reason.'
Assert-True ($e.packetMode -eq 'ContextDelta') 'Case E must use Context Delta after QA failure.'
Assert-True ($e.contextDelta.packet_id -and $e.contextDelta.packet_version -and $e.contextDelta.previous_sha -and $e.contextDelta.new_sha -and $e.contextDelta.unchanged_constraints) 'Case E Delta is missing stale-context guards.'
Assert-True ($f.parallelAllowed -and $f.newWorktreeAllowed) 'Case F must allow real disjoint parallel writers.'
Assert-True (($f.roles -join ',') -eq 'Frontend,Backend') 'Case F must keep distinct writer ownership.'

$contextText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\context-delegation.md') -Raw
$routingText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\routing-policy.md') -Raw
foreach ($required in @('packet_id','packet_version','previous_sha','new_sha','Scope 0','Scope 4','Context efficiency is subordinate to correctness')) {
    Assert-True ($contextText.Contains($required)) "Context policy is missing: $required"
}
foreach ($risk in @('Low','Medium','High')) {
    Assert-True ($routingText.Contains($risk)) "Routing policy is missing duplicate-context risk: $risk"
}

[pscustomobject]@{
    suite = 'V1.2.0 context delegation Cases A-F'
    passed = ($failures.Count -eq 0)
    cases = $results
    failures = $failures
} | ConvertTo-Json -Depth 10
if ($failures.Count -gt 0) { exit 1 }
