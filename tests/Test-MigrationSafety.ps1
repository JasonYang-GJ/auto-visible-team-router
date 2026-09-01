[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }

function Resolve-Migration([bool]$InFlight, [bool]$SafeCheckpoint, [bool]$CriticalConflict) {
    if ($CriticalConflict) { return 'InterruptForSafety' }
    if ($InFlight -and -not $SafeCheckpoint) { return 'PreserveAndWait' }
    return 'AdoptAtCheckpoint'
}
function Resolve-IntegrationOwner([object]$Alternate) {
    if ($null -eq $Alternate) { return [pscustomobject]@{ role='Coordinator'; valid=$true } }
    $valid = @('role','threadId','targetBranch','scope','reason','authorization') | ForEach-Object {
        $Alternate.PSObject.Properties.Name -contains $_ -and -not [string]::IsNullOrWhiteSpace([string]$Alternate.$_)
    }
    [pscustomobject]@{ role=$Alternate.role; valid=(-not ($valid -contains $false)) }
}

Assert-True ((Resolve-Migration $true $false $false) -eq 'PreserveAndWait') 'Upgrade interrupted in-flight work before a checkpoint.'
Assert-True ((Resolve-Migration $true $false $true) -eq 'InterruptForSafety') 'Critical verified conflict did not interrupt safely.'
Assert-True ((Resolve-Migration $true $true $false) -eq 'AdoptAtCheckpoint') 'Checkpoint adoption was not allowed.'
Assert-True ((Resolve-IntegrationOwner $null).role -eq 'Coordinator') 'Coordinator is not the default Integration Owner.'
$invalidAlternate = [pscustomobject]@{ role='Developer'; threadId='thread-dev' }
Assert-True (-not (Resolve-IntegrationOwner $invalidAlternate).valid) 'Incomplete alternate Integration Owner was accepted.'
$validAlternate = [pscustomobject]@{ role='Developer'; threadId='thread-dev'; targetBranch='main'; scope='candidate commits'; reason='authorized release owner'; authorization='user approval' }
Assert-True (Resolve-IntegrationOwner $validAlternate).valid 'Complete alternate Integration Owner was rejected.'

$skill = Get-Content -LiteralPath (Join-Path $SkillRoot 'SKILL.md') -Raw
$routing = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\routing-policy.md') -Raw
$roles = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\role-catalog.md') -Raw
$context = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\context-delegation.md') -Raw
$module = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\module-governance.md') -Raw
$migration = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\migration-integration.md') -Raw

foreach ($required in @('hard fast path','current task','Worktree','Module Registry')) { Assert-True (($skill + $routing).Contains($required)) "Level 0 fast path is missing: $required" }
Assert-True ($roles.Contains('| Developer | 开发工程师 |')) 'Canonical Developer role is missing.'
Assert-True ($roles.Contains('not an automatic alias for') -and $roles.Contains('Reuse an accessible existing Developer')) 'Developer reuse/normalization rule is incomplete.'
foreach ($required in @('Packet invalidation events','baseline/integration baseline','CapabilityCheckRefresh')) { Assert-True (($context + $module).Contains($required)) "Packet/capability refresh rule is missing: $required" }
foreach ($required in @('Preserve in-flight work','Safe checkpoints','Project mode authorization','Integration ownership','Read-only attribution')) { Assert-True ($migration.Contains($required)) "Migration reference is missing: $required" }

[pscustomobject]@{ suite='V1.3.3 migration and integration safety'; passed=($failures.Count -eq 0); failures=$failures } | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { exit 1 }
