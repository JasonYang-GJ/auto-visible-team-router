[CmdletBinding()]
param(
    [ValidateSet('Init','Status','GetProject','FindModule','PreviewModule','SetProjectMode','UpsertModule','AcquireLease','RefreshLease','ReleaseLease','MarkLeaseStale')]
    [string]$Action = 'Status',
    [string]$RegistryPath,
    [string]$ProjectId,
    [string]$ProjectName,
    [string]$ProjectPath,
    [ValidateSet('Shadow','Active')]
    [string]$Mode = 'Shadow',
    [string]$AuthorizedAt,
    [string]$AuthorizationEvidence,
    [string]$AuthorizedProjectKey,
    [string]$AuthorizationBaselineCommit,
    [string]$ArchitectureMapEvidence,
    [string]$ModuleId,
    [string]$ModuleName,
    [string[]]$Responsibilities,
    [string[]]$Paths,
    [string]$OwnerRole,
    [string]$OwnerThreadId,
    [string[]]$Dependencies,
    [string[]]$Dependents,
    [ValidateSet('ACTIVE','MIGRATING','LEGACY','REMOVABLE','UNKNOWN')]
    [string]$ModuleState = 'UNKNOWN',
    [ValidateSet('Confirmed','Inferred','Unknown')]
    [string]$Confidence = 'Unknown',
    [string[]]$Sources,
    [string]$VerifiedAt,
    [string]$VerifiedAgainstCommit,
    [string]$LeaseId,
    [string]$WriterThreadId,
    [string]$TaskId,
    [string]$PacketId,
    [ValidateRange(0,2147483647)]
    [int]$PacketVersion = 0,
    [string]$Worktree,
    [string]$Branch,
    [switch]$DetachedWorktree,
    [string[]]$AllowedPaths,
    [string]$BaseCommit,
    [string]$AcquiredAt,
    [string]$LastVerifiedAt,
    [ValidateRange(5,1440)]
    [int]$LeaseMinutes = 120,
    [string]$ReleaseReason,
    [string]$VerificationEvidence,
    [ValidateRange(1,60)]
    [int]$LockStaleMinutes = 5
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Bound = $PSBoundParameters
. (Join-Path $PSScriptRoot 'Registry-Lock.ps1')

if (-not $RegistryPath) {
    $scriptSkillRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $installedSuffix = [System.IO.Path]::Combine('.agents', 'skills', 'auto-visible-team-router')
    $routerCodexHome = if ($scriptSkillRoot.EndsWith($installedSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $installedUserProfile = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptSkillRoot))
        [System.IO.Path]::GetFullPath((Join-Path $installedUserProfile '.codex'))
    } elseif ($env:CODEX_HOME) {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    } else {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    }
    $RegistryPath = Join-Path $routerCodexHome 'auto-visible-team-router\module-registry.json'
}
$RegistryPath = [System.IO.Path]::GetFullPath($RegistryPath)

function New-RegistryDocument {
    [pscustomobject]@{ schemaVersion=1; updatedAt=(Get-Date).ToString('o'); projects=@(); events=@() }
}

function Convert-ToStringArray([object]$Value) {
    @($Value | ForEach-Object {
        if ($null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_)) { ([string]$_).Trim() }
    } | Sort-Object -Unique)
}

function Convert-ToScopeArray([object]$Value) {
    @($Value | ForEach-Object {
        if ($null -eq $_ -or [string]::IsNullOrWhiteSpace([string]$_)) { return }
        $scope = ([string]$_).Trim().Replace('\','/').TrimStart('./').TrimEnd('/').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($scope)) { throw 'AllowedPaths cannot contain the repository root.' }
        if ($scope.IndexOfAny([char[]]'*?[]') -ge 0) { throw "AllowedPaths must use concrete paths, not wildcards: $scope" }
        $scope
    } | Sort-Object -Unique)
}

function Get-ProjectKey {
    if (-not [string]::IsNullOrWhiteSpace($ProjectId)) { return 'id:' + $ProjectId.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        return 'path:' + [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/').ToLowerInvariant()
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { return 'name:' + $ProjectName.Trim().ToLowerInvariant() }
    throw 'ProjectId, ProjectPath, or ProjectName is required.'
}

function Add-MissingProperty([object]$Target, [string]$Name, [object]$Value) {
    if ($Target.PSObject.Properties.Name -notcontains $Name) { $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Read-Registry {
    if (-not (Test-Path -LiteralPath $RegistryPath)) { return New-RegistryDocument }
    $raw = [System.IO.File]::ReadAllText($RegistryPath, $utf8NoBom)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Module Registry is empty: $RegistryPath" }
    try { $doc = $raw | ConvertFrom-Json } catch { throw "Module Registry is corrupt; no automatic recovery was attempted: $RegistryPath" }
    if ($doc.schemaVersion -ne 1) { throw "Unsupported Module Registry schema: $($doc.schemaVersion)" }
    Add-MissingProperty $doc 'projects' @()
    Add-MissingProperty $doc 'events' @()
    foreach ($project in @($doc.projects)) {
        Add-MissingProperty $project 'modules' @()
        Add-MissingProperty $project 'writeLeases' @()
        Add-MissingProperty $project 'modeAuthorization' $null
    }
    return $doc
}

function Write-Registry([object]$Document) {
    $parent = Split-Path -Parent $RegistryPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $Document.updatedAt = (Get-Date).ToString('o')
    $temp = Join-Path $parent ('.module-registry-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Document | ConvertTo-Json -Depth 24
        [System.IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $utf8NoBom)
        if (Test-Path -LiteralPath $RegistryPath) {
            $knownGood = [System.IO.File]::ReadAllText($RegistryPath, $utf8NoBom) | ConvertFrom-Json
            if ($knownGood.schemaVersion -ne 1) { throw 'Refusing to back up an unverified Module Registry.' }
            Copy-Item -LiteralPath $RegistryPath -Destination ($RegistryPath + '.bak') -Force
        }
        [System.IO.File]::Move($temp, $RegistryPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Find-Project([object]$Document, [string]$ProjectKey) {
    @($Document.projects | Where-Object { $_.projectKey -eq $ProjectKey }) | Select-Object -First 1
}

function Ensure-Project([object]$Document, [string]$ProjectKey) {
    $project = Find-Project $Document $ProjectKey
    if ($null -ne $project) { return $project }
    $project = [pscustomobject]@{
        projectKey=$ProjectKey; projectId=$ProjectId; projectName=$ProjectName; projectPath=$ProjectPath
        mode='Shadow'; modeAuthorization=$null; lastVerifiedAt=$null; verifiedAgainstCommit=$null
        modules=@(); writeLeases=@()
    }
    $Document.projects = @($Document.projects) + $project
    return $project
}

function Add-Event([object]$Document, [string]$Type, [string]$ProjectKey, [object]$Details) {
    $Document.events = @($Document.events) + [pscustomobject]@{
        at=(Get-Date).ToString('o'); type=$Type; projectKey=$ProjectKey; details=$Details
    }
}

function Set-ObjectProperty([object]$Target, [string]$Name, [object]$Value) {
    if ($Target.PSObject.Properties.Name -contains $Name) { $Target.$Name = $Value }
    else { $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function New-ModuleCandidate {
    [pscustomobject]@{
        id=$ModuleId; name=$ModuleName; responsibilities=Convert-ToStringArray $Responsibilities
        paths=Convert-ToStringArray $Paths; ownerRole=$OwnerRole; ownerThreadId=$OwnerThreadId
        dependencies=Convert-ToStringArray $Dependencies; dependents=Convert-ToStringArray $Dependents
        state=$ModuleState; confidence=$Confidence; sources=Convert-ToStringArray $Sources
        verifiedAt=$VerifiedAt; verifiedAgainstCommit=$VerifiedAgainstCommit
    }
}

function Assert-ModuleRecord([object]$Module) {
    if ([string]::IsNullOrWhiteSpace([string]$Module.id)) { throw 'ModuleId is required.' }
    if ($Module.confidence -eq 'Confirmed') {
        foreach ($required in @(
            @{name='ModuleName';value=$Module.name}, @{name='Responsibilities';value=@($Module.responsibilities)},
            @{name='Paths';value=@($Module.paths)}, @{name='OwnerRole';value=$Module.ownerRole},
            @{name='State';value=$Module.state}, @{name='Sources';value=@($Module.sources)},
            @{name='VerifiedAt';value=$Module.verifiedAt}, @{name='VerifiedAgainstCommit';value=$Module.verifiedAgainstCommit}
        )) {
            $missing = if ($required.value -is [array]) { $required.value.Count -eq 0 } else { [string]::IsNullOrWhiteSpace([string]$required.value) }
            if ($missing) { throw "Confirmed module requires $($required.name)." }
        }
        if ($Module.state -eq 'UNKNOWN') { throw 'Confirmed module requires a known lifecycle state.' }
    }
    if ($Module.confidence -eq 'Inferred' -and @($Module.sources).Count -eq 0) { throw 'Inferred module requires at least one evidence source.' }
    foreach ($field in @('dependencies','dependents')) { Add-MissingProperty $Module $field @() }
}

function Update-ModulePatch([object]$Existing) {
    $candidate = if ($null -eq $Existing) { New-ModuleCandidate } else { $Existing }
    $mapping = @{
        ModuleName='name'; Responsibilities='responsibilities'; Paths='paths'; OwnerRole='ownerRole';
        OwnerThreadId='ownerThreadId'; Dependencies='dependencies'; Dependents='dependents'; ModuleState='state';
        Confidence='confidence'; Sources='sources'; VerifiedAt='verifiedAt'; VerifiedAgainstCommit='verifiedAgainstCommit'
    }
    foreach ($parameter in $mapping.Keys) {
        if ($null -eq $Existing -or $script:Bound.ContainsKey($parameter)) {
            $value = Get-Variable -Name $parameter -ValueOnly
            if ($parameter -in @('Responsibilities','Paths','Dependencies','Dependents','Sources')) { $value = Convert-ToStringArray $value }
            Set-ObjectProperty $candidate $mapping[$parameter] $value
        }
    }
    Assert-ModuleRecord $candidate
    return $candidate
}

function Assert-ActiveAuthorization([string]$ProjectKey) {
    foreach ($required in @(
        @{name='AuthorizedAt';value=$AuthorizedAt}, @{name='AuthorizationEvidence';value=$AuthorizationEvidence},
        @{name='AuthorizedProjectKey';value=$AuthorizedProjectKey}
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "$($required.name) is required to enable Active mode." }
    }
    [void][datetimeoffset]::Parse($AuthorizedAt)
    if (-not $AuthorizedProjectKey.Equals($ProjectKey, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "AuthorizedProjectKey must exactly match the resolved project: $ProjectKey"
    }
    if ([string]::IsNullOrWhiteSpace($AuthorizationBaselineCommit) -and [string]::IsNullOrWhiteSpace($ArchitectureMapEvidence)) {
        throw 'Active mode requires AuthorizationBaselineCommit or ArchitectureMapEvidence.'
    }
}

function Assert-ValidBranch([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Branch is required unless DetachedWorktree is set.' }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        & git check-ref-format --branch $Name 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Invalid Git branch name: $Name" }
    }
}

function Test-PathScopeConflict([string]$Left, [string]$Right) {
    if ($Left -eq $Right) { return $true }
    return $Left.StartsWith($Right + '/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LeaseExactMatch([object]$Lease, [object]$Request) {
    $leaseDetached = if ($Lease.PSObject.Properties.Name -contains 'detachedWorktree') { [bool]$Lease.detachedWorktree } else { $Lease.branch -eq 'DETACHED' }
    $leasePacketId = if ($Lease.PSObject.Properties.Name -contains 'packetId') { [string]$Lease.packetId } else { [string]$Lease.taskId }
    $leasePacketVersion = if ($Lease.PSObject.Properties.Name -contains 'packetVersion') { [int]$Lease.packetVersion } else { 0 }
    $leasePaths = @(Convert-ToScopeArray $Lease.allowedPaths) -join [char]31
    $requestPaths = @($Request.allowedPaths) -join [char]31
    return (
        $Lease.moduleId -eq $Request.moduleId -and $Lease.writerThreadId -eq $Request.writerThreadId -and
        $Lease.taskId -eq $Request.taskId -and $leasePacketId -eq $Request.packetId -and
        $leasePacketVersion -eq $Request.packetVersion -and
        ([System.IO.Path]::GetFullPath([string]$Lease.worktree)).Equals($Request.worktree,[System.StringComparison]::OrdinalIgnoreCase) -and
        $leaseDetached -eq $Request.detachedWorktree -and [string]$Lease.branch -eq $Request.branch -and
        [string]$Lease.baseCommit -eq $Request.baseCommit -and $leasePaths -eq $requestPaths
    )
}

$writeActions = @('Init','SetProjectMode','UpsertModule','AcquireLease','RefreshLease','ReleaseLease','MarkLeaseStale')
$lock = $null
try {
    if ($writeActions -contains $Action) { $lock = Enter-RouterRegistryLock $RegistryPath 2000 $LockStaleMinutes }
    $document = Read-Registry
    $projectKey = if ($Action -in @('Status','Init')) { $null } else { Get-ProjectKey }

    switch ($Action) {
        'Status' {
            $projects = @($document.projects)
            $modules = @($projects | ForEach-Object { @($_.modules) })
            $leases = @($projects | ForEach-Object { @($_.writeLeases) })
            $result = [pscustomobject]@{
                action='Status'; exists=(Test-Path -LiteralPath $RegistryPath); schemaVersion=1
                projectCount=$projects.Count; moduleCount=$modules.Count
                activeLeaseCount=@($leases | Where-Object { $_.state -eq 'Active' }).Count
                registryPath=$RegistryPath; backupPath=$RegistryPath + '.bak'
            }
        }
        'Init' {
            if (-not (Test-Path -LiteralPath $RegistryPath)) { Write-Registry $document }
            $result = [pscustomobject]@{ action='Init'; schemaVersion=1; registryPath=$RegistryPath }
        }
        'GetProject' {
            $project = Find-Project $document $projectKey
            $result = [pscustomobject]@{ action='GetProject'; found=($null -ne $project); project=$project }
        }
        'FindModule' {
            if ([string]::IsNullOrWhiteSpace($ModuleId)) { throw 'ModuleId is required.' }
            $project = Find-Project $document $projectKey
            $module = if ($null -eq $project) { $null } else { @($project.modules | Where-Object { $_.id -eq $ModuleId }) | Select-Object -First 1 }
            $result = [pscustomobject]@{ action='FindModule'; found=($null -ne $module); module=$module }
        }
        'PreviewModule' {
            if ([string]::IsNullOrWhiteSpace($ModuleId) -or [string]::IsNullOrWhiteSpace($ModuleName)) { throw 'ModuleId and ModuleName are required.' }
            $result = [pscustomobject]@{ action='PreviewModule'; mode='Shadow'; persisted=$false; projectKey=$projectKey; module=New-ModuleCandidate }
        }
        'SetProjectMode' {
            $project = Ensure-Project $document $projectKey
            $previousMode = [string]$project.mode
            if ($Mode -eq 'Active') {
                Assert-ActiveAuthorization $projectKey
                $project.modeAuthorization = [pscustomobject]@{
                    authorizedAt=[datetimeoffset]::Parse($AuthorizedAt).ToString('o')
                    evidence=$AuthorizationEvidence; authorizedProjectKey=$projectKey
                    baselineCommit=$AuthorizationBaselineCommit; architectureMapEvidence=$ArchitectureMapEvidence
                }
            } elseif ($previousMode -eq 'Active') {
                $activeLeases = @($project.writeLeases | Where-Object { $_.state -eq 'Active' })
                if ($activeLeases.Count -gt 0) { throw 'Active to Shadow transition is blocked while Active leases remain.' }
            }
            $project.mode = $Mode
            if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { $project.projectName = $ProjectName }
            if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $project.projectPath = $ProjectPath }
            Add-Event $document 'ProjectModeSet' $projectKey ([pscustomobject]@{ previousMode=$previousMode; newMode=$Mode; authorization=$project.modeAuthorization })
            Write-Registry $document
            $result = [pscustomobject]@{ action='SetProjectMode'; previousMode=$previousMode; project=$project }
        }
        'UpsertModule' {
            if ([string]::IsNullOrWhiteSpace($ModuleId)) { throw 'ModuleId is required.' }
            $project = Find-Project $document $projectKey
            if ($null -eq $project -or $project.mode -ne 'Active') { throw 'Persistent module records require an existing project in Active mode.' }
            $existing = @($project.modules | Where-Object { $_.id -eq $ModuleId }) | Select-Object -First 1
            $candidate = Update-ModulePatch $existing
            if ($null -eq $existing) { $project.modules = @($project.modules) + $candidate }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.verifiedAt)) { $project.lastVerifiedAt = $candidate.verifiedAt }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.verifiedAgainstCommit)) { $project.verifiedAgainstCommit = $candidate.verifiedAgainstCommit }
            Add-Event $document $(if ($null -eq $existing) { 'ModuleCreated' } else { 'ModulePatched' }) $projectKey ([pscustomobject]@{ moduleId=$ModuleId; commit=$candidate.verifiedAgainstCommit; suppliedFields=@($script:Bound.Keys) })
            Write-Registry $document
            $result = [pscustomobject]@{ action='UpsertModule'; created=($null -eq $existing); module=$candidate }
        }
        'AcquireLease' {
            if ([string]::IsNullOrWhiteSpace($ModuleId) -or [string]::IsNullOrWhiteSpace($WriterThreadId) -or [string]::IsNullOrWhiteSpace($TaskId)) { throw 'ModuleId, WriterThreadId, and TaskId are required.' }
            if ($PacketVersion -lt 1) { throw 'PacketVersion must be at least 1.' }
            if ([string]::IsNullOrWhiteSpace($Worktree) -or [string]::IsNullOrWhiteSpace($BaseCommit)) { throw 'Worktree and BaseCommit are required.' }
            $normalizedPaths = @(Convert-ToScopeArray $AllowedPaths)
            if ($normalizedPaths.Count -eq 0) { throw 'AllowedPaths is required.' }
            if (-not $DetachedWorktree) { Assert-ValidBranch $Branch }
            $project = Find-Project $document $projectKey
            if ($null -eq $project -or $project.mode -ne 'Active') { throw 'A module lease requires an existing project in Active mode.' }
            if ($null -eq (@($project.modules | Where-Object { $_.id -eq $ModuleId }) | Select-Object -First 1)) { throw "Unknown module: $ModuleId" }
            $request = [pscustomobject]@{
                moduleId=$ModuleId; writerThreadId=$WriterThreadId; taskId=$TaskId
                packetId=$(if ([string]::IsNullOrWhiteSpace($PacketId)) { $TaskId } else { $PacketId }); packetVersion=$PacketVersion
                worktree=[System.IO.Path]::GetFullPath($Worktree)
                branch=$(if ($DetachedWorktree) { 'DETACHED' } else { $Branch }); detachedWorktree=[bool]$DetachedWorktree
                allowedPaths=$normalizedPaths; baseCommit=$BaseCommit
            }
            $sameModuleLease = @($project.writeLeases | Where-Object { $_.moduleId -eq $ModuleId -and $_.state -eq 'Active' }) | Select-Object -First 1
            if ($null -ne $sameModuleLease) {
                if (Test-LeaseExactMatch $sameModuleLease $request) {
                    $result = [pscustomobject]@{ action='AcquireLease'; reused=$true; lease=$sameModuleLease }
                    break
                }
                throw "Active lease differs from the requested scope or baseline. Release/refresh at a safe checkpoint before acquiring a new lease: $($sameModuleLease.id)"
            }
            foreach ($other in @($project.writeLeases | Where-Object { $_.state -eq 'Active' })) {
                foreach ($requestedPath in $normalizedPaths) {
                    foreach ($existingPath in @(Convert-ToScopeArray $other.allowedPaths)) {
                        if (Test-PathScopeConflict $requestedPath $existingPath) {
                            throw "AllowedPaths conflict with active lease $($other.id): $requestedPath <> $existingPath"
                        }
                    }
                }
            }
            $start = if ([string]::IsNullOrWhiteSpace($AcquiredAt)) { [datetimeoffset]::Now } else { [datetimeoffset]::Parse($AcquiredAt) }
            $lease = [pscustomobject]@{
                id=$(if ([string]::IsNullOrWhiteSpace($LeaseId)) { 'lease-' + [guid]::NewGuid().ToString('N') } else { $LeaseId })
                moduleId=$request.moduleId; writerThreadId=$request.writerThreadId; taskId=$request.taskId
                packetId=$request.packetId; packetVersion=$request.packetVersion; worktree=$request.worktree
                branch=$request.branch; detachedWorktree=$request.detachedWorktree; allowedPaths=$request.allowedPaths
                baseCommit=$request.baseCommit; acquiredAt=$start.ToString('o')
                lastVerifiedAt=$(if ([string]::IsNullOrWhiteSpace($LastVerifiedAt)) { $start.ToString('o') } else { [datetimeoffset]::Parse($LastVerifiedAt).ToString('o') })
                expiresAt=$start.AddMinutes($LeaseMinutes).ToString('o'); state='Active'
                releasedAt=$null; releaseReason=$null; verificationEvidence=$VerificationEvidence
            }
            $project.writeLeases = @($project.writeLeases) + $lease
            Add-Event $document 'LeaseAcquired' $projectKey ([pscustomobject]@{ leaseId=$lease.id; moduleId=$ModuleId; threadId=$WriterThreadId; packetId=$lease.packetId; packetVersion=$lease.packetVersion })
            Write-Registry $document
            $result = [pscustomobject]@{ action='AcquireLease'; reused=$false; lease=$lease }
        }
        'RefreshLease' {
            if ([string]::IsNullOrWhiteSpace($LeaseId) -or [string]::IsNullOrWhiteSpace($WriterThreadId) -or [string]::IsNullOrWhiteSpace($LastVerifiedAt) -or [string]::IsNullOrWhiteSpace($VerificationEvidence)) { throw 'LeaseId, WriterThreadId, LastVerifiedAt, and VerificationEvidence are required.' }
            $project = Find-Project $document $projectKey
            $lease = if ($null -eq $project) { $null } else { @($project.writeLeases | Where-Object { $_.id -eq $LeaseId }) | Select-Object -First 1 }
            if ($null -eq $lease -or $lease.state -ne 'Active') { throw 'Active lease not found.' }
            if ($lease.writerThreadId -ne $WriterThreadId) { throw 'Only the recorded writer may refresh this lease.' }
            $verified = [datetimeoffset]::Parse($LastVerifiedAt)
            $lease.lastVerifiedAt=$verified.ToString('o'); $lease.expiresAt=$verified.AddMinutes($LeaseMinutes).ToString('o'); $lease.verificationEvidence=$VerificationEvidence
            Add-Event $document 'LeaseRefreshed' $projectKey ([pscustomobject]@{ leaseId=$LeaseId })
            Write-Registry $document
            $result = [pscustomobject]@{ action='RefreshLease'; lease=$lease }
        }
        'ReleaseLease' {
            if ([string]::IsNullOrWhiteSpace($LeaseId) -or [string]::IsNullOrWhiteSpace($WriterThreadId) -or [string]::IsNullOrWhiteSpace($ReleaseReason) -or [string]::IsNullOrWhiteSpace($VerificationEvidence)) { throw 'LeaseId, WriterThreadId, ReleaseReason, and VerificationEvidence are required.' }
            $project = Find-Project $document $projectKey
            $lease = if ($null -eq $project) { $null } else { @($project.writeLeases | Where-Object { $_.id -eq $LeaseId }) | Select-Object -First 1 }
            if ($null -eq $lease -or $lease.state -ne 'Active') { throw 'Active lease not found.' }
            if ($lease.writerThreadId -ne $WriterThreadId) { throw 'Only the recorded writer may release this lease.' }
            $lease.state='Released'; $lease.releasedAt=(Get-Date).ToString('o'); $lease.releaseReason=$ReleaseReason; $lease.verificationEvidence=$VerificationEvidence
            Add-Event $document 'LeaseReleased' $projectKey ([pscustomobject]@{ leaseId=$LeaseId; reason=$ReleaseReason })
            Write-Registry $document
            $result = [pscustomobject]@{ action='ReleaseLease'; lease=$lease }
        }
        'MarkLeaseStale' {
            if ([string]::IsNullOrWhiteSpace($LeaseId) -or [string]::IsNullOrWhiteSpace($LastVerifiedAt) -or [string]::IsNullOrWhiteSpace($VerificationEvidence)) { throw 'LeaseId, LastVerifiedAt, and VerificationEvidence are required.' }
            $project = Find-Project $document $projectKey
            $lease = if ($null -eq $project) { $null } else { @($project.writeLeases | Where-Object { $_.id -eq $LeaseId }) | Select-Object -First 1 }
            if ($null -eq $lease -or $lease.state -ne 'Active') { throw 'Active lease not found.' }
            $lease.state='Stale'; $lease.lastVerifiedAt=[datetimeoffset]::Parse($LastVerifiedAt).ToString('o'); $lease.releasedAt=(Get-Date).ToString('o')
            $lease.releaseReason='Verified stale; no automatic takeover'; $lease.verificationEvidence=$VerificationEvidence
            Add-Event $document 'LeaseMarkedStale' $projectKey ([pscustomobject]@{ leaseId=$LeaseId; evidence=$VerificationEvidence })
            Write-Registry $document
            $result = [pscustomobject]@{ action='MarkLeaseStale'; lease=$lease }
        }
    }
    $result | ConvertTo-Json -Depth 24
} finally {
    Exit-RouterRegistryLock $lock
}
