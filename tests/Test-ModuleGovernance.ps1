[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Resolve-ModuleCase([pscustomobject]$Case) {
    $architectRequired = (
        $Case.ContractChanged -or $Case.SharedStateChanged -or
        $Case.UncertainBoundary -or $Case.UnresolvedAuthoritativeDuplication
    )
    $parallelAllowed = (
        $Case.WriterCount -ge 2 -and $Case.DisjointModules -and
        $Case.DisjointPaths -and $Case.MaterialTimeBenefit
    )
    $sameModuleConflict = $Case.WriterCount -ge 2 -and -not $Case.DisjointModules
    $duplicateStatus = if ($Case.ExistingAuthoritativeCapability -and $Case.AttemptedReplacement) { 'POSSIBLE_DUPLICATION' } else { 'None' }
    $implementation = if ($Case.ExistingAuthoritativeCapability) { 'ExtendExisting' } else { 'AddBoundedCapability' }
    $qaStatus = if ($Case.FeaturePass -and $Case.RegressionPass) { 'PASS' } elseif ($Case.RequiresQA) { 'FAIL' } else { 'NotRequired' }

    [pscustomobject]@{
        name = $Case.Name
        shadowMode = $true
        registryWrite = $false
        initialScope = 1
        existingCapabilityCheck = $true
        implementation = $implementation
        duplicateStatus = $duplicateStatus
        architectRequired = $architectRequired
        parallelAllowed = $parallelAllowed
        sameModuleConflict = $sameModuleConflict
        routingDecision = $(if ($sameModuleConflict) { 'OwnerHandoffOrSerialize' } elseif ($parallelAllowed) { 'ParallelDisjoint' } else { 'SingleWriter' })
        qaStatus = $qaStatus
        featurePass = $Case.FeaturePass
        regressionPass = $Case.RegressionPass
    }
}

$cases = @(
    [pscustomobject]@{Name='A-voice-stop-reuses-cancellation';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=1;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$false;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='B-ai-feature-finds-owner';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=1;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$false;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='C-second-session-manager';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$true;WriterCount=1;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$false;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$true;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='D-frontend-backend-disjoint';ExistingAuthoritativeCapability=$false;AttemptedReplacement=$false;WriterCount=2;DisjointModules=$true;DisjointPaths=$true;MaterialTimeBenefit=$true;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='E-two-voice-writers';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=2;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$true;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='F-voice-ai-session-contract';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=2;DisjointModules=$true;DisjointPaths=$true;MaterialTimeBenefit=$true;ContractChanged=$true;SharedStateChanged=$true;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='G-simple-voice-text';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=1;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$false;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$false;FeaturePass=$true;RegressionPass=$true},
    [pscustomobject]@{Name='H-feature-pass-regression-fail';ExistingAuthoritativeCapability=$true;AttemptedReplacement=$false;WriterCount=1;DisjointModules=$false;DisjointPaths=$false;MaterialTimeBenefit=$false;ContractChanged=$false;SharedStateChanged=$false;UncertainBoundary=$false;UnresolvedAuthoritativeDuplication=$false;RequiresQA=$true;FeaturePass=$true;RegressionPass=$false}
)

$results = @($cases | ForEach-Object { Resolve-ModuleCase $_ })
$a, $b, $c, $d, $e, $f, $g, $h = $results

Assert-True ($a.implementation -eq 'ExtendExisting' -and $a.duplicateStatus -eq 'None') 'Case A must extend the authoritative cancellation path.'
Assert-True ($b.implementation -eq 'ExtendExisting' -and -not $b.architectRequired) 'Case B must find and reuse the existing AI owner without mechanical Architect routing.'
Assert-True ($c.duplicateStatus -eq 'POSSIBLE_DUPLICATION' -and $c.architectRequired) 'Case C must block an unresolved second Session manager behind a duplication decision.'
Assert-True ($d.parallelAllowed -and $d.routingDecision -eq 'ParallelDisjoint') 'Case D must allow materially useful disjoint module writers.'
Assert-True (-not $e.parallelAllowed -and $e.routingDecision -eq 'OwnerHandoffOrSerialize') 'Case E must serialize two writers in the Voice module.'
Assert-True ($f.architectRequired) 'Case F must require Architect for a changed cross-module cancellation contract.'
Assert-True (-not $g.architectRequired -and $g.initialScope -eq 1) 'Case G must keep a simple local Voice edit at Scope 1 without Architect.'
Assert-True ($h.featurePass -and -not $h.regressionPass -and $h.qaStatus -eq 'FAIL') 'Case H regression failure must override feature success.'
Assert-True (@($results | Where-Object { -not $_.shadowMode -or $_.registryWrite }).Count -eq 0) 'Shadow fixtures must not persist module state.'

$policyText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\module-governance.md') -Raw
$policyNormalized = ($policyText -replace '\s+', ' ')
$packetText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\context-delegation.md') -Raw
foreach ($required in @('Existing Capability Check','POSSIBLE_DUPLICATION','one active coding writer','Expiry makes a lease an unverified stale candidate','REMOVABLE','Feature tests','Regression tests')) {
    Assert-True ($policyNormalized.Contains($required)) "Module governance policy is missing: $required"
}
foreach ($field in @('primary_module','affected_modules','module_owner','existing_capability_evidence','change_impact','architecture_gate','module_write_lease')) {
    Assert-True ($packetText.Contains($field)) "Delegation Packet is missing: $field"
}

[pscustomobject]@{
    suite = 'V1.3.1 module governance Shadow Cases A-H'
    passed = ($failures.Count -eq 0)
    cases = $results
    failures = $failures
} | ConvertTo-Json -Depth 10
if ($failures.Count -gt 0) { exit 1 }
