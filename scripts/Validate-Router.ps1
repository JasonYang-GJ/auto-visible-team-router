[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]

function Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$required = @(
    'SKILL.md',
    'README.md',
    'VERSION',
    'references\modes-and-mutual-exclusion.md',
    'references\project-identity.md',
    'references\repository-containment.md',
    'references\workstream-routing.md',
    'references\execution-backends.md',
    'references\platform-capability-history.md',
    'references\dependency-planning.md',
    'references\context-delegation.md',
    'references\risk-gates.md',
    'references\thread-lifecycle.md',
    'references\git-worktree-safety.md',
    'references\delivery-reliability.md',
    'references\telemetry-ab.md',
    'references\migration-v1.md',
    'references\canary-runbook.md',
    'references\acceptance-tests.md',
    'scripts\Manage-Global.ps1',
    'scripts\Resolve-ProjectIdentity.ps1',
    'scripts\Resolve-RepositoryContainment.ps1',
    'scripts\Resolve-Route.ps1',
    'scripts\Resolve-ExecutionBackend.ps1',
    'scripts\Workstream-Registry.ps1',
    'scripts\ReadOnly-Guard.ps1',
    'schemas\defaults.json',
    'schemas\project-identity.schema.json',
    'schemas\repository-containment.schema.json',
    'schemas\route-proposal.schema.json',
    'schemas\workstream-registry.schema.json',
    'tests\scenarios.json',
    'tests\Run-OfflineGate.ps1',
    'tests\Run-ReleaseCandidateGate.ps1',
    'tests\validate_package.py',
    'tests\Test-InstallRollback.ps1',
    'tests\Test-ManagementLifecycle.ps1',
    'tests\Test-ReadOnlyGuard.ps1',
    'tests\Test-RouteAcceptance.ps1',
    'tests\Test-BackendSelection.ps1',
    'tests\Test-PlatformAdaptedSynthetic.ps1',
    'tests\Test-ProjectIdentity.ps1',
    'tests\Test-RepositoryContainment.ps1',
    'tests\Test-WorkstreamRegistry.ps1'
)

foreach ($rel in $required) {
    Check (Test-Path -LiteralPath (Join-Path $Root $rel)) "Missing required file: $rel"
}

$defaultsPath = Join-Path $Root 'schemas\defaults.json'
if (Test-Path $defaultsPath) {
    $defaults = Get-Content $defaultsPath -Raw | ConvertFrom-Json
    Check ($defaults.defaultMode -eq 'SHADOW') 'defaultMode must be SHADOW.'
    Check ($defaults.maxCodingLanes -eq 3) 'maxCodingLanes must be 3.'
    Check ($defaults.worktreeBudget -eq 3) 'worktreeBudget must be 3.'
    Check ($defaults.defaultExecutionBackend -eq 'CURRENT_THREAD') 'CURRENT_THREAD must be the default backend.'
    Check ($defaults.executionBackends.AUTO_VISIBLE_WORKTREE.availability -eq 'UNSUPPORTED') 'AUTO_VISIBLE_WORKTREE must be unsupported.'
    Check (-not $defaults.executionBackends.AUTO_VISIBLE_WORKTREE.productionDispatchEnabled) 'AUTO_VISIBLE_WORKTREE dispatch must be disabled.'
    Check ($defaults.executionBackends.COLLAB_SUBAGENT.codingParallelism -eq 'FORBIDDEN') 'Shared-worktree collaboration coding must be forbidden.'
    Check ($defaults.parallelBackendUnavailablePolicy -eq 'SERIALIZED_FALLBACK') 'Parallel backend degradation must serialize.'
    Check (-not $defaults.telemetryEnabledByDefault) 'Telemetry must default off.'
    Check (($defaults.registryKey -join '+') -eq 'projectKey+batchId+workstreamId') 'Registry key must be project+batch+workstream.'
    Check (($defaults.projectIdentityPriority -join '+') -eq 'APP_PROJECT_ID+GIT_ROOT+CANONICAL_PATH') 'Project identity priority is invalid.'
    Check (($defaults.projectKeyPrefixes -join '+') -eq 'id:+git:+path:') 'Project key prefixes are invalid.'
    Check (-not $defaults.projectIdRequired) 'projectId must be preferred, not required.'
    Check (-not $defaults.threadCwdIsProjectIdentity) 'Thread cwd must not be Project Identity.'
    Check ($defaults.repositoryContainmentResolver -eq 'scripts/Resolve-RepositoryContainment.ps1') 'Containment resolver path is invalid.'
    Check ($defaults.activeRouterMutualExclusionRequired) 'Single-router mutual exclusion must be required.'
}

$managePath = Join-Path $Root 'scripts\Manage-Global.ps1'
if (Test-Path $managePath) {
    $manage = Get-Content $managePath -Raw
    Check ($manage.Contains('[string]$SkillRoot')) 'Management must support the real installed Skill path.'
    Check ($manage.Contains('Set-AgentsRouterBlock')) 'Management must replace the managed AGENTS block.'
    Check ($manage.Contains('legacy-v1')) 'Management must archive V1 Registry state.'
    Check ($manage.Contains('workstream-registry.json')) 'Management must initialize the V2 Registry.'
    Check ($manage.Contains("'UpdateV2Shadow'")) 'Management must support exact V2-to-V2 SHADOW update.'
    Check ($manage.Contains('[string]$SourceIdentity')) 'Exact V2 update must record SourceIdentity.'
    Check ($manage.Contains('previousV2Backup')) 'Exact V2 update must preserve the previous installation.'
}

$registryPath = Join-Path $Root 'scripts\Workstream-Registry.ps1'
if (Test-Path $registryPath) {
    $registry = Get-Content $registryPath -Raw
    Check ($registry.Contains('WORKSTREAM_REGISTRY_LOCKED')) 'Registry writes must fail closed on lock contention.'
    Check ($registry.Contains('BatchId') -and $registry.Contains('WorkstreamId')) 'Registry identity must be batch/workstream based.'
    Check (-not $registry.Contains('Role')) 'Registry must not use permanent Role identity.'
}

$identityResolverPath = Join-Path $Root 'scripts\Resolve-ProjectIdentity.ps1'
if (Test-Path $identityResolverPath) {
    $identityResolver = Get-Content $identityResolverPath -Raw
    Check ($identityResolver.Contains('APP_PROJECT_ID')) 'Project Identity resolver must support app-native Project ID.'
    Check ($identityResolver.Contains('GIT_ROOT')) 'Project Identity resolver must support canonical Git root.'
    Check ($identityResolver.Contains('CANONICAL_PATH')) 'Project Identity resolver must support canonical path.'
    Check ($identityResolver.Contains('PROJECT_IDENTITY_BLOCKED')) 'Project Identity resolver must fail closed when all sources are unavailable.'
}

$containmentResolverPath = Join-Path $Root 'scripts\Resolve-RepositoryContainment.ps1'
if (Test-Path $containmentResolverPath) {
    $containmentResolver = Get-Content $containmentResolverPath -Raw
    Check ($containmentResolver.Contains('git-common-dir')) 'Containment resolver must compare git-common-dir.'
    Check ($containmentResolver.Contains('worktree') -and $containmentResolver.Contains('--porcelain')) 'Containment resolver must inspect canonical worktree inventory.'
    Check ($containmentResolver.Contains('UNRELATED_CHECKOUT')) 'Containment resolver must distinguish unrelated checkouts.'
    Check ($containmentResolver.Contains('UNATTRIBUTED_DIRTY_STATE')) 'Containment resolver must block unattributed dirty state.'
    Check ($containmentResolver.Contains('BASELINE_LINEAGE_UNEXPLAINED')) 'Containment resolver must verify Batch lineage.'
}

foreach ($retired in @(
    'references\routing-policy.md',
    'references\role-catalog.md',
    'references\module-governance.md',
    'scripts\Thread-Registry.ps1',
    'scripts\Module-Registry.ps1',
    'scripts\Validate-V1.3.3.ps1'
)) {
    Check (-not (Test-Path -LiteralPath (Join-Path $Root $retired))) "Conflicting V1 file remains: $retired"
}

$skillPath = Join-Path $Root 'SKILL.md'
if (Test-Path $skillPath) {
    $skill = Get-Content $skillPath -Raw
    Check ($skill -match 'Default mode is `SHADOW`') 'SKILL must declare SHADOW default.'
    Check ($skill -match 'Every additional Agent must own an independent') 'Missing extra-agent hard rule.'
    Check ($skill -match 'default maximum number of simultaneous coding Workstreams is \*\*3\*\*') 'Missing lane cap.'
    Check ($skill -match 'DUAL_ROUTER_BLOCKED') 'Missing dual-router block.'
    Check ($skill -match 'project_key \+ batch_id \+ workstream_id') 'Missing V2 identity.'
    Check ($skill -match '`thread\.projectId` is preferred evidence, not a hard requirement') 'SKILL must not require projectId.'
    Check ($skill -match 'Logical routing is separate from execution placement') 'Logical routes must be decoupled from execution placement.'
    Check ($skill -match '`AUTO_VISIBLE_WORKTREE` — `UNSUPPORTED`') 'AUTO_VISIBLE_WORKTREE platform freeze is missing.'
    Check ($skill -match '`SERIALIZED_FALLBACK`') 'Serialized fallback contract is missing.'
}

foreach ($jsonRel in @('schemas\defaults.json','schemas\project-identity.schema.json','schemas\repository-containment.schema.json','schemas\route-proposal.schema.json','schemas\workstream-registry.schema.json','tests\scenarios.json')) {
    $p = Join-Path $Root $jsonRel
    if (Test-Path $p) {
        try { $null = Get-Content $p -Raw | ConvertFrom-Json }
        catch { $failures.Add("Invalid JSON: $jsonRel :: $($_.Exception.Message)") }
    }
}

if ($failures.Count -gt 0) {
    Write-Output 'V2_OFFLINE_VALIDATION_FAIL'
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}

Write-Output 'V2_OFFLINE_VALIDATION_PASS'
Write-Output "Root=$Root"
Write-Output "Checks=$($required.Count + 24)"
