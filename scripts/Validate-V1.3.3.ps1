[CmdletBinding()]
param(
    [string]$SkillRoot,
    [ValidateSet('Package','Installed')]
    [string]$Mode = 'Package',
    [string]$AgentsPath
)

$ErrorActionPreference = 'Stop'
if (-not $SkillRoot) { $SkillRoot = Split-Path -Parent $PSScriptRoot }
$SkillRoot = [System.IO.Path]::GetFullPath($SkillRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Router([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }

$required = @(
    'SKILL.md','VERSION','README.md','agents\openai.yaml',
    'references\routing-policy.md','references\role-catalog.md','references\thread-lifecycle.md',
    'references\context-delegation.md','references\module-governance.md','references\migration-integration.md',
    'references\visible-thread-delivery-recovery.md','references\delivery-reliability.md',
    'references\acceptance-tests.md','scripts\Manage-Global.ps1','scripts\Thread-Registry.ps1',
    'scripts\Module-Registry.ps1','scripts\Registry-Lock.ps1','scripts\ReadOnly-Guard.ps1',
    'scripts\Validate-V1.ps1','scripts\Validate-V1.1.ps1','scripts\Validate-V1.1.1.ps1',
    'scripts\Validate-V1.2.ps1','scripts\Validate-V1.3.ps1','scripts\Validate-V1.3.1.ps1','scripts\Validate-V1.3.2.ps1','scripts\Validate-V1.3.3.ps1',
    'scripts\Run-Acceptance-V1.3.1.ps1','scripts\Run-Acceptance-V1.3.2.ps1','scripts\Run-Acceptance-V1.3.3.ps1','tests\Test-ThreadRegistry.ps1',
    'tests\Test-LifecycleRegistry.ps1','tests\Test-ReadOnlyGuard.ps1',
    'tests\Test-ManagementLifecycle.ps1','tests\Test-RegistryScale.ps1',
    'tests\Test-ContextDelegation.ps1','tests\Test-ModuleRegistry.ps1',
    'tests\Test-ModuleGovernance.ps1','tests\Test-TokenEfficiency.ps1',
    'tests\Test-RegistryLockRecovery.ps1','tests\Test-MigrationSafety.ps1','tests\Test-RealGitLifecycle.ps1',
    'tests\Test-VisibleThreadDeliveryRecovery.ps1','tests\Test-DeliveryReliability.ps1'
)
foreach ($relative in $required) { Assert-Router (Test-Path -LiteralPath (Join-Path $SkillRoot $relative)) "Missing required file: $relative" }

if ($failures.Count -eq 0) {
    $skill = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'SKILL.md'),$utf8)
    $version = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'VERSION'),$utf8).Trim()
    $yaml = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'agents\openai.yaml'),$utf8)
    $manager = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Manage-Global.ps1'),$utf8)
    $moduleScript = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Module-Registry.ps1'),$utf8)
    $threadScript = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'),$utf8)
    $lockScript = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Registry-Lock.ps1'),$utf8)
    $readOnlyScript = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\ReadOnly-Guard.ps1'),$utf8)
    $routing = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\routing-policy.md'),$utf8)
    $roles = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\role-catalog.md'),$utf8)
    $context = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\context-delegation.md'),$utf8)
    $module = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\module-governance.md'),$utf8)
    $migration = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\migration-integration.md'),$utf8)
    $lifecycle = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\thread-lifecycle.md'),$utf8)
    $deliveryRecovery = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\visible-thread-delivery-recovery.md'),$utf8)
    $deliveryReliability = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\delivery-reliability.md'),$utf8)
    $acceptance = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\acceptance-tests.md'),$utf8)
    $wrapper = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Validate-V1.ps1'),$utf8)

    Assert-Router ($version -eq '1.3.3') 'VERSION is not 1.3.3.'
    Assert-Router ($skill -match '(?m)^name:\s*auto-visible-team-router\s*$') 'Invalid skill name.'
    Assert-Router ($skill -match '(?m)^description:\s*\S') 'Missing skill description.'
    $frontmatter = [regex]::Match($skill,'(?s)^---\r?\n(.*?)\r?\n---').Groups[1].Value
    $frontmatterKeys = @([regex]::Matches($frontmatter,'(?m)^([a-zA-Z0-9_-]+):') | ForEach-Object {$_.Groups[1].Value})
    Assert-Router (($frontmatterKeys -join ',') -eq 'name,description') 'SKILL frontmatter must contain only name and description.'
    Assert-Router ($yaml -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$') 'Implicit invocation is not enabled.'
    Assert-Router ($skill -notmatch '(?m)^\s*(model|thinking)\s*:') 'Pinned model/thinking route found.'
    Assert-Router ($skill -notmatch '(?i)C:\\Users\\|/Users/[^/]+/') 'Machine-specific path found in SKILL.md.'
    Assert-Router ($wrapper.Contains("'Validate-V1.3.3.ps1'")) 'Validate-V1.ps1 does not target the current validator.'

    foreach ($legacy in @('Registry-first reuse','Team Adoption','Thread, Worktree, and Branch are different objects','default per-project Worktree Budget is three','two or more coding Agents','Policy-Enforced Read','new SHA')) {
        Assert-Router ((($skill -replace '\s+',' ')).Contains($legacy)) "Lifecycle invariant is missing: $legacy"
    }
    foreach ($requiredText in @('hard fast path','exact-scope','READ_ONLY_STATE_CHANGED','migration-integration.md','Integration Owner','visible-thread-delivery-recovery.md','delivery-reliability.md','REDELIVER','one replacement per incident')) { Assert-Router ($skill.Contains($requiredText)) "V1.3.3 entry rule is missing: $requiredText" }
    Assert-Router ($roles.Contains('| Developer | 开发工程师 |')) 'Canonical Developer role is missing.'
    Assert-Router ($routing.Contains('Level 0') -and $routing.Contains('Do not discover/adopt/create specialist')) 'Level 0 fast path is incomplete.'
    Assert-Router ($context.Contains('Packet invalidation events') -and $context.Contains('CapabilityCheckRefresh')) 'Packet invalidation/refresh rules are missing.'
    foreach ($requiredText in @('AuthorizedAt','Active-to-Shadow','idempotent only when','every Active lease','patches: unspecified')) { Assert-Router ($module.Contains($requiredText)) "Module integrity rule is missing: $requiredText" }
    foreach ($requiredText in @('Preserve in-flight work','Safe checkpoints','Integration ownership','Read-only attribution')) { Assert-Router ($migration.Contains($requiredText)) "Migration rule is missing: $requiredText" }
    Assert-Router ($lifecycle.Contains('current V1.3.3 policy')) 'Current lifecycle text still names an obsolete active policy.'
    foreach ($requiredText in @('THREAD_DELIVERY_DEGRADED','VISIBLE_THREAD_DELIVERY_UNAVAILABLE','ARCHITECT_SPECIALIST_CHANNEL_UNAVAILABLE','Coordinator fallback','completed','CHANNEL_UNAVAILABLE','ThreadDelivery:')) { Assert-Router ($deliveryRecovery.Contains($requiredText)) "Delivery recovery rule is missing: $requiredText" }
    foreach ($requiredText in @('Delivery Receipt','DELIVERY_RECONCILIATION','DISPATCHED','WORK_COMPLETED','DELIVERY_PENDING','DELIVERED','ACKNOWLEDGED','DELIVERY_EVIDENCE_CONFLICT','REDELIVER','MANUAL_VISIBLE_THREAD_HANDOFF','PLATFORM_LIMITATION')) { Assert-Router ($deliveryReliability.Contains($requiredText)) "Delivery reliability rule is missing: $requiredText" }
    Assert-Router ($readOnlyScript.Contains("'READ_ONLY_STATE_CHANGED'")) 'ReadOnly Guard still over-attributes changes.'
    Assert-Router ($moduleScript.Contains('PacketVersion') -and $moduleScript.Contains('Test-PathScopeConflict') -and $moduleScript.Contains('modeAuthorization')) 'Module Registry integrity implementation is incomplete.'
    Assert-Router ($threadScript.Contains('Enter-RouterRegistryLock') -and $moduleScript.Contains('Enter-RouterRegistryLock')) 'Registries do not share verified lock recovery.'
    foreach ($requiredText in @("'MarkDeliveryDegraded'","'RecordReplacementHealth'","'Degraded'",'deliveryRecovery','BackgroundWorkEvidence','One-replacement cap reached')) { Assert-Router ($threadScript.Contains($requiredText)) "Thread Registry delivery recovery is missing: $requiredText" }
    foreach ($requiredText in @("'SetDeliveryState'","'RecordDeliveryReceipt'","'ReconcileDelivery'","'RequestRedelivery'","'AcknowledgeDelivery'",'DELIVERY_RECEIPT_RECORDED','DELIVERY_RECONCILIATION_RECEIPT_MISSING','DELIVERY_REDELIVERY_REQUESTED','DELIVERY_ACKNOWLEDGED','DELIVERY_EVIDENCE_CONFLICT','Assert-SafeDeliverySummary')) { Assert-Router ($threadScript.Contains($requiredText)) "Thread Registry delivery reliability is missing: $requiredText" }
    foreach ($requiredText in @('processStartTimeUtc','createdAt','registryPath','Test-RouterVerifiedStaleLock')) { Assert-Router ($lockScript.Contains($requiredText)) "Registry lock evidence is missing: $requiredText" }
    Assert-Router ($manager.Contains('自动可视化团队路由器 V1.3.3') -and $manager.Contains("version = '1.3.3'")) 'Managed AGENTS contract is not V1.3.3.'

    $numbered = [regex]::Matches($acceptance,'(?m)^(\d+)\.\s')
    Assert-Router ($numbered.Count -eq 115) "Expected 115 acceptance items, found $($numbered.Count)."
    if ($numbered.Count -eq 115) { for($i=1;$i -le 115;$i++){ Assert-Router ([int]$numbered[$i-1].Groups[1].Value -eq $i) "Acceptance numbering breaks at $i." } }

    $parseErrors = @()
    Get-ChildItem -LiteralPath $SkillRoot -Filter '*.ps1' -File -Recurse | ForEach-Object {
        $tokens=$null; $errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        foreach($error in @($errors)){ $parseErrors += "$($_.FullName): $($error.Message)" }
    }
    Assert-Router ($parseErrors.Count -eq 0) "PowerShell parse errors: $($parseErrors -join '; ')"

    foreach ($branch in @('codex/stage2c-developer','codex/backend','codex/frontend-lifecycle')) {
        & git check-ref-format --branch $branch 2>$null | Out-Null
        Assert-Router ($LASTEXITCODE -eq 0) "Invalid Git fixture branch: $branch"
    }

    $markerState = [pscustomobject]@{begin=0;end=0}
    if ($Mode -eq 'Installed') {
        if (-not $AgentsPath) {
            $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
            $AgentsPath = Join-Path $codexHome 'AGENTS.md'
        }
        Assert-Router (Test-Path -LiteralPath $AgentsPath) "Installed AGENTS.md not found: $AgentsPath"
        if (Test-Path -LiteralPath $AgentsPath) {
            $agents = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($AgentsPath),$utf8)
            $markerState.begin = ([regex]::Matches($agents,'<!-- BEGIN auto-visible-team-router:v1(?: separatorChars=\d+)? -->')).Count
            $markerState.end = ([regex]::Matches($agents,[regex]::Escape('<!-- END auto-visible-team-router:v1 -->'))).Count
            Assert-Router ($markerState.begin -eq 1 -and $markerState.end -eq 1) 'Installed validation requires exactly one managed block.'
            Assert-Router ($agents.Contains('自动可视化团队路由器 V1.3.3')) 'Installed managed block is not V1.3.3.'
        }
    }
}

[pscustomobject]@{
    suite='V1.3.3 static validation'; mode=$Mode; skillRoot=$SkillRoot; version=$(if($version){$version}else{$null})
    requiredFiles=$required.Count; acceptanceItems=$(if($numbered){$numbered.Count}else{0}); registrySchema=2; moduleRegistrySchema=1
    markers=$markerState; failures=$failures; passed=($failures.Count -eq 0)
} | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) { exit 1 }
