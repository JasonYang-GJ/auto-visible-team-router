[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Status', 'InstallShadow', 'UpdateV2Shadow', 'SetMode', 'EnableTelemetry', 'DisableTelemetry', 'UninstallV2')]
    [string]$Action,

    [string]$SourceRoot,
    [string]$SourceIdentity,
    [string]$CodexHome,
    [string]$SkillRoot,
    [ValidateSet('SHADOW', 'CANARY', 'ACTIVE', 'DISABLED')]
    [string]$Mode = 'SHADOW',
    [string]$ProjectKey,
    [string]$BatchId,
    [switch]$ConfirmSingleRouter,
    [switch]$ConfirmUninstall
)

$ErrorActionPreference = 'Stop'

$v1Pattern = '(?s)<!-- BEGIN auto-visible-team-router:v1 separatorChars=0 -->.*?<!-- END auto-visible-team-router:v1 -->'
$v2Pattern = '(?s)<!-- AUTO_VISIBLE_TEAM_ROUTER_V2 START -->.*?<!-- AUTO_VISIBLE_TEAM_ROUTER_V2 END -->'

function Resolve-CodexHome {
    param([string]$Explicit)
    if ($Explicit) {
        return [System.IO.Path]::GetFullPath($Explicit)
    }
    if ($env:CODEX_HOME) {
        return [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    $userProfilePath = [Environment]::GetFolderPath('UserProfile')
    return [System.IO.Path]::GetFullPath((Join-Path $userProfilePath '.codex'))
}

function Resolve-SkillRoot {
    param([string]$Explicit, [string]$ResolvedCodexHome)
    if ($Explicit) {
        return [System.IO.Path]::GetFullPath($Explicit)
    }

    $profileRoot = Split-Path -Parent $ResolvedCodexHome
    $agentsCandidate = Join-Path $profileRoot '.agents\skills\auto-visible-team-router'
    $codexCandidate = Join-Path $ResolvedCodexHome 'skills\auto-visible-team-router'
    if (Test-Path -LiteralPath $agentsCandidate) {
        return [System.IO.Path]::GetFullPath($agentsCandidate)
    }
    if (Test-Path -LiteralPath $codexCandidate) {
        return [System.IO.Path]::GetFullPath($codexCandidate)
    }
    return [System.IO.Path]::GetFullPath($agentsCandidate)
}

function Assert-ProjectKeyFormat {
    param([string]$Value)
    if ($Value -notmatch '^(id|git|path):.+') {
        throw 'ProjectKey must use id:, git:, or path: identity.'
    }
}

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $result
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += , (ConvertTo-Hashtable $item)
        }
        return $items
    }
    return $InputObject
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return ConvertTo-Hashtable (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Write-TextAtomic {
    param([string]$Path, [string]$Value)
    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $temporaryPath = "$Path.tmp"
    [System.IO.File]::WriteAllText($temporaryPath, $Value, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporaryPath -Destination $Path
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value)
    Write-TextAtomic -Path $Path -Value (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-DirectoryManifest {
    param([string]$Root)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $entries = @()
    foreach ($file in Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse | Sort-Object FullName) {
        $relative = $file.FullName.Substring($resolvedRoot.Length + 1).Replace('\', '/')
        $entries += [ordered]@{
            path = $relative
            bytes = $file.Length
            sha256 = Get-FileSha256 $file.FullName
        }
    }
    return $entries
}

function Copy-RouterSource {
    param([string]$Source, [string]$Destination)
    $sourceVersionPath = Join-Path $Source 'VERSION'
    if (-not (Test-Path -LiteralPath $sourceVersionPath)) {
        throw 'SourceRoot is missing VERSION.'
    }
    if ((Get-Content -LiteralPath $sourceVersionPath -Raw).Trim() -ne '2.0.0') {
        throw 'SourceRoot VERSION must be 2.0.0.'
    }

    New-Item -ItemType Directory -Path $Destination | Out-Null
    foreach ($fileName in @('README.md', 'SKILL.md', 'VERSION', 'V2_COMPLETE_PLAN.md')) {
        $sourceFile = Join-Path $Source $fileName
        if (-not (Test-Path -LiteralPath $sourceFile)) {
            throw "SourceRoot is missing $fileName."
        }
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $Destination $fileName)
    }
    foreach ($directoryName in @('agents', 'examples', 'references', 'schemas', 'scripts', 'templates', 'tests')) {
        $sourceDirectory = Join-Path $Source $directoryName
        if (-not (Test-Path -LiteralPath $sourceDirectory)) {
            throw "SourceRoot is missing $directoryName."
        }
        Copy-Item -Recurse -LiteralPath $sourceDirectory -Destination (Join-Path $Destination $directoryName)
    }
}

function Get-CanaryBlock {
    param([string]$CanaryProjectKey, [string]$CanaryBatchId)
    return @"
<!-- AUTO_VISIBLE_TEAM_ROUTER_V2 START -->
Auto Visible Team Router V2 is in CANARY mode only for:
- project_key: $CanaryProjectKey
- batch_id: $CanaryBatchId

For that exact batch, route by bounded deliverables, dependencies, disjoint write
ownership, parallel benefit, and evidence-triggered gates. For every other
project or batch, behave as SHADOW: no V2 dispatch, product edits, Worktree or
Branch creation, integration, Registry write, or telemetry write.
Never reuse V1 permanent role Threads. Maximum default simultaneous coding
Workstreams is 3. Fail closed with DUAL_ROUTER_BLOCKED if exclusivity is unclear.
<!-- AUTO_VISIBLE_TEAM_ROUTER_V2 END -->
"@
}

function Set-AgentsRouterBlock {
    param(
        [string]$AgentsPath,
        [string]$TemplateRoot,
        [string]$TargetMode,
        [string]$CanaryProjectKey,
        [string]$CanaryBatchId,
        [switch]$AllowV1Replacement
    )
    if (-not (Test-Path -LiteralPath $AgentsPath)) {
        Write-TextAtomic -Path $AgentsPath -Value ''
    }
    $content = [System.IO.File]::ReadAllText($AgentsPath)
    $v1Matches = [regex]::Matches($content, $v1Pattern)
    $v2Matches = [regex]::Matches($content, $v2Pattern)
    if ($v1Matches.Count -gt 1 -or $v2Matches.Count -gt 1 -or ($v1Matches.Count + $v2Matches.Count) -gt 1) {
        throw 'Multiple managed router blocks found; fail closed.'
    }
    if (-not $AllowV1Replacement -and $v1Matches.Count -gt 0) {
        throw 'DUAL_ROUTER_BLOCKED: a V1 managed block is still active.'
    }

    $block = ''
    switch ($TargetMode) {
        'SHADOW' {
            $block = [System.IO.File]::ReadAllText((Join-Path $TemplateRoot 'templates\AGENTS-v2-shadow.md')).Trim()
        }
        'CANARY' {
            if ([string]::IsNullOrWhiteSpace($CanaryProjectKey) -or [string]::IsNullOrWhiteSpace($CanaryBatchId)) {
                throw 'CANARY requires ProjectKey and BatchId.'
            }
            $block = (Get-CanaryBlock -CanaryProjectKey $CanaryProjectKey -CanaryBatchId $CanaryBatchId).Trim()
        }
        'ACTIVE' {
            $block = [System.IO.File]::ReadAllText((Join-Path $TemplateRoot 'templates\AGENTS-v2-active.md')).Trim()
        }
        'DISABLED' {
            $block = ''
        }
        default {
            throw "Unsupported mode: $TargetMode"
        }
    }

    $routerMatch = if ($v1Matches.Count -eq 1) { $v1Matches[0] } elseif ($v2Matches.Count -eq 1) { $v2Matches[0] } else { $null }
    if ($null -ne $routerMatch) {
        $prefix = $content.Substring(0, $routerMatch.Index).TrimEnd()
        $suffix = $content.Substring($routerMatch.Index + $routerMatch.Length).TrimStart()
        $parts = @($prefix, $block, $suffix) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $newContent = ($parts -join ([Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine
    }
    elseif ($block) {
        $newContent = $content.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
    }
    else {
        $newContent = $content
    }
    Write-TextAtomic -Path $AgentsPath -Value $newContent

    $verified = [System.IO.File]::ReadAllText($AgentsPath)
    $verifiedV1 = [regex]::Matches($verified, $v1Pattern).Count
    $verifiedV2 = [regex]::Matches($verified, $v2Pattern).Count
    if ($TargetMode -eq 'DISABLED') {
        if ($verifiedV1 -ne 0 -or $verifiedV2 -ne 0) {
            throw 'Router disable verification failed.'
        }
    }
    elseif ($verifiedV1 -ne 0 -or $verifiedV2 -ne 1) {
        throw 'Router block mutual-exclusion verification failed.'
    }
}

function Write-BackupManifest {
    param([string]$BackupRoot)
    $manifestPath = Join-Path $BackupRoot 'backup-manifest.json'
    $entries = @(Get-DirectoryManifest $BackupRoot | Where-Object { $_.path -ne 'backup-manifest.json' })
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAt = (Get-Date).ToString('o')
        root = [System.IO.Path]::GetFullPath($BackupRoot)
        files = $entries
    }
    Write-JsonAtomic -Path $manifestPath -Value $manifest

    $loaded = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($entry in $loaded.files) {
        $path = Join-Path $BackupRoot $entry.path
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileSha256 $path) -ne $entry.sha256) {
            throw "Backup verification failed: $($entry.path)"
        }
    }
    return $manifestPath
}

$homePath = Resolve-CodexHome $CodexHome
$resolvedSkillRoot = Resolve-SkillRoot -Explicit $SkillRoot -ResolvedCodexHome $homePath
$runtimeRoot = Join-Path $homePath 'auto-visible-team-router'
$statePath = Join-Path $runtimeRoot 'v2-state.json'
$agentsPath = Join-Path $homePath 'AGENTS.md'

switch ($Action) {
    'Status' {
        $agentsContent = if (Test-Path -LiteralPath $agentsPath) { [System.IO.File]::ReadAllText($agentsPath) } else { '' }
        [pscustomobject]@{
            CodexHome = $homePath
            SkillInstalled = Test-Path -LiteralPath $resolvedSkillRoot
            SkillPath = $resolvedSkillRoot
            InstalledVersion = if (Test-Path -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION')) {
                (Get-Content -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION') -Raw).Trim()
            }
            else {
                $null
            }
            RuntimePath = $runtimeRoot
            V2State = Read-JsonFile $statePath
            ActiveV1BlockCount = [regex]::Matches($agentsContent, $v1Pattern).Count
            ActiveV2BlockCount = [regex]::Matches($agentsContent, $v2Pattern).Count
            LegacyThreadRegistryPresent = Test-Path -LiteralPath (Join-Path $runtimeRoot 'thread-registry.json')
            LegacyModuleRegistryPresent = Test-Path -LiteralPath (Join-Path $runtimeRoot 'module-registry.json')
            V2WorkstreamRegistryPresent = Test-Path -LiteralPath (Join-Path $runtimeRoot 'workstream-registry.json')
            LegacyArchives = @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot 'legacy-v1') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        } | ConvertTo-Json -Depth 30
        break
    }

    'InstallShadow' {
        if (-not $SourceRoot) {
            throw 'InstallShadow requires SourceRoot.'
        }
        $source = [System.IO.Path]::GetFullPath($SourceRoot)
        if (-not (Test-Path -LiteralPath $resolvedSkillRoot)) {
            throw 'Installed V1 Skill is missing; this command performs an in-place V1 upgrade only.'
        }
        $installedVersionPath = Join-Path $resolvedSkillRoot 'VERSION'
        if (-not (Test-Path -LiteralPath $installedVersionPath) -or
            (Get-Content -LiteralPath $installedVersionPath -Raw).Trim() -ne '1.3.3') {
            throw 'Installed Skill must be V1.3.3 before InstallShadow.'
        }

        $agentsBefore = if (Test-Path -LiteralPath $agentsPath) { [System.IO.File]::ReadAllText($agentsPath) } else { '' }
        if ([regex]::Matches($agentsBefore, $v1Pattern).Count -ne 1 -or
            [regex]::Matches($agentsBefore, $v2Pattern).Count -ne 0) {
            throw 'Expected exactly one V1 managed AGENTS block and no V2 block.'
        }

        New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $backupRoot = Join-Path $runtimeRoot "backups\v1-pre-v2-$stamp"
        $runtimeSnapshot = Join-Path $backupRoot 'runtime-state'
        $legacyArchive = Join-Path $runtimeRoot "legacy-v1\$stamp"
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
        New-Item -ItemType Directory -Path $runtimeSnapshot | Out-Null

        Copy-Item -Recurse -LiteralPath $resolvedSkillRoot -Destination (Join-Path $backupRoot 'installed-skill')
        if (Test-Path -LiteralPath $agentsPath) {
            Copy-Item -LiteralPath $agentsPath -Destination (Join-Path $backupRoot 'AGENTS.md')
        }
        foreach ($item in Get-ChildItem -LiteralPath $runtimeRoot -Force) {
            if ($item.Name -in @('backups', 'legacy-v1')) {
                continue
            }
            Copy-Item -Recurse -Force -LiteralPath $item.FullName -Destination (Join-Path $runtimeSnapshot $item.Name)
        }
        $backupManifestPath = Write-BackupManifest $backupRoot

        $skillParent = Split-Path -Parent $resolvedSkillRoot
        New-Item -ItemType Directory -Force -Path $skillParent | Out-Null
        $stagingRoot = Join-Path $skillParent "auto-visible-team-router-v2-staging-$stamp"
        Copy-RouterSource -Source $source -Destination $stagingRoot
        $stagedValidation = @(& (Join-Path $stagingRoot 'scripts\Validate-Router.ps1') -Root $stagingRoot)
        if ($stagedValidation -notcontains 'V2_OFFLINE_VALIDATION_PASS') {
            throw "Staged V2 validation failed: $($stagedValidation -join '; ')"
        }

        $oldSkillSwap = Join-Path $skillParent "auto-visible-team-router-v1-live-$stamp"
        try {
            Move-Item -LiteralPath $resolvedSkillRoot -Destination $oldSkillSwap
            Move-Item -LiteralPath $stagingRoot -Destination $resolvedSkillRoot
            Move-Item -LiteralPath $oldSkillSwap -Destination (Join-Path $backupRoot 'installed-skill-live')

            New-Item -ItemType Directory -Force -Path $legacyArchive | Out-Null
            foreach ($name in @('thread-registry.json', 'thread-registry.json.bak', 'module-registry.json', 'module-registry.json.bak')) {
                $legacyPath = Join-Path $runtimeRoot $name
                if (Test-Path -LiteralPath $legacyPath) {
                    Move-Item -LiteralPath $legacyPath -Destination (Join-Path $legacyArchive $name)
                }
            }

            $freshRegistry = [ordered]@{
                schemaVersion = 1
                defaults = [ordered]@{ worktreeBudget = 3; maxCodingLanes = 3 }
                projects = [ordered]@{}
            }
            Write-JsonAtomic -Path (Join-Path $runtimeRoot 'workstream-registry.json') -Value $freshRegistry

            Set-AgentsRouterBlock -AgentsPath $agentsPath -TemplateRoot $resolvedSkillRoot -TargetMode 'SHADOW' -AllowV1Replacement
            $state = [ordered]@{
                schemaVersion = 1
                version = '2.0.0'
                mode = 'SHADOW'
                telemetryEnabled = $false
                canary = $null
                installedAt = (Get-Date).ToString('o')
                skillRoot = $resolvedSkillRoot
                rollbackBackup = $backupRoot
                backupManifest = $backupManifestPath
                legacyArchive = $legacyArchive
                legacyRegistryPolicy = 'ARCHIVED_NOT_MIGRATED'
            }
            Write-JsonAtomic -Path $statePath -Value $state

            $status = & $PSCommandPath -Action Status -CodexHome $homePath -SkillRoot $resolvedSkillRoot | ConvertFrom-Json
            if ($status.InstalledVersion -ne '2.0.0' -or
                $status.ActiveV1BlockCount -ne 0 -or
                $status.ActiveV2BlockCount -ne 1 -or
                -not $status.V2WorkstreamRegistryPresent) {
                throw 'V2 SHADOW post-install verification failed.'
            }
        }
        catch {
            $installedVersionDuringFailure = if (Test-Path -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION')) {
                (Get-Content -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION') -Raw).Trim()
            }
            else {
                $null
            }
            if ($installedVersionDuringFailure -eq '2.0.0') {
                Remove-Item -Recurse -Force -LiteralPath $resolvedSkillRoot
            }
            if (-not (Test-Path -LiteralPath $resolvedSkillRoot)) {
                if (Test-Path -LiteralPath $oldSkillSwap) {
                    Move-Item -LiteralPath $oldSkillSwap -Destination $resolvedSkillRoot
                }
                elseif (Test-Path -LiteralPath (Join-Path $backupRoot 'installed-skill')) {
                    Copy-Item -Recurse -LiteralPath (Join-Path $backupRoot 'installed-skill') -Destination $resolvedSkillRoot
                }
            }
            if (Test-Path -LiteralPath (Join-Path $backupRoot 'AGENTS.md')) {
                Copy-Item -Force -LiteralPath (Join-Path $backupRoot 'AGENTS.md') -Destination $agentsPath
            }
            foreach ($name in @('thread-registry.json', 'thread-registry.json.bak', 'module-registry.json', 'module-registry.json.bak', 'v2-state.json', 'workstream-registry.json')) {
                $originalPath = Join-Path $runtimeSnapshot $name
                $activePath = Join-Path $runtimeRoot $name
                if (Test-Path -LiteralPath $originalPath) {
                    Copy-Item -Force -LiteralPath $originalPath -Destination $activePath
                }
                elseif (Test-Path -LiteralPath $activePath) {
                    Remove-Item -LiteralPath $activePath
                }
            }
            throw
        }

        Write-Output 'V2_SHADOW_INSTALLED_IN_PLACE'
        Write-Output "Skill=$resolvedSkillRoot"
        Write-Output "Backup=$backupRoot"
        Write-Output "LegacyArchive=$legacyArchive"
        break
    }

    'UpdateV2Shadow' {
        if (-not $SourceRoot) {
            throw 'UpdateV2Shadow requires SourceRoot.'
        }
        if ([string]::IsNullOrWhiteSpace($SourceIdentity) -or $SourceIdentity -notmatch '^[0-9a-fA-F]{40,64}$') {
            throw 'UpdateV2Shadow requires an exact SourceIdentity Git object ID.'
        }
        $source = [System.IO.Path]::GetFullPath($SourceRoot)
        $state = Read-JsonFile $statePath
        if ($null -eq $state -or $state['version'] -ne '2.0.0') {
            throw 'Installed V2 runtime state is missing or invalid.'
        }
        if (-not (Test-Path -LiteralPath $resolvedSkillRoot) -or
            (Get-Content -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION') -Raw).Trim() -ne '2.0.0') {
            throw 'UpdateV2Shadow requires an existing V2.0.0 installation.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $source 'VERSION')) -or
            (Get-Content -LiteralPath (Join-Path $source 'VERSION') -Raw).Trim() -ne '2.0.0') {
            throw 'UpdateV2Shadow source must be V2.0.0.'
        }

        $agentsBefore = if (Test-Path -LiteralPath $agentsPath) { [System.IO.File]::ReadAllText($agentsPath) } else { '' }
        if ([regex]::Matches($agentsBefore, $v1Pattern).Count -ne 0 -or
            [regex]::Matches($agentsBefore, $v2Pattern).Count -ne 1) {
            throw 'UpdateV2Shadow requires exactly one active V2 block and no V1 block.'
        }

        New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $backupRoot = Join-Path $runtimeRoot "backups\v2-pre-update-$stamp"
        $runtimeSnapshot = Join-Path $backupRoot 'runtime-state'
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
        New-Item -ItemType Directory -Path $runtimeSnapshot | Out-Null
        Copy-Item -Recurse -LiteralPath $resolvedSkillRoot -Destination (Join-Path $backupRoot 'installed-skill')
        Copy-Item -LiteralPath $agentsPath -Destination (Join-Path $backupRoot 'AGENTS.md')
        foreach ($name in @('v2-state.json', 'workstream-registry.json', 'workstream-registry.json.bak')) {
            $activePath = Join-Path $runtimeRoot $name
            if (Test-Path -LiteralPath $activePath) {
                Copy-Item -LiteralPath $activePath -Destination (Join-Path $runtimeSnapshot $name)
            }
        }
        $updateManifestPath = Write-BackupManifest $backupRoot

        $skillParent = Split-Path -Parent $resolvedSkillRoot
        $stagingRoot = Join-Path $skillParent "auto-visible-team-router-v2-update-staging-$stamp"
        Copy-RouterSource -Source $source -Destination $stagingRoot
        $stagedValidation = @(& (Join-Path $stagingRoot 'scripts\Validate-Router.ps1') -Root $stagingRoot)
        if ($stagedValidation -notcontains 'V2_OFFLINE_VALIDATION_PASS') {
            throw "Staged V2 update validation failed: $($stagedValidation -join '; ')"
        }

        $oldSkillSwap = Join-Path $skillParent "auto-visible-team-router-v2-live-$stamp"
        try {
            Move-Item -LiteralPath $resolvedSkillRoot -Destination $oldSkillSwap
            Move-Item -LiteralPath $stagingRoot -Destination $resolvedSkillRoot

            $freshRegistry = [ordered]@{
                schemaVersion = 1
                defaults = [ordered]@{ worktreeBudget = 3; maxCodingLanes = 3 }
                projects = [ordered]@{}
            }
            Write-JsonAtomic -Path (Join-Path $runtimeRoot 'workstream-registry.json') -Value $freshRegistry
            $registryBackupPath = Join-Path $runtimeRoot 'workstream-registry.json.bak'
            if (Test-Path -LiteralPath $registryBackupPath) {
                Move-Item -Force -LiteralPath $registryBackupPath -Destination (Join-Path $runtimeSnapshot 'workstream-registry.json.bak.after-swap')
            }

            Set-AgentsRouterBlock -AgentsPath $agentsPath -TemplateRoot $resolvedSkillRoot -TargetMode 'SHADOW'
            $state['mode'] = 'SHADOW'
            $state['canary'] = $null
            $state['telemetryEnabled'] = $false
            $state['installedSourceIdentity'] = $SourceIdentity.ToLowerInvariant()
            $state['previousV2Backup'] = $backupRoot
            $state['previousV2BackupManifest'] = $updateManifestPath
            $state['updatedAt'] = (Get-Date).ToString('o')
            Write-JsonAtomic -Path $statePath -Value $state

            Move-Item -LiteralPath $oldSkillSwap -Destination (Join-Path $backupRoot 'installed-skill-live')
            $updateManifestPath = Write-BackupManifest $backupRoot
            $state = Read-JsonFile $statePath
            $state['previousV2BackupManifest'] = $updateManifestPath
            Write-JsonAtomic -Path $statePath -Value $state

            $status = & $PSCommandPath -Action Status -CodexHome $homePath -SkillRoot $resolvedSkillRoot | ConvertFrom-Json
            $freshRegistryCheck = Get-Content -LiteralPath (Join-Path $runtimeRoot 'workstream-registry.json') -Raw | ConvertFrom-Json
            if ($status.InstalledVersion -ne '2.0.0' -or
                $status.ActiveV1BlockCount -ne 0 -or
                $status.ActiveV2BlockCount -ne 1 -or
                $status.V2State.mode -ne 'SHADOW' -or
                $status.V2State.installedSourceIdentity -ne $SourceIdentity.ToLowerInvariant() -or
                @($freshRegistryCheck.projects.PSObject.Properties).Count -ne 0) {
                throw 'V2 exact SHADOW update post-install verification failed.'
            }
        }
        catch {
            if (Test-Path -LiteralPath $resolvedSkillRoot) {
                Remove-Item -Recurse -Force -LiteralPath $resolvedSkillRoot
            }
            if (Test-Path -LiteralPath $oldSkillSwap) {
                Move-Item -LiteralPath $oldSkillSwap -Destination $resolvedSkillRoot
            }
            elseif (Test-Path -LiteralPath (Join-Path $backupRoot 'installed-skill')) {
                Copy-Item -Recurse -LiteralPath (Join-Path $backupRoot 'installed-skill') -Destination $resolvedSkillRoot
            }
            Copy-Item -Force -LiteralPath (Join-Path $backupRoot 'AGENTS.md') -Destination $agentsPath
            foreach ($name in @('v2-state.json', 'workstream-registry.json', 'workstream-registry.json.bak')) {
                $snapshotPath = Join-Path $runtimeSnapshot $name
                $activePath = Join-Path $runtimeRoot $name
                if (Test-Path -LiteralPath $snapshotPath) {
                    Copy-Item -Force -LiteralPath $snapshotPath -Destination $activePath
                }
                elseif (Test-Path -LiteralPath $activePath) {
                    Remove-Item -LiteralPath $activePath
                }
            }
            throw
        }

        Write-Output 'V2_EXACT_SHADOW_UPDATE_PASS'
        Write-Output "SourceIdentity=$($SourceIdentity.ToLowerInvariant())"
        Write-Output "PreviousV2Backup=$backupRoot"
        break
    }

    'SetMode' {
        $state = Read-JsonFile $statePath
        if ($null -eq $state -or $state['version'] -ne '2.0.0') {
            throw 'V2 state missing or invalid. InstallShadow first.'
        }
        if ($Mode -in @('CANARY', 'ACTIVE') -and -not $ConfirmSingleRouter) {
            throw "$Mode requires ConfirmSingleRouter."
        }
        if ($Mode -eq 'CANARY' -and
            ([string]::IsNullOrWhiteSpace($ProjectKey) -or [string]::IsNullOrWhiteSpace($BatchId))) {
            throw 'CANARY requires ProjectKey and BatchId.'
        }
        if ($Mode -eq 'CANARY') {
            Assert-ProjectKeyFormat $ProjectKey
        }

        $agentsContent = if (Test-Path -LiteralPath $agentsPath) { [System.IO.File]::ReadAllText($agentsPath) } else { '' }
        if ([regex]::Matches($agentsContent, $v1Pattern).Count -gt 0) {
            throw 'DUAL_ROUTER_BLOCKED: V1 managed AGENTS block remains.'
        }
        Set-AgentsRouterBlock -AgentsPath $agentsPath -TemplateRoot $resolvedSkillRoot -TargetMode $Mode -CanaryProjectKey $ProjectKey -CanaryBatchId $BatchId

        if ($Mode -eq 'CANARY') {
            $state['canary'] = [ordered]@{
                projectKey = $ProjectKey
                batchId = $BatchId
                authorizedAt = (Get-Date).ToString('o')
            }
        }
        else {
            $state['canary'] = $null
        }
        $state['mode'] = $Mode
        $state['updatedAt'] = (Get-Date).ToString('o')
        Write-JsonAtomic -Path $statePath -Value $state
        Write-Output "V2_MODE=$Mode"
        break
    }

    'EnableTelemetry' {
        $state = Read-JsonFile $statePath
        if ($null -eq $state) {
            throw 'V2 state missing.'
        }
        $state['telemetryEnabled'] = $true
        $state['updatedAt'] = (Get-Date).ToString('o')
        Write-JsonAtomic -Path $statePath -Value $state
        Write-Output 'V2_TELEMETRY=ENABLED'
        break
    }

    'DisableTelemetry' {
        $state = Read-JsonFile $statePath
        if ($null -eq $state) {
            throw 'V2 state missing.'
        }
        $state['telemetryEnabled'] = $false
        $state['updatedAt'] = (Get-Date).ToString('o')
        Write-JsonAtomic -Path $statePath -Value $state
        Write-Output 'V2_TELEMETRY=DISABLED'
        break
    }

    'UninstallV2' {
        if (-not $ConfirmUninstall) {
            throw 'UninstallV2 requires ConfirmUninstall.'
        }
        if (Test-Path -LiteralPath $resolvedSkillRoot) {
            if ((Get-Content -LiteralPath (Join-Path $resolvedSkillRoot 'VERSION') -Raw).Trim() -ne '2.0.0') {
                throw 'Refusing to remove a non-V2 Skill root.'
            }
            Remove-Item -Recurse -Force -LiteralPath $resolvedSkillRoot
        }
        Set-AgentsRouterBlock -AgentsPath $agentsPath -TemplateRoot $resolvedSkillRoot -TargetMode 'DISABLED'
        Write-Output 'V2_SKILL_REMOVED; runtime, backups, and legacy archives retained.'
        break
    }
}
