[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$manage = Join-Path $Root 'scripts\Manage-Global.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-management-' + [guid]::NewGuid().ToString('N'))
$codexHome = Join-Path $temporaryRoot 'codex-home'
$skillRoot = Join-Path $temporaryRoot 'agents\skills\auto-visible-team-router'
$runtimeRoot = Join-Path $codexHome 'auto-visible-team-router'
$agentsPath = Join-Path $codexHome 'AGENTS.md'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

try {
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $skillRoot 'VERSION'), "1.3.3`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $skillRoot 'SKILL.md'), "# V1 fixture`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeRoot 'thread-registry.json'),
        '{"schemaVersion":2,"entries":[{"thread":{"id":"legacy-thread"}}]}' + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeRoot 'module-registry.json'),
        '{"schemaVersion":1,"projects":{}}' + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'reports') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'reports\legacy.txt'), "legacy-report`n", [System.Text.UTF8Encoding]::new($false))

    $v1Block = @'
<!-- BEGIN auto-visible-team-router:v1 separatorChars=0 -->
## V1 fixture
<!-- END auto-visible-team-router:v1 -->
'@
    $agentsBefore = "PREFIX-KEPT`n`n$v1Block`n`nSUFFIX-KEPT`n"
    [System.IO.File]::WriteAllText($agentsPath, $agentsBefore, [System.Text.UTF8Encoding]::new($false))

    $installOutput = @(& $manage -Action InstallShadow -SourceRoot $Root -CodexHome $codexHome -SkillRoot $skillRoot)
    Assert-True ($installOutput -contains 'V2_SHADOW_INSTALLED_IN_PLACE') 'InstallShadow did not report success.'

    $status = & $manage -Action Status -CodexHome $codexHome -SkillRoot $skillRoot | ConvertFrom-Json
    Assert-True ($status.InstalledVersion -eq '2.0.0') 'Installed version is not V2.0.0.'
    Assert-True ($status.ActiveV1BlockCount -eq 0 -and $status.ActiveV2BlockCount -eq 1) 'Exactly one V2 block was not established.'
    Assert-True (-not $status.LegacyThreadRegistryPresent -and -not $status.LegacyModuleRegistryPresent) 'Legacy registries remain active.'
    Assert-True $status.V2WorkstreamRegistryPresent 'Fresh V2 Registry is missing.'
    Assert-True ($status.LegacyArchives.Count -eq 1) 'Exactly one legacy archive is required.'

    $state = Get-Content -LiteralPath (Join-Path $runtimeRoot 'v2-state.json') -Raw | ConvertFrom-Json
    Assert-True ($state.mode -eq 'SHADOW' -and -not $state.telemetryEnabled) 'V2 must install in SHADOW with telemetry off.'
    Assert-True (Test-Path -LiteralPath $state.rollbackBackup) 'Rollback backup is missing.'
    Assert-True (Test-Path -LiteralPath $state.backupManifest) 'Backup manifest is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $state.rollbackBackup 'installed-skill\VERSION')) 'Installed V1 Skill backup is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $state.rollbackBackup 'AGENTS.md')) 'AGENTS backup is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $state.rollbackBackup 'runtime-state\thread-registry.json')) 'V1 Thread Registry backup is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $state.legacyArchive 'thread-registry.json')) 'V1 Thread Registry archive is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $state.legacyArchive 'module-registry.json')) 'V1 Module Registry archive is missing.'

    $backupManifest = Get-Content -LiteralPath $state.backupManifest -Raw | ConvertFrom-Json
    foreach ($entry in $backupManifest.files) {
        $path = Join-Path $state.rollbackBackup $entry.path
        Assert-True (Test-Path -LiteralPath $path) "Backup entry is missing: $($entry.path)"
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $entry.sha256) "Backup hash mismatch: $($entry.path)"
    }

    $freshRegistry = Get-Content -LiteralPath (Join-Path $runtimeRoot 'workstream-registry.json') -Raw | ConvertFrom-Json
    Assert-True ($freshRegistry.schemaVersion -eq 1) 'Fresh Registry schema is invalid.'
    Assert-True ($freshRegistry.defaults.worktreeBudget -eq 3 -and $freshRegistry.defaults.maxCodingLanes -eq 3) 'Fresh Registry defaults are invalid.'
    Assert-True (@($freshRegistry.projects.PSObject.Properties).Count -eq 0) 'Fresh Registry must not reinterpret V1 entries.'

    $agentsShadow = [System.IO.File]::ReadAllText($agentsPath)
    Assert-True ($agentsShadow.Contains('PREFIX-KEPT') -and $agentsShadow.Contains('SUFFIX-KEPT')) 'Unrelated AGENTS bytes were not preserved.'
    Assert-True ($agentsShadow.Contains('installed in SHADOW mode')) 'SHADOW block is missing.'
    Assert-True (-not $agentsShadow.Contains('V1 fixture')) 'V1 block remains reachable.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $skillRoot '.git'))) 'Git metadata must not be installed with the Skill.'

    $preUpdateRegistry = @{
        schemaVersion = 1
        defaults = @{ worktreeBudget = 3; maxCodingLanes = 3 }
        projects = @{ 'path:C:\old-v2-evidence' = @{ batches = @{} } }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeRoot 'workstream-registry.json'),
        $preUpdateRegistry + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    $sourceIdentity = ('a' * 40)
    $updateOutput = @(& $manage -Action UpdateV2Shadow -SourceRoot $Root -SourceIdentity $sourceIdentity -CodexHome $codexHome -SkillRoot $skillRoot)
    Assert-True ($updateOutput -contains 'V2_EXACT_SHADOW_UPDATE_PASS') 'UpdateV2Shadow did not report success.'

    $updatedState = Get-Content -LiteralPath (Join-Path $runtimeRoot 'v2-state.json') -Raw | ConvertFrom-Json
    Assert-True ($updatedState.mode -eq 'SHADOW' -and $updatedState.installedSourceIdentity -eq $sourceIdentity) 'Exact source identity was not installed in SHADOW.'
    Assert-True (Test-Path -LiteralPath $updatedState.previousV2Backup) 'Previous V2 backup is missing.'
    Assert-True (Test-Path -LiteralPath $updatedState.previousV2BackupManifest) 'Previous V2 backup manifest is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $updatedState.previousV2Backup 'installed-skill\VERSION')) 'Previous installed V2 Skill was not backed up.'
    $previousRegistry = Get-Content -LiteralPath (Join-Path $updatedState.previousV2Backup 'runtime-state\workstream-registry.json') -Raw | ConvertFrom-Json
    Assert-True ($null -ne $previousRegistry.projects.'path:C:\old-v2-evidence') 'Previous V2 Registry evidence was not preserved.'
    $updatedRegistry = Get-Content -LiteralPath (Join-Path $runtimeRoot 'workstream-registry.json') -Raw | ConvertFrom-Json
    Assert-True (@($updatedRegistry.projects.PSObject.Properties).Count -eq 0) 'Exact V2 update must initialize a fresh Registry.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw).Contains('Logical routing is separate from execution placement')) 'Updated platform-adaptive Skill was not installed.'
    Assert-True ([System.IO.File]::ReadAllText($agentsPath).Contains('installed in SHADOW mode')) 'Exact update must return AGENTS to SHADOW.'

    & $manage -Action SetMode -Mode CANARY -ProjectKey 'path:C:\fixture' -BatchId 'synthetic-v2' -ConfirmSingleRouter -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    $agentsCanary = [System.IO.File]::ReadAllText($agentsPath)
    Assert-True ($agentsCanary.Contains('CANARY mode') -and $agentsCanary.Contains('synthetic-v2')) 'CANARY block is not batch-scoped.'

    & $manage -Action SetMode -Mode ACTIVE -ConfirmSingleRouter -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    $agentsActive = [System.IO.File]::ReadAllText($agentsPath)
    Assert-True ($agentsActive.Contains('V2 is ACTIVE')) 'ACTIVE block is missing.'

    & $manage -Action SetMode -Mode SHADOW -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    & $manage -Action EnableTelemetry -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    & $manage -Action DisableTelemetry -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    $stateAfter = Get-Content -LiteralPath (Join-Path $runtimeRoot 'v2-state.json') -Raw | ConvertFrom-Json
    Assert-True ($stateAfter.mode -eq 'SHADOW' -and -not $stateAfter.telemetryEnabled) 'Mode/telemetry lifecycle is invalid.'

    $v1Conflict = [System.IO.File]::ReadAllText($agentsPath) + [Environment]::NewLine + $v1Block
    [System.IO.File]::WriteAllText($agentsPath, $v1Conflict, [System.Text.UTF8Encoding]::new($false))
    $blocked = $false
    try {
        & $manage -Action SetMode -Mode ACTIVE -ConfirmSingleRouter -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    }
    catch {
        $blocked = $_.Exception.Message -match 'DUAL_ROUTER_BLOCKED|Multiple managed router blocks'
    }
    Assert-True $blocked 'Stale V1 AGENTS coexistence must fail closed.'

    Write-Output 'V2_MANAGEMENT_LIFECYCLE_PASS'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
