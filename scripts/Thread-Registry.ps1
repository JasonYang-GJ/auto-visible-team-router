[CmdletBinding()]
param(
    [ValidateSet('Init','Status','List','Find','Upsert','Adopt','SetState','SetDeliveryState','RecordDeliveryReceipt','ReconcileDelivery','RequestRedelivery','AcknowledgeDelivery','MarkDeliveryDegraded','RecordReplacementHealth','GetProjectBudget','SetProjectBudget')]
    [string]$Action = 'Status',
    [string]$RegistryPath,
    [string]$ProjectId,
    [string]$ProjectName,
    [string]$ProjectPath,
    [string]$Role,
    [string]$ThreadId,
    [string]$Title,
    [ValidateSet('Active','Archived','Stale','Degraded')]
    [string]$State = 'Active',
    [string]$Worktree,
    [string]$Branch,
    [switch]$DetachedWorktree,
    [string]$BaseCommit,
    [string]$WorktreeCreatedAt,
    [ValidateSet('Active','Idle','Completed','Removed','Unknown')]
    [string]$WorktreeState = 'Unknown',
    [ValidateSet('RouterCreated','Adopted','External','Unknown')]
    [string]$WorktreeManagement = 'Unknown',
    [switch]$TemporaryWorktree,
    [ValidateSet('RouterCreated','PreExisting','User','Unknown')]
    [string]$BranchOwnership = 'Unknown',
    [ValidateSet('Active','Merged','Retained','Deleted','Unknown')]
    [string]$BranchState = 'Unknown',
    [switch]$ProtectedBranch,
    [string]$CommitSha,
    [ValidateSet('Pending','PASS','FAIL','NotRequired','Unknown')]
    [string]$QaStatus = 'Unknown',
    [ValidateSet('Pending','Merged','Retained','Unknown')]
    [string]$IntegrationState = 'Unknown',
    [ValidateRange(1,100)]
    [int]$WorktreeBudget = 3,
    [string]$CreatedAt,
    [string]$VerifiedAt,
    [string]$ReplacesThreadId,
    [string]$Purpose,
    [string]$Result,
    [string]$TaskId,
    [ValidateSet('DISPATCHED','RUNNING','WORK_COMPLETED','DELIVERY_PENDING')]
    [string]$DeliveryState,
    [ValidateSet('PASS','FAIL','BLOCKED')]
    [string]$ResultStatus,
    [string]$ParentSha,
    [ValidateSet('True','False','NotApplicable')]
    [string]$GitClean = 'NotApplicable',
    [string]$TestsSummary,
    [string]$EvidenceSummary,
    [string]$ReceiptTimestamp,
    [switch]$PrimaryBodyMissing,
    [string]$PrimaryTaskId,
    [string]$PrimaryRole,
    [ValidateSet('PASS','FAIL','BLOCKED')]
    [string]$PrimaryResultStatus,
    [string]$PrimaryCommitSha,
    [string]$PrimaryParentSha,
    [ValidateSet('True','False','NotApplicable')]
    [string]$PrimaryGitClean = 'NotApplicable',
    [string]$PrimaryTestsSummary,
    [string]$PrimaryEvidenceSummary,
    [string]$AcknowledgedAt,
    [string]$IncidentId,
    [string]$FirstFailureRun,
    [string]$RetryRun,
    [ValidateRange(0,1)]
    [int]$DeliveryRetryCount = 0,
    [string]$ObservedState,
    [string]$DirectReadEvidence,
    [string]$OutputEvidence,
    [string]$BackgroundWorkEvidence,
    [string]$ReadOnlyGuardEvidence,
    [string]$DeliveryDetectedAt,
    [string]$DeliveryReason,
    [string]$ReplacementThreadId,
    [ValidateSet('PASS','FAIL')]
    [string]$ReplacementHealth,
    [string]$ReplacementHealthEvidence,
    [switch]$IncludeInactive,
    [ValidateRange(1,60)]
    [int]$LockStaleMinutes = 5
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
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
    $RegistryPath = Join-Path $routerCodexHome 'auto-visible-team-router\thread-registry.json'
}
$RegistryPath = [System.IO.Path]::GetFullPath($RegistryPath)

function New-RegistryDocument {
    [pscustomobject]@{
        schemaVersion = 2
        defaultWorktreeBudget = 3
        updatedAt = (Get-Date).ToString('o')
        projects = @()
        entries = @()
        events = @()
    }
}

function Get-OptionalValue([object]$Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function New-DeliveryRecovery {
    [pscustomobject]@{
        status='UNKNOWN'; incidentId=$null; retryCount=0; firstFailureRun=$null; retryRun=$null
        observedState=$null; directReadEvidence=$null; outputEvidence=$null; backgroundWorkEvidence=$null; readOnlyGuard=$null
        detectedAt=$null; reason=$null; replacementThreadId=$null; replacementHealth=$null
        replacementHealthEvidence=$null
    }
}

function New-DeliveryReceipt {
    [pscustomobject]@{
        taskId=$null; threadId=$null; role=$null; deliveryStatus='UNKNOWN'; resultStatus=$null
        commitSha=$null; parentSha=$null; gitClean=$null; testsSummary=$null; evidenceSummary=$null
        timestamp=$null; receiptHash=$null; redeliveryCount=0; redeliveryOnly=$false
        acknowledgedAt=$null
    }
}

function New-DeliveryRecord {
    [pscustomobject]@{
        commitSha=$null; parentSha=$null; qaStatus='Unknown'; integrationState='Unknown'; resultStatus=$null
        deliveryState='UNKNOWN'; receipt=(New-DeliveryReceipt); reconciliationStatus='NOT_STARTED'
        reconciliationSource=$null; conflicts=@(); reconciledAt=$null
    }
}

function Add-MissingProperty([object]$Object,[string]$Name,[object]$Value) {
    if ($Object.PSObject.Properties.Name -notcontains $Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Initialize-DeliveryRecord([object]$Delivery) {
    if ($null -eq $Delivery) { return (New-DeliveryRecord) }
    Add-MissingProperty $Delivery 'commitSha' $null
    Add-MissingProperty $Delivery 'parentSha' $null
    Add-MissingProperty $Delivery 'qaStatus' 'Unknown'
    Add-MissingProperty $Delivery 'integrationState' 'Unknown'
    Add-MissingProperty $Delivery 'resultStatus' $null
    Add-MissingProperty $Delivery 'deliveryState' 'UNKNOWN'
    Add-MissingProperty $Delivery 'receipt' (New-DeliveryReceipt)
    Add-MissingProperty $Delivery 'reconciliationStatus' 'NOT_STARTED'
    Add-MissingProperty $Delivery 'reconciliationSource' $null
    Add-MissingProperty $Delivery 'conflicts' @()
    Add-MissingProperty $Delivery 'reconciledAt' $null
    if ($null -eq $Delivery.receipt) { $Delivery.receipt = New-DeliveryReceipt }
    foreach ($property in (New-DeliveryReceipt).PSObject.Properties) {
        Add-MissingProperty $Delivery.receipt $property.Name $property.Value
    }
    return $Delivery
}

function Convert-GitCleanValue([string]$Value) {
    if ($Value -eq 'True') { return $true }
    if ($Value -eq 'False') { return $false }
    return $null
}

function Get-NormalizedSummary([string]$Value) {
    if ($null -eq $Value) { return $null }
    return (($Value -replace "`r`n","`n").Trim())
}

function Assert-SafeDeliverySummary([string]$Name,[string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Name is required." }
    if ($Value.Length -gt 1200) { throw "$Name exceeds the 1200-character compact-summary limit." }
    if (@($Value -split "`r?`n").Count -gt 12) { throw "$Name exceeds the 12-line compact-summary limit." }
    $sensitive = '(?i)(api[ _-]?key|password|secret|authorization|credential|bearer\s+[a-z0-9._-]+|sk-[a-z0-9_-]{8,}|prompt\s*(?:body|正文|:)|completion\s*(?:body|正文|:)|reasoning\s*(?:body|正文|:)|raw\s+(?:provider|sse)|完整聊天|chat\s+history)'
    if ($Value -match $sensitive) { throw "$Name contains forbidden sensitive or raw-content material." }
}

function Assert-OptionalSha([string]$Name,[string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '^[0-9a-fA-F]{7,64}$') {
        throw "$Name is not a valid commit identifier."
    }
}

function Get-DeliveryReceiptHash([object]$Receipt) {
    $canonicalTimestamp = [datetimeoffset]::Parse([string]$Receipt.timestamp).ToString('o')
    $canonical = @(
        [string]$Receipt.taskId,[string]$Receipt.threadId,[string]$Receipt.role,[string]$Receipt.resultStatus,
        [string]$Receipt.commitSha,[string]$Receipt.parentSha,[string]$Receipt.gitClean,
        (Get-NormalizedSummary ([string]$Receipt.testsSummary)),
        (Get-NormalizedSummary ([string]$Receipt.evidenceSummary)),$canonicalTimestamp
    ) -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Test-DeliveryReceiptComplete([object]$Receipt) {
    if ($null -eq $Receipt) { return $false }
    foreach ($name in @('taskId','threadId','role','resultStatus','testsSummary','evidenceSummary','timestamp','receiptHash')) {
        if ([string]::IsNullOrWhiteSpace([string]$Receipt.$name)) { return $false }
    }
    return $true
}

function Assert-DeliveryReceiptIntegrity([object]$Entry,[object]$Receipt) {
    if (-not (Test-DeliveryReceiptComplete $Receipt)) { throw 'Delivery Receipt is missing required fields.' }
    if ($Receipt.threadId -cne $Entry.thread.id -or $Receipt.role -cne $Entry.role) { throw 'Delivery Receipt Thread or Role does not match the Registry entry.' }
    if ($Receipt.resultStatus -notin @('PASS','FAIL','BLOCKED')) { throw 'Delivery Receipt ResultStatus is invalid.' }
    [void][datetimeoffset]::Parse([string]$Receipt.timestamp)
    Assert-OptionalSha 'CommitSHA' ([string]$Receipt.commitSha)
    Assert-OptionalSha 'ParentSHA' ([string]$Receipt.parentSha)
    Assert-SafeDeliverySummary 'TestsSummary' ([string]$Receipt.testsSummary)
    Assert-SafeDeliverySummary 'EvidenceSummary' ([string]$Receipt.evidenceSummary)
    if ((Get-DeliveryReceiptHash $Receipt) -cne [string]$Receipt.receiptHash) { throw 'Delivery Receipt hash mismatch.' }
}

function Convert-V1Entry([object]$Legacy) {
    $legacyWorktree = Get-OptionalValue $Legacy 'worktree'
    $legacyBranch = Get-OptionalValue $Legacy 'branch'
    $threadIdValue = Get-OptionalValue $Legacy 'threadId'
    $threadStateValue = Get-OptionalValue $Legacy 'state'
    $worktreeRecord = if (-not [string]::IsNullOrWhiteSpace([string]$legacyWorktree)) {
        [pscustomobject]@{
            path = [string]$legacyWorktree
            threadId = [string]$threadIdValue
            branch = [string]$legacyBranch
            baseCommit = $null
            createdAt = $null
            state = 'Unknown'
            management = 'Unknown'
            createdByRouter = $false
            temporary = $false
            autoDeleteEligible = $false
        }
    } else { $null }
    $branchRecord = if (-not [string]::IsNullOrWhiteSpace([string]$legacyBranch)) {
        [pscustomobject]@{
            name = [string]$legacyBranch
            ownership = 'Unknown'
            protected = [bool]([string]$legacyBranch -match '^(main|master|release(?:/|$)|stable(?:/|$))')
            state = 'Unknown'
            autoDeleteEligible = $false
        }
    } else { $null }
    [pscustomobject]@{
        projectKey = Get-OptionalValue $Legacy 'projectKey'
        projectId = Get-OptionalValue $Legacy 'projectId'
        projectName = Get-OptionalValue $Legacy 'projectName'
        projectPath = Get-OptionalValue $Legacy 'projectPath'
        role = Get-OptionalValue $Legacy 'role'
        thread = [pscustomobject]@{
            id = $threadIdValue
            title = Get-OptionalValue $Legacy 'title'
            createdAt = Get-OptionalValue $Legacy 'createdAt'
            lastVerifiedAt = Get-OptionalValue $Legacy 'lastVerifiedAt'
            state = $(if ($threadStateValue) { $threadStateValue } else { 'Stale' })
            origin = 'Legacy'
            adoptedAt = $null
        }
        worktree = $worktreeRecord
        branch = $branchRecord
        delivery = New-DeliveryRecord
        deliveryRecovery = New-DeliveryRecovery
        replacesThreadId = Get-OptionalValue $Legacy 'replacesThreadId'
        purpose = Get-OptionalValue $Legacy 'purpose'
        result = Get-OptionalValue $Legacy 'result'
    }
}

function Read-RegistryDocument {
    if (-not (Test-Path -LiteralPath $RegistryPath)) { return (New-RegistryDocument) }
    $raw = [System.IO.File]::ReadAllText($RegistryPath, $utf8NoBom)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Registry is empty: $RegistryPath" }
    try { $doc = $raw | ConvertFrom-Json } catch { throw "Thread Registry is corrupt; no automatic recovery was attempted: $RegistryPath" }
    if ($doc.schemaVersion -eq 1) {
        $migrated = New-RegistryDocument
        $migrated.entries = @($doc.entries | ForEach-Object { Convert-V1Entry $_ })
        $migrated.events = @($doc.events) + [pscustomobject]@{ at=(Get-Date).ToString('o'); type='SchemaMigration'; from=1; to=2 }
        return $migrated
    }
    if ($doc.schemaVersion -ne 2) { throw "Unsupported registry schema: $($doc.schemaVersion)" }
    if ($null -eq $doc.projects) { $doc | Add-Member -NotePropertyName projects -NotePropertyValue @() }
    if ($null -eq $doc.entries) { $doc | Add-Member -NotePropertyName entries -NotePropertyValue @() }
    if ($null -eq $doc.events) { $doc | Add-Member -NotePropertyName events -NotePropertyValue @() }
    if ($null -eq $doc.defaultWorktreeBudget) { $doc | Add-Member -NotePropertyName defaultWorktreeBudget -NotePropertyValue 3 }
    foreach ($entry in @($doc.entries)) {
        $entry.delivery = Initialize-DeliveryRecord $entry.delivery
        if ($entry.PSObject.Properties.Name -notcontains 'deliveryRecovery' -or $null -eq $entry.deliveryRecovery) {
            $entry | Add-Member -NotePropertyName deliveryRecovery -NotePropertyValue (New-DeliveryRecovery) -Force
        }
    }
    return $doc
}

function Get-ProjectKey {
    if (-not [string]::IsNullOrWhiteSpace($ProjectId)) { return "id:$ProjectId" }
    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        return 'path:' + ([System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/').ToLowerInvariant())
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { return 'name:' + $ProjectName.Trim().ToLowerInvariant() }
    throw 'ProjectId, ProjectPath, or ProjectName is required.'
}

function Save-RegistryDocument([object]$Document) {
    $Document.updatedAt = (Get-Date).ToString('o')
    $parent = Split-Path -Parent $RegistryPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tempPath = $RegistryPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $json = $Document | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($tempPath, $json + [Environment]::NewLine, $utf8NoBom)
    try {
        if (Test-Path -LiteralPath $RegistryPath) {
            $knownGood = [System.IO.File]::ReadAllText($RegistryPath, $utf8NoBom) | ConvertFrom-Json
            if ($knownGood.schemaVersion -notin @(1,2)) { throw 'Refusing to back up an unverified Thread Registry.' }
            Copy-Item -LiteralPath $RegistryPath -Destination ($RegistryPath + '.bak') -Force
        }
        [System.IO.File]::Move($tempPath, $RegistryPath, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Write-Result([object]$Value) { $Value | ConvertTo-Json -Depth 20 }

function Get-ThreadState([object]$Entry) {
    if ($null -eq $Entry.thread) { return $null }
    return $Entry.thread.state
}

function Get-ProjectBudgetRecord([object]$Document, [string]$Key) {
    return @($Document.projects) | Where-Object { $_.projectKey -eq $Key } | Select-Object -First 1
}

function Get-ProjectBudgetStatus([object]$Document, [string]$Key) {
    $project = Get-ProjectBudgetRecord $Document $Key
    $budget = if ($project) { [int]$project.worktreeBudget } else { [int]$Document.defaultWorktreeBudget }
    $managedEntries = @($Document.entries | Where-Object {
        $_.projectKey -eq $Key -and $null -ne $_.worktree -and
        $_.worktree.management -in @('RouterCreated','Adopted') -and $_.worktree.state -ne 'Removed'
    })
    $retainedPaths = @($managedEntries | ForEach-Object { $_.worktree.path } | Where-Object { $_ } | Sort-Object -Unique)
    $activePaths = @($managedEntries | Where-Object { $_.worktree.state -eq 'Active' } | ForEach-Object { $_.worktree.path } | Where-Object { $_ } | Sort-Object -Unique)
    $idlePaths = @($managedEntries | Where-Object { $_.worktree.state -eq 'Idle' } | ForEach-Object { $_.worktree.path } | Where-Object { $_ } | Sort-Object -Unique)
    [pscustomobject]@{
        projectKey=$Key; budget=$budget; retainedManagedWorktrees=$retainedPaths.Count
        activeManagedWorktrees=$activePaths.Count; idleManagedWorktrees=$idlePaths.Count
        remaining=[Math]::Max(0, $budget - $retainedPaths.Count); atBudget=($retainedPaths.Count -ge $budget)
        whenReached=@('ReuseIdle','Wait','Serialize'); deleteUnknownToMakeRoom=$false
    }
}

function New-Entry([string]$Origin, [string]$Key, [string]$Now) {
    $isAdoption = $Origin -eq 'Adopted'
    if ($Branch -and $DetachedWorktree) { throw 'Branch and DetachedWorktree cannot be specified together.' }
    $worktreeBranch = if ($DetachedWorktree) { 'DETACHED' } else { $Branch }
    $protected = [bool]($ProtectedBranch -or (-not [string]::IsNullOrWhiteSpace($Branch) -and $Branch -match '^(main|master|release(?:/|$)|stable(?:/|$))'))
    $effectiveManagement = if ($isAdoption -and $Worktree) { 'Adopted' } else { $WorktreeManagement }
    $effectiveBranchOwnership = if ($isAdoption -and $Branch) { 'PreExisting' } else { $BranchOwnership }
    $worktreeRecord = if ($Worktree) {
        [pscustomobject]@{
            path=$Worktree; threadId=$ThreadId; branch=$worktreeBranch; baseCommit=$BaseCommit; createdAt=$WorktreeCreatedAt
            state=$WorktreeState; management=$effectiveManagement; createdByRouter=($effectiveManagement -eq 'RouterCreated')
            temporary=[bool]$(if ($isAdoption) { $false } else { $TemporaryWorktree }); autoDeleteEligible=$false
        }
    } else { $null }
    $branchRecord = if ($Branch) {
        [pscustomobject]@{
            name=$Branch; ownership=$effectiveBranchOwnership; protected=$protected; state=$BranchState
            autoDeleteEligible=[bool]($effectiveBranchOwnership -eq 'RouterCreated' -and -not $protected -and $BranchState -eq 'Merged')
        }
    } else { $null }
    $entry = [pscustomobject]@{
        projectKey=$Key; projectId=$ProjectId; projectName=$ProjectName; projectPath=$ProjectPath; role=$Role
        thread=[pscustomobject]@{
            id=$ThreadId; title=$Title; createdAt=$(if ($CreatedAt) { $CreatedAt } else { $Now })
            lastVerifiedAt=$(if ($VerifiedAt) { $VerifiedAt } else { $null }); state=$State; origin=$Origin
            adoptedAt=$(if ($isAdoption) { $Now } else { $null })
        }
        worktree=$worktreeRecord; branch=$branchRecord
        delivery=New-DeliveryRecord
        deliveryRecovery=New-DeliveryRecovery
        replacesThreadId=$ReplacesThreadId; purpose=$Purpose; result=$Result
    }
    $entry.delivery.commitSha = $CommitSha
    $entry.delivery.parentSha = $ParentSha
    $entry.delivery.qaStatus = $QaStatus
    $entry.delivery.integrationState = $IntegrationState
    return $entry
}

function Assert-UpsertMetadata([string]$Origin) {
    foreach ($required in @(@{Name='Role';Value=$Role},@{Name='ThreadId';Value=$ThreadId},@{Name='Title';Value=$Title})) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for $Action." }
    }
    if ($State -eq 'Degraded') { throw 'Use MarkDeliveryDegraded so delivery evidence cannot be bypassed.' }
    $effectiveManagement = if ($Origin -eq 'Adopted' -and $Worktree) { 'Adopted' } else { $WorktreeManagement }
    if ($effectiveManagement -eq 'RouterCreated' -and $TemporaryWorktree) {
        foreach ($required in @(
            @{Name='Worktree';Value=$Worktree}, @{Name='BaseCommit';Value=$BaseCommit},
            @{Name='WorktreeCreatedAt';Value=$WorktreeCreatedAt}
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for a Router-created temporary worktree." }
        }
        if (-not $Branch -and -not $DetachedWorktree) { throw 'Branch or DetachedWorktree is required for a Router-created temporary worktree.' }
        if ($Branch -and $DetachedWorktree) { throw 'Branch and DetachedWorktree cannot be specified together.' }
        if ($WorktreeState -eq 'Unknown') { throw 'WorktreeState is required for a Router-created temporary worktree.' }
    }
}

$mutating = $Action -in @('Init','Upsert','Adopt','SetState','SetDeliveryState','RecordDeliveryReceipt','ReconcileDelivery','RequestRedelivery','AcknowledgeDelivery','MarkDeliveryDegraded','RecordReplacementHealth','SetProjectBudget')
$lock = $null
try {
    if ($mutating) { $lock = Enter-RouterRegistryLock $RegistryPath 2000 $LockStaleMinutes }
    switch ($Action) {
        'Init' {
            $doc = Read-RegistryDocument
            Save-RegistryDocument $doc
            Write-Result $doc
        }
        'Status' {
            $doc = Read-RegistryDocument
            $entries = @($doc.entries)
            Write-Result ([pscustomobject]@{
                schemaVersion=$doc.schemaVersion; registryPath=$RegistryPath; exists=(Test-Path -LiteralPath $RegistryPath)
                entryCount=$entries.Count; activeCount=@($entries | Where-Object { (Get-ThreadState $_) -eq 'Active' }).Count
                archivedCount=@($entries | Where-Object { (Get-ThreadState $_) -eq 'Archived' }).Count
                staleCount=@($entries | Where-Object { (Get-ThreadState $_) -eq 'Stale' }).Count
                degradedCount=@($entries | Where-Object { (Get-ThreadState $_) -eq 'Degraded' }).Count
                channelUnavailableCount=@($entries | Where-Object { $_.deliveryRecovery.status -eq 'CHANNEL_UNAVAILABLE' }).Count
                deliveryPendingCount=@($entries | Where-Object { $_.delivery.deliveryState -eq 'DELIVERY_PENDING' }).Count
                acknowledgedDeliveryCount=@($entries | Where-Object { $_.delivery.deliveryState -eq 'ACKNOWLEDGED' }).Count
                deliveryConflictCount=@($entries | Where-Object { $_.delivery.deliveryState -eq 'DELIVERY_EVIDENCE_CONFLICT' }).Count
                defaultWorktreeBudget=$doc.defaultWorktreeBudget; updatedAt=$doc.updatedAt
            })
        }
        'List' {
            $doc = Read-RegistryDocument
            $entries = @($doc.entries)
            if (-not $IncludeInactive) { $entries = @($entries | Where-Object { (Get-ThreadState $_) -eq 'Active' }) }
            Write-Result ([pscustomobject]@{registryPath=$RegistryPath; entries=$entries})
        }
        'Find' {
            if ([string]::IsNullOrWhiteSpace($Role)) { throw 'Role is required for Find.' }
            $key = Get-ProjectKey
            $doc = Read-RegistryDocument
            $matches = @($doc.entries | Where-Object {
                $_.projectKey -eq $key -and $_.role -eq $Role -and ($IncludeInactive -or (Get-ThreadState $_) -eq 'Active')
            })
            $entry = $matches | Sort-Object @{Expression={if ((Get-ThreadState $_) -eq 'Active') {1} else {0}};Descending=$true}, @{Expression={$_.thread.lastVerifiedAt};Descending=$true}, @{Expression={$_.thread.createdAt};Descending=$true} | Select-Object -First 1
            Write-Result ([pscustomobject]@{found=($null -ne $entry); projectKey=$key; role=$Role; entry=$entry})
        }
        { $_ -in @('Upsert','Adopt') } {
            $origin = if ($Action -eq 'Adopt') { 'Adopted' } else { 'RouterCreated' }
            Assert-UpsertMetadata $origin
            $key = Get-ProjectKey
            $doc = Read-RegistryDocument
            $entries = @($doc.entries)
            $sameThread = $entries | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            $otherActive = $entries | Where-Object {
                $_.projectKey -eq $key -and $_.role -eq $Role -and $_.thread.state -eq 'Active' -and $_.thread.id -ne $ThreadId
            } | Select-Object -First 1
            if ($otherActive) { throw "Duplicate active role blocked: project=$key role=$Role existing=$($otherActive.thread.id)" }
            if ($ReplacesThreadId) {
                $replaced = $entries | Where-Object { $_.thread.id -eq $ReplacesThreadId } | Select-Object -First 1
                if (-not $replaced) { throw "Replacement target is not registered: $ReplacesThreadId" }
                if ($replaced.thread.state -notin @('Stale','Archived','Degraded')) { throw "Replacement target must be Stale, Archived, or verified Degraded first: $ReplacesThreadId" }
                if ($replaced.thread.state -eq 'Degraded') {
                    if ($replaced.deliveryRecovery.status -ne 'DEGRADED' -or [string]::IsNullOrWhiteSpace([string]$replaced.deliveryRecovery.incidentId)) {
                        throw "Degraded replacement requires a verified delivery incident: $ReplacesThreadId"
                    }
                    $sameIncidentReplacements = @($entries | Where-Object {
                        $_.projectKey -eq $key -and $_.role -eq $Role -and
                        $_.deliveryRecovery.incidentId -eq $replaced.deliveryRecovery.incidentId -and
                        -not [string]::IsNullOrWhiteSpace([string]$_.replacesThreadId)
                    })
                    if (@($sameIncidentReplacements | Where-Object { $_.thread.id -ne $ThreadId }).Count -gt 0) {
                        throw "One-replacement cap reached for delivery incident: $($replaced.deliveryRecovery.incidentId)"
                    }
                }
            }
            $now = (Get-Date).ToString('o')
            $next = New-Entry $origin $key $now
            if ($sameThread) {
                if (-not $ProjectId) { $next.projectId = $sameThread.projectId }
                if (-not $ProjectName) { $next.projectName = $sameThread.projectName }
                if (-not $ProjectPath) { $next.projectPath = $sameThread.projectPath }
                if (-not $PSBoundParameters.ContainsKey('CreatedAt')) { $next.thread.createdAt = $sameThread.thread.createdAt }
                if (-not $PSBoundParameters.ContainsKey('VerifiedAt')) { $next.thread.lastVerifiedAt = $sameThread.thread.lastVerifiedAt }
                if ($Action -eq 'Upsert' -and $sameThread.thread.origin -eq 'Adopted') {
                    $next.thread.origin = 'Adopted'
                    $next.thread.adoptedAt = $sameThread.thread.adoptedAt
                }
                if (-not $PSBoundParameters.ContainsKey('Worktree')) { $next.worktree = $sameThread.worktree }
                if (-not $PSBoundParameters.ContainsKey('Branch') -and -not $PSBoundParameters.ContainsKey('DetachedWorktree')) { $next.branch = $sameThread.branch }
                if (-not $PSBoundParameters.ContainsKey('CommitSha')) { $next.delivery.commitSha = $sameThread.delivery.commitSha }
                if (-not $PSBoundParameters.ContainsKey('ParentSha')) { $next.delivery.parentSha = $sameThread.delivery.parentSha }
                if (-not $PSBoundParameters.ContainsKey('QaStatus')) { $next.delivery.qaStatus = $sameThread.delivery.qaStatus }
                if (-not $PSBoundParameters.ContainsKey('IntegrationState')) { $next.delivery.integrationState = $sameThread.delivery.integrationState }
                $next.delivery.resultStatus = $sameThread.delivery.resultStatus
                $next.delivery.deliveryState = $sameThread.delivery.deliveryState
                $next.delivery.receipt = $sameThread.delivery.receipt
                $next.delivery.reconciliationStatus = $sameThread.delivery.reconciliationStatus
                $next.delivery.reconciliationSource = $sameThread.delivery.reconciliationSource
                $next.delivery.conflicts = $sameThread.delivery.conflicts
                $next.delivery.reconciledAt = $sameThread.delivery.reconciledAt
                if (-not $PSBoundParameters.ContainsKey('Purpose')) { $next.purpose = $sameThread.purpose }
                if (-not $PSBoundParameters.ContainsKey('Result')) { $next.result = $sameThread.result }
                $next.deliveryRecovery = $sameThread.deliveryRecovery
                $entries[[array]::IndexOf($entries,$sameThread)] = $next
            } else {
                $entries += $next
            }
            if ($ReplacesThreadId -and $replaced.thread.state -eq 'Degraded') {
                $next.deliveryRecovery.incidentId = $replaced.deliveryRecovery.incidentId
                $replaced.deliveryRecovery.replacementThreadId = $ThreadId
                $replaced.deliveryRecovery.replacementHealth = 'PENDING'
            }
            $doc.entries = $entries
            $doc.events = @($doc.events) + [pscustomobject]@{
                at=$now; type=$Action; projectKey=$key; role=$Role; threadId=$ThreadId
                previousThreadId=$ReplacesThreadId; state=$State
            }
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action=$Action; entry=$next; registryPath=$RegistryPath})
        }
        'SetState' {
            if ([string]::IsNullOrWhiteSpace($ThreadId)) { throw 'ThreadId is required for SetState.' }
            if ($State -eq 'Degraded') { throw 'Use MarkDeliveryDegraded so delivery evidence cannot be bypassed.' }
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $before = $entry.thread.state
            $entry.thread.state = $State
            if ($VerifiedAt) { $entry.thread.lastVerifiedAt = $VerifiedAt }
            $doc.events = @($doc.events) + [pscustomobject]@{
                at=(Get-Date).ToString('o'); type='SetState'; projectKey=$entry.projectKey; role=$entry.role
                threadId=$ThreadId; previousState=$before; state=$State
            }
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='SetState'; entry=$entry; registryPath=$RegistryPath})
        }
        'SetDeliveryState' {
            foreach ($required in @(@{Name='ThreadId';Value=$ThreadId},@{Name='TaskId';Value=$TaskId},@{Name='DeliveryState';Value=$DeliveryState})) {
                if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for SetDeliveryState." }
            }
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $entry.delivery = Initialize-DeliveryRecord $entry.delivery
            $current = [string]$entry.delivery.deliveryState
            if ($DeliveryState -eq 'DISPATCHED' -and $current -in @('UNKNOWN','ACKNOWLEDGED')) {
                $previousTaskId = $entry.delivery.receipt.taskId
                $previousCommitSha = $entry.delivery.commitSha
                $entry.delivery = New-DeliveryRecord
                $entry.delivery.deliveryState = 'DISPATCHED'
                $entry.delivery.receipt.taskId = $TaskId
                $entry.delivery.receipt.threadId = $entry.thread.id
                $entry.delivery.receipt.role = $entry.role
                $entry.delivery.receipt.deliveryStatus = 'DISPATCHED'
                $doc.events = @($doc.events) + [pscustomobject]@{
                    at=(Get-Date).ToString('o'); type='DeliveryStateChanged'; projectKey=$entry.projectKey; role=$entry.role
                    threadId=$ThreadId; taskId=$TaskId; previousTaskId=$previousTaskId; previousCommitSha=$previousCommitSha
                    previousState=$current; state='DISPATCHED'
                }
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='SetDeliveryState';taskId=$TaskId;threadId=$ThreadId;previousTaskId=$previousTaskId;previousState=$current;deliveryState='DISPATCHED';registryPath=$RegistryPath})
                break
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.delivery.receipt.taskId) -and $entry.delivery.receipt.taskId -cne $TaskId) {
                throw 'Delivery state TaskId does not match the existing assignment.'
            }
            $allowed = @{
                UNKNOWN=@('DISPATCHED'); DISPATCHED=@('RUNNING'); RUNNING=@('WORK_COMPLETED')
                WORK_COMPLETED=@('DELIVERY_PENDING'); DELIVERY_PENDING=@('DELIVERY_PENDING')
            }
            if ($current -cne $DeliveryState -and ($allowed.Keys -notcontains $current -or $allowed[$current] -notcontains $DeliveryState)) {
                throw "Invalid delivery transition: $current -> $DeliveryState"
            }
            $entry.delivery.deliveryState = $DeliveryState
            $entry.delivery.receipt.taskId = $TaskId
            $entry.delivery.receipt.threadId = $entry.thread.id
            $entry.delivery.receipt.role = $entry.role
            $entry.delivery.receipt.deliveryStatus = $DeliveryState
            $doc.events = @($doc.events) + [pscustomobject]@{
                at=(Get-Date).ToString('o'); type='DeliveryStateChanged'; projectKey=$entry.projectKey; role=$entry.role
                threadId=$ThreadId; taskId=$TaskId; previousState=$current; state=$DeliveryState
            }
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='SetDeliveryState';taskId=$TaskId;threadId=$ThreadId;previousState=$current;deliveryState=$DeliveryState;registryPath=$RegistryPath})
        }
        'RecordDeliveryReceipt' {
            foreach ($required in @(
                @{Name='ThreadId';Value=$ThreadId},@{Name='TaskId';Value=$TaskId},@{Name='ResultStatus';Value=$ResultStatus},
                @{Name='TestsSummary';Value=$TestsSummary},@{Name='EvidenceSummary';Value=$EvidenceSummary},@{Name='ReceiptTimestamp';Value=$ReceiptTimestamp}
            )) { if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for RecordDeliveryReceipt." } }
            [void][datetimeoffset]::Parse($ReceiptTimestamp)
            Assert-OptionalSha 'CommitSHA' $CommitSha
            Assert-OptionalSha 'ParentSHA' $ParentSha
            if (-not [string]::IsNullOrWhiteSpace($CommitSha) -and $GitClean -eq 'NotApplicable') { throw 'GitClean is required when CommitSHA is present.' }
            Assert-SafeDeliverySummary 'TestsSummary' $TestsSummary
            Assert-SafeDeliverySummary 'EvidenceSummary' $EvidenceSummary
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $entry.delivery = Initialize-DeliveryRecord $entry.delivery
            if ($entry.delivery.deliveryState -notin @('WORK_COMPLETED','DELIVERY_PENDING')) { throw 'RecordDeliveryReceipt requires WORK_COMPLETED or DELIVERY_PENDING.' }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.delivery.receipt.taskId) -and $entry.delivery.receipt.taskId -cne $TaskId) {
                throw 'Delivery Receipt TaskId does not match the current assignment.'
            }
            $newReceipt = [pscustomobject]@{
                taskId=$TaskId; threadId=$entry.thread.id; role=$entry.role; deliveryStatus='DELIVERY_PENDING'; resultStatus=$ResultStatus
                commitSha=$(if([string]::IsNullOrWhiteSpace($CommitSha)){$null}else{$CommitSha.ToLowerInvariant()})
                parentSha=$(if([string]::IsNullOrWhiteSpace($ParentSha)){$null}else{$ParentSha.ToLowerInvariant()})
                gitClean=(Convert-GitCleanValue $GitClean); testsSummary=(Get-NormalizedSummary $TestsSummary)
                evidenceSummary=(Get-NormalizedSummary $EvidenceSummary); timestamp=[datetimeoffset]::Parse($ReceiptTimestamp).ToString('o')
                receiptHash=$null; redeliveryCount=[int]$entry.delivery.receipt.redeliveryCount
                redeliveryOnly=([int]$entry.delivery.receipt.redeliveryCount -eq 1); acknowledgedAt=$null
            }
            $newReceipt.receiptHash = Get-DeliveryReceiptHash $newReceipt
            if (Test-DeliveryReceiptComplete $entry.delivery.receipt) {
                if ($entry.delivery.receipt.receiptHash -ceq $newReceipt.receiptHash) {
                    Write-Result ([pscustomobject]@{action='RecordDeliveryReceipt';reused=$true;status=$entry.delivery.deliveryState;receipt=$entry.delivery.receipt;registryPath=$RegistryPath})
                    break
                }
                $entry.delivery.deliveryState = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.reconciliationStatus = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.conflicts = @('ReceiptHash')
                $doc.events = @($doc.events) + [pscustomobject]@{at=(Get-Date).ToString('o');type='DELIVERY_EVIDENCE_CONFLICT';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;conflicts=@('ReceiptHash')}
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='RecordDeliveryReceipt';status='DELIVERY_EVIDENCE_CONFLICT';conflicts=@('ReceiptHash');registryPath=$RegistryPath})
                break
            }
            $metadataConflicts = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.delivery.commitSha) -and ([string]$entry.delivery.commitSha).ToLowerInvariant() -cne $newReceipt.commitSha) { $metadataConflicts.Add('CommitSHA') }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.delivery.parentSha) -and ([string]$entry.delivery.parentSha).ToLowerInvariant() -cne $newReceipt.parentSha) { $metadataConflicts.Add('ParentSHA') }
            if ($metadataConflicts.Count -gt 0) {
                $entry.delivery.deliveryState = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.reconciliationStatus = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.conflicts = @($metadataConflicts)
                $doc.events = @($doc.events) + [pscustomobject]@{at=(Get-Date).ToString('o');type='DELIVERY_EVIDENCE_CONFLICT';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;conflicts=@($metadataConflicts)}
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='RecordDeliveryReceipt';status='DELIVERY_EVIDENCE_CONFLICT';conflicts=@($metadataConflicts);registryPath=$RegistryPath})
                break
            }
            $entry.delivery.receipt = $newReceipt
            $entry.delivery.commitSha = $newReceipt.commitSha
            $entry.delivery.parentSha = $newReceipt.parentSha
            $entry.delivery.resultStatus = $newReceipt.resultStatus
            $entry.delivery.deliveryState = 'DELIVERY_PENDING'
            $entry.delivery.reconciliationStatus = 'PENDING'
            $entry.delivery.conflicts = @()
            $doc.events = @($doc.events) + [pscustomobject]@{at=(Get-Date).ToString('o');type='DELIVERY_RECEIPT_RECORDED';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;resultStatus=$ResultStatus;receiptHash=$newReceipt.receiptHash}
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='RecordDeliveryReceipt';reused=$false;status='DELIVERY_PENDING';receipt=$newReceipt;registryPath=$RegistryPath})
        }
        'ReconcileDelivery' {
            foreach ($required in @(@{Name='ThreadId';Value=$ThreadId},@{Name='TaskId';Value=$TaskId})) {
                if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for ReconcileDelivery." }
            }
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $entry.delivery = Initialize-DeliveryRecord $entry.delivery
            $receipt = $entry.delivery.receipt
            if ($entry.delivery.deliveryState -eq 'ACKNOWLEDGED') {
                if ($receipt.taskId -cne $TaskId) { throw 'Reconciliation TaskId does not match the acknowledged Receipt.' }
                Write-Result ([pscustomobject]@{action='ReconcileDelivery';reused=$true;status='ACKNOWLEDGED';resultStatus=$receipt.resultStatus;ackAllowed=$true;registryPath=$RegistryPath})
                break
            }
            if ($entry.delivery.deliveryState -eq 'DELIVERY_EVIDENCE_CONFLICT') {
                Write-Result ([pscustomobject]@{action='ReconcileDelivery';reused=$true;status='DELIVERY_EVIDENCE_CONFLICT';conflicts=@($entry.delivery.conflicts);ackAllowed=$false;registryPath=$RegistryPath})
                break
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$receipt.taskId) -and $receipt.taskId -cne $TaskId) {
                $entry.delivery.deliveryState = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.reconciliationStatus = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.conflicts = @('TaskId')
                $entry.delivery.reconciledAt = (Get-Date).ToString('o')
                $doc.events = @($doc.events) + [pscustomobject]@{at=$entry.delivery.reconciledAt;type='DELIVERY_EVIDENCE_CONFLICT';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;conflicts=@('TaskId')}
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='ReconcileDelivery';status='DELIVERY_EVIDENCE_CONFLICT';conflicts=@('TaskId');ackAllowed=$false;registryPath=$RegistryPath})
                break
            }
            if (-not (Test-DeliveryReceiptComplete $receipt)) {
                $entry.delivery.deliveryState = 'DELIVERY_PENDING'
                $entry.delivery.reconciliationStatus = 'CONTROLLED_DELIVERY_RETRY_REQUIRED'
                $entry.delivery.reconciliationSource = $null
                $entry.delivery.conflicts = @()
                $doc.events = @($doc.events) + [pscustomobject]@{at=(Get-Date).ToString('o');type='DELIVERY_RECONCILIATION_RECEIPT_MISSING';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId}
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='ReconcileDelivery';status='CONTROLLED_DELIVERY_RETRY_REQUIRED';retryMode='REDELIVER';retryCount=[int]$receipt.redeliveryCount;reexecuteAllowed=$false;registryPath=$RegistryPath})
                break
            }
            $integrityConflicts = [System.Collections.Generic.List[string]]::new()
            try { Assert-DeliveryReceiptIntegrity $entry $receipt } catch { $integrityConflicts.Add($_.Exception.Message) }
            if ($receipt.taskId -cne $TaskId) { $integrityConflicts.Add('TaskId') }
            $conflicts = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $integrityConflicts) { $conflicts.Add($item) }
            $source = 'RECEIPT'
            if (-not $PrimaryBodyMissing) {
                foreach ($required in @(
                    @{Name='PrimaryTaskId';Value=$PrimaryTaskId},@{Name='PrimaryRole';Value=$PrimaryRole},@{Name='PrimaryResultStatus';Value=$PrimaryResultStatus},
                    @{Name='PrimaryTestsSummary';Value=$PrimaryTestsSummary},@{Name='PrimaryEvidenceSummary';Value=$PrimaryEvidenceSummary}
                )) { if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required when the primary body is present." } }
                Assert-OptionalSha 'PrimaryCommitSHA' $PrimaryCommitSha
                Assert-OptionalSha 'PrimaryParentSHA' $PrimaryParentSha
                Assert-SafeDeliverySummary 'PrimaryTestsSummary' $PrimaryTestsSummary
                Assert-SafeDeliverySummary 'PrimaryEvidenceSummary' $PrimaryEvidenceSummary
                if ($PrimaryTaskId -cne $receipt.taskId) { $conflicts.Add('TaskId') }
                if ($PrimaryRole -cne $receipt.role) { $conflicts.Add('Role') }
                if ($PrimaryResultStatus -cne $receipt.resultStatus) { $conflicts.Add('ResultStatus') }
                if (([string]$PrimaryCommitSha).ToLowerInvariant() -cne [string]$receipt.commitSha) { $conflicts.Add('CommitSHA') }
                if (([string]$PrimaryParentSha).ToLowerInvariant() -cne [string]$receipt.parentSha) { $conflicts.Add('ParentSHA') }
                if ((Convert-GitCleanValue $PrimaryGitClean) -ne $receipt.gitClean) { $conflicts.Add('GitClean') }
                if ((Get-NormalizedSummary $PrimaryTestsSummary) -cne [string]$receipt.testsSummary) { $conflicts.Add('TestsSummary') }
                if ((Get-NormalizedSummary $PrimaryEvidenceSummary) -cne [string]$receipt.evidenceSummary) { $conflicts.Add('EvidenceSummary') }
                $source = 'PRIMARY_AND_RECEIPT'
            }
            $uniqueConflicts = @($conflicts | Sort-Object -Unique)
            if ($uniqueConflicts.Count -gt 0) {
                $entry.delivery.deliveryState = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.reconciliationStatus = 'DELIVERY_EVIDENCE_CONFLICT'
                $entry.delivery.reconciliationSource = $source
                $entry.delivery.conflicts = $uniqueConflicts
                $entry.delivery.reconciledAt = (Get-Date).ToString('o')
                $doc.events = @($doc.events) + [pscustomobject]@{at=$entry.delivery.reconciledAt;type='DELIVERY_EVIDENCE_CONFLICT';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;conflicts=$uniqueConflicts}
                Save-RegistryDocument $doc
                Write-Result ([pscustomobject]@{action='ReconcileDelivery';status='DELIVERY_EVIDENCE_CONFLICT';conflicts=$uniqueConflicts;ackAllowed=$false;registryPath=$RegistryPath})
                break
            }
            $now = (Get-Date).ToString('o')
            $entry.delivery.deliveryState = 'DELIVERED'
            $entry.delivery.resultStatus = $receipt.resultStatus
            $entry.delivery.receipt.deliveryStatus = 'DELIVERED'
            $entry.delivery.reconciliationStatus = 'PASS'
            $entry.delivery.reconciliationSource = $source
            $entry.delivery.conflicts = @()
            $entry.delivery.reconciledAt = $now
            $doc.events = @($doc.events) + [pscustomobject]@{at=$now;type='DELIVERY_RECONCILED';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;source=$source;resultStatus=$receipt.resultStatus}
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='ReconcileDelivery';status='DELIVERED';source=$source;resultStatus=$receipt.resultStatus;receipt=$receipt;ackAllowed=$true;registryPath=$RegistryPath})
        }
        'RequestRedelivery' {
            foreach ($required in @(@{Name='ThreadId';Value=$ThreadId},@{Name='TaskId';Value=$TaskId})) {
                if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for RequestRedelivery." }
            }
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $entry.delivery = Initialize-DeliveryRecord $entry.delivery
            if ($entry.delivery.deliveryState -in @('DELIVERED','ACKNOWLEDGED','DELIVERY_EVIDENCE_CONFLICT')) { throw "Redelivery is not allowed from state $($entry.delivery.deliveryState)." }
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.delivery.receipt.taskId) -and $entry.delivery.receipt.taskId -cne $TaskId) { throw 'Redelivery TaskId does not match the current assignment.' }
            if (Test-DeliveryReceiptComplete $entry.delivery.receipt) { throw 'A complete Delivery Receipt exists; reconcile it instead of retrying.' }
            if ([int]$entry.delivery.receipt.redeliveryCount -ge 1) {
                Write-Result ([pscustomobject]@{action='RequestRedelivery';status='DELIVERY_RETRY_EXHAUSTED';retryCount=1;reexecuteAllowed=$false;registryPath=$RegistryPath})
                break
            }
            $entry.delivery.receipt.taskId = $TaskId
            $entry.delivery.receipt.threadId = $entry.thread.id
            $entry.delivery.receipt.role = $entry.role
            $entry.delivery.receipt.deliveryStatus = 'DELIVERY_PENDING'
            $entry.delivery.receipt.redeliveryCount = 1
            $entry.delivery.receipt.redeliveryOnly = $true
            $entry.delivery.deliveryState = 'DELIVERY_PENDING'
            $entry.delivery.reconciliationStatus = 'REDELIVERY_REQUESTED'
            $doc.events = @($doc.events) + [pscustomobject]@{at=(Get-Date).ToString('o');type='DELIVERY_REDELIVERY_REQUESTED';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;retryCount=1;mode='REDELIVER'}
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{
                action='RequestRedelivery';status='REDELIVER';retryCount=1;reexecuteAllowed=$false
                prohibited=@('tests','build','network','provider_request','developer_rerun','new_specialist')
                prompt='REDELIVER only the already-generated compact delivery summary. Do not re-run work, tests, builds, network, providers, or development.'
                registryPath=$RegistryPath
            })
        }
        'AcknowledgeDelivery' {
            foreach ($required in @(@{Name='ThreadId';Value=$ThreadId},@{Name='TaskId';Value=$TaskId})) {
                if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for AcknowledgeDelivery." }
            }
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            $entry.delivery = Initialize-DeliveryRecord $entry.delivery
            Assert-DeliveryReceiptIntegrity $entry $entry.delivery.receipt
            if ($entry.delivery.receipt.taskId -cne $TaskId) { throw 'Acknowledgement TaskId does not match the Delivery Receipt.' }
            if ($entry.delivery.deliveryState -eq 'ACKNOWLEDGED') {
                Write-Result ([pscustomobject]@{action='AcknowledgeDelivery';reused=$true;status='ACKNOWLEDGED';taskId=$TaskId;threadId=$ThreadId;registryPath=$RegistryPath})
                break
            }
            if ($entry.delivery.deliveryState -ne 'DELIVERED' -or $entry.delivery.reconciliationStatus -ne 'PASS') { throw 'Only a successfully reconciled delivery can be acknowledged.' }
            $ackTime = if ([string]::IsNullOrWhiteSpace($AcknowledgedAt)) { (Get-Date).ToString('o') } else { [datetimeoffset]::Parse($AcknowledgedAt).ToString('o') }
            $entry.delivery.deliveryState = 'ACKNOWLEDGED'
            $entry.delivery.receipt.deliveryStatus = 'ACKNOWLEDGED'
            $entry.delivery.receipt.acknowledgedAt = $ackTime
            $doc.events = @($doc.events) + [pscustomobject]@{at=$ackTime;type='DELIVERY_ACKNOWLEDGED';projectKey=$entry.projectKey;role=$entry.role;threadId=$ThreadId;taskId=$TaskId;resultStatus=$entry.delivery.receipt.resultStatus}
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='AcknowledgeDelivery';reused=$false;status='ACKNOWLEDGED';taskId=$TaskId;threadId=$ThreadId;resultStatus=$entry.delivery.receipt.resultStatus;registryPath=$RegistryPath})
        }
        'MarkDeliveryDegraded' {
            foreach ($required in @(
                @{Name='ThreadId';Value=$ThreadId}, @{Name='FirstFailureRun';Value=$FirstFailureRun},
                @{Name='RetryRun';Value=$RetryRun}, @{Name='ObservedState';Value=$ObservedState},
                @{Name='DirectReadEvidence';Value=$DirectReadEvidence}, @{Name='OutputEvidence';Value=$OutputEvidence},
                @{Name='BackgroundWorkEvidence';Value=$BackgroundWorkEvidence},
                @{Name='ReadOnlyGuardEvidence';Value=$ReadOnlyGuardEvidence}, @{Name='DeliveryDetectedAt';Value=$DeliveryDetectedAt},
                @{Name='DeliveryReason';Value=$DeliveryReason}
            )) { if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for MarkDeliveryDegraded." } }
            if ($DeliveryRetryCount -ne 1) { throw 'Delivery degradation requires exactly one controlled retry.' }
            if ($FirstFailureRun -eq $RetryRun) { throw 'FirstFailureRun and RetryRun must identify different attempts.' }
            if ($ObservedState -notmatch '(?i)completed' -or $ObservedState -notmatch '(?i)idle') { throw 'ObservedState must prove completed and idle delivery attempts.' }
            if ($DirectReadEvidence -notmatch '(?i)direct[- ]?read' -or $DirectReadEvidence -notmatch '(?i)project' -or $DirectReadEvidence -notmatch '(?i)role' -or $DirectReadEvidence -notmatch '(?i)assignment') { throw 'DirectReadEvidence must prove exact read, project, role, and assignment acceptance.' }
            if ($OutputEvidence -notmatch '(?i)empty' -or $OutputEvidence -notmatch '(?i)no tool' -or $OutputEvidence -notmatch '(?i)no (role )?conclusion|no PASS.+FAIL.+BLOCKED') { throw 'OutputEvidence must prove empty body, no tool records, and no role conclusion.' }
            if ($BackgroundWorkEvidence -notmatch '(?i)no background|not running') { throw 'BackgroundWorkEvidence must prove no background work remains.' }
            if ($ReadOnlyGuardEvidence -notmatch 'PASS|READ_ONLY_CONFIRMED') { throw 'ReadOnlyGuardEvidence must prove a clean read-only comparison.' }
            [void][datetimeoffset]::Parse($DeliveryDetectedAt)
            $doc = Read-RegistryDocument
            $entry = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            if (-not $entry) { throw "Thread is not registered: $ThreadId" }
            if ($entry.thread.state -ne 'Active' -and $entry.thread.state -ne 'Degraded') { throw 'Delivery degradation requires a verified accessible Active Thread.' }
            $effectiveIncident = if ([string]::IsNullOrWhiteSpace($IncidentId)) { 'delivery-' + [guid]::NewGuid().ToString('N') } else { $IncidentId }
            if ($entry.thread.state -eq 'Degraded') {
                if ($entry.deliveryRecovery.incidentId -eq $effectiveIncident) {
                    Write-Result ([pscustomobject]@{action='MarkDeliveryDegraded';reused=$true;entry=$entry;registryPath=$RegistryPath})
                    break
                }
                throw 'Thread already has a different delivery degradation incident.'
            }
            $entry.thread.state = 'Degraded'
            $entry.thread.lastVerifiedAt = $DeliveryDetectedAt
            $entry.deliveryRecovery = [pscustomobject]@{
                status='DEGRADED'; incidentId=$effectiveIncident; retryCount=1
                firstFailureRun=$FirstFailureRun; retryRun=$RetryRun; observedState=$ObservedState
                directReadEvidence=$DirectReadEvidence; outputEvidence=$OutputEvidence
                backgroundWorkEvidence=$BackgroundWorkEvidence
                readOnlyGuard=$ReadOnlyGuardEvidence; detectedAt=[datetimeoffset]::Parse($DeliveryDetectedAt).ToString('o')
                reason=$DeliveryReason; replacementThreadId=$null; replacementHealth=$null
                replacementHealthEvidence=$null
            }
            $doc.events = @($doc.events) + [pscustomobject]@{
                at=(Get-Date).ToString('o'); type='THREAD_DELIVERY_DEGRADED'; projectKey=$entry.projectKey
                role=$entry.role; threadId=$ThreadId; incidentId=$effectiveIncident; retryCount=1
            }
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='MarkDeliveryDegraded';reused=$false;entry=$entry;registryPath=$RegistryPath})
        }
        'RecordReplacementHealth' {
            foreach ($required in @(
                @{Name='ThreadId';Value=$ThreadId}, @{Name='ReplacementThreadId';Value=$ReplacementThreadId},
                @{Name='ReplacementHealth';Value=$ReplacementHealth}, @{Name='ReplacementHealthEvidence';Value=$ReplacementHealthEvidence}
            )) { if ([string]::IsNullOrWhiteSpace([string]$required.Value)) { throw "$($required.Name) is required for RecordReplacementHealth." } }
            $doc = Read-RegistryDocument
            $original = @($doc.entries) | Where-Object { $_.thread.id -eq $ThreadId } | Select-Object -First 1
            $replacement = @($doc.entries) | Where-Object { $_.thread.id -eq $ReplacementThreadId } | Select-Object -First 1
            if (-not $original -or -not $replacement) { throw 'Original and replacement Threads must both be registered.' }
            if ($original.deliveryRecovery.status -ne 'DEGRADED') { throw 'Original Thread is not awaiting replacement health.' }
            if ($replacement.replacesThreadId -ne $ThreadId -or $replacement.deliveryRecovery.incidentId -ne $original.deliveryRecovery.incidentId) {
                throw 'Replacement lineage or incident identity does not match.'
            }
            if ($ReplacementHealth -eq 'PASS') {
                $expectedProject = if (-not [string]::IsNullOrWhiteSpace([string]$original.projectId)) { [string]$original.projectId } elseif (-not [string]::IsNullOrWhiteSpace([string]$original.projectName)) { [string]$original.projectName } else { [string]$original.projectKey }
                $healthLines = @($ReplacementHealthEvidence -split '[;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $expectedLines = @('Status: HEALTH_OK',"Role: $($original.role)","Project: $expectedProject")
                if ($healthLines.Count -ne 3 -or @($expectedLines | Where-Object { $healthLines -cnotcontains $_ }).Count -gt 0) {
                    throw 'Replacement health PASS requires only exact Status, Role, and Project lines.'
                }
            } elseif ($ReplacementHealthEvidence -notmatch '(?i)completed|idle' -or $ReplacementHealthEvidence -notmatch '(?i)empty' -or $ReplacementHealthEvidence -notmatch '(?i)no tools?') {
                throw 'Replacement health FAIL must record completed/idle, empty body, and no tools.'
            }
            $original.deliveryRecovery.replacementThreadId = $ReplacementThreadId
            $original.deliveryRecovery.replacementHealth = $ReplacementHealth
            $original.deliveryRecovery.replacementHealthEvidence = $ReplacementHealthEvidence
            if ($ReplacementHealth -eq 'PASS') {
                $original.deliveryRecovery.status = 'REPLACED'
                $replacement.thread.state = 'Active'
                $replacement.deliveryRecovery.status = 'HEALTHY'
                $eventType = 'ReplacementHealthPass'
            } else {
                $original.deliveryRecovery.status = 'CHANNEL_UNAVAILABLE'
                $replacement.thread.state = 'Degraded'
                $replacement.deliveryRecovery.status = 'CHANNEL_UNAVAILABLE'
                $replacement.deliveryRecovery.reason = 'Replacement produced no visible body, tools, or role conclusion.'
                $eventType = 'VISIBLE_THREAD_DELIVERY_UNAVAILABLE'
            }
            $doc.events = @($doc.events) + [pscustomobject]@{
                at=(Get-Date).ToString('o'); type=$eventType; projectKey=$original.projectKey; role=$original.role
                threadId=$ThreadId; replacementThreadId=$ReplacementThreadId; incidentId=$original.deliveryRecovery.incidentId
            }
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='RecordReplacementHealth';original=$original;replacement=$replacement;registryPath=$RegistryPath})
        }
        'GetProjectBudget' {
            $key = Get-ProjectKey
            $doc = Read-RegistryDocument
            Write-Result (Get-ProjectBudgetStatus $doc $key)
        }
        'SetProjectBudget' {
            $key = Get-ProjectKey
            $doc = Read-RegistryDocument
            $projects = @($doc.projects)
            $record = $projects | Where-Object { $_.projectKey -eq $key } | Select-Object -First 1
            $now = (Get-Date).ToString('o')
            if ($record) {
                $record.worktreeBudget = $WorktreeBudget
                $record.updatedAt = $now
            } else {
                $record = [pscustomobject]@{
                    projectKey=$key; projectId=$ProjectId; projectName=$ProjectName; projectPath=$ProjectPath
                    worktreeBudget=$WorktreeBudget; updatedAt=$now
                }
                $projects += $record
                $doc.projects = $projects
            }
            $doc.events = @($doc.events) + [pscustomobject]@{at=$now;type='SetProjectBudget';projectKey=$key;worktreeBudget=$WorktreeBudget}
            Save-RegistryDocument $doc
            Write-Result ([pscustomobject]@{action='SetProjectBudget';project=$record;status=(Get-ProjectBudgetStatus $doc $key)})
        }
    }
}
finally {
    Exit-RouterRegistryLock $lock
}
