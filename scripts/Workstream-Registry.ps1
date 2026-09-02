[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Init', 'Status', 'BeginBatch', 'UpsertWorkstream', 'SetBatchState', 'RecordReceipt')]
    [string]$Action,

    [string]$CodexHome,
    [string]$ProjectKey,
    [string]$ProjectIdentitySource,
    [string]$ProjectId,
    [string]$CanonicalGitRoot,
    [string]$CanonicalGitCommonDir,
    [string]$BatchId,
    [string]$Objective,
    [string]$WorkstreamId,
    [string]$Capability,
    [string]$ThreadId,
    [string]$State,
    [string]$CommitSha,
    [string]$Worktree,
    [string]$Branch,
    [string]$CheckoutPath,
    [string]$CheckoutType,
    [string]$GitCommonDir,
    [string]$StartingSha,
    [string]$BranchOrDetached,
    [string]$ContainmentCategory,
    [string]$ContainmentStatus,
    [string]$WorktreeManagement,
    [switch]$CreatedByRouter,
    [string]$RouterCreationEvidence,
    [string]$OwnedScopeJson,
    [string]$DependenciesJson,
    [string]$ReceiptJson
)

$ErrorActionPreference = 'Stop'

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
        return ,$items
    }
    return $InputObject
}

function New-Registry {
    return [ordered]@{
        schemaVersion = 1
        defaults = [ordered]@{
            worktreeBudget = 3
            maxCodingLanes = 3
        }
        projects = [ordered]@{}
    }
}

function Assert-Registry {
    param([System.Collections.IDictionary]$Registry)
    if ($null -eq $Registry -or $Registry['schemaVersion'] -ne 1) {
        throw 'Unsupported or missing Workstream Registry schemaVersion.'
    }
    if (-not $Registry.Contains('projects') -or $null -eq $Registry['projects']) {
        throw 'Workstream Registry projects object is missing.'
    }
    if (-not $Registry.Contains('defaults')) {
        $Registry['defaults'] = [ordered]@{ worktreeBudget = 3; maxCodingLanes = 3 }
    }
    if ($Registry['defaults']['worktreeBudget'] -ne 3 -or $Registry['defaults']['maxCodingLanes'] -ne 3) {
        throw 'Workstream Registry safety defaults must both remain 3.'
    }
}

function Load-Registry {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return New-Registry
    }
    try {
        $registryObject = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $registry = ConvertTo-Hashtable $registryObject
        Assert-Registry $registry
        return $registry
    }
    catch {
        throw "Workstream Registry is unreadable; fail closed: $($_.Exception.Message)"
    }
}

function Save-Registry {
    param([string]$Path, [System.Collections.IDictionary]$Registry)
    Assert-Registry $Registry
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (Test-Path -LiteralPath $Path) {
        try {
            $knownGood = Load-Registry $Path
            $null = $knownGood
            Copy-Item -Force -LiteralPath $Path -Destination "$Path.bak"
        }
        catch {
            throw 'Existing Registry is not a parsed known-good file; refusing to overwrite it.'
        }
    }
    $temporaryPath = "$Path.tmp"
    $json = ($Registry | ConvertTo-Json -Depth 40) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    $null = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
    Move-Item -Force -LiteralPath $temporaryPath -Destination $Path
}

function Acquire-RegistryLock {
    param([string]$Path)
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $payload = [System.Text.Encoding]::UTF8.GetBytes("pid=$PID;createdAt=$((Get-Date).ToString('o'))")
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush()
        return $stream
    }
    catch {
        throw 'WORKSTREAM_REGISTRY_LOCKED: another writer or an unverified stale lock exists.'
    }
}

function Release-RegistryLock {
    param([System.IO.FileStream]$Stream, [string]$Path)
    if ($null -ne $Stream) {
        $Stream.Dispose()
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path
    }
}

function Require-Value {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required for $Action."
    }
}

function Assert-ProjectKeyFormat {
    param([string]$Value)
    if ($Value -notmatch '^(id|git|path):.+') {
        throw 'ProjectKey must use id:, git:, or path: identity.'
    }
}

function Assert-ProjectIdentitySource {
    param([string]$Value)
    if ($Value -and $Value -notin @('APP_PROJECT_ID', 'GIT_ROOT', 'CANONICAL_PATH')) {
        throw "Invalid ProjectIdentitySource: $Value"
    }
}

function Assert-CheckoutEvidence {
    if ($CheckoutType -and $CheckoutType -notin @('PRIMARY_CHECKOUT', 'CODEX_MANAGED_WORKTREE', 'PERMANENT_WORKTREE', 'UNRELATED_CHECKOUT', 'UNKNOWN')) {
        throw "Invalid CheckoutType: $CheckoutType"
    }
    if ($ContainmentCategory -and $ContainmentCategory -notin @('PRIMARY_CHECKOUT', 'RELATED_GIT_WORKTREE', 'UNRELATED_CHECKOUT', 'UNKNOWN')) {
        throw "Invalid ContainmentCategory: $ContainmentCategory"
    }
    if ($ContainmentStatus -and $ContainmentStatus -notin @('PASS', 'BLOCKED', 'UNKNOWN')) {
        throw "Invalid ContainmentStatus: $ContainmentStatus"
    }
    if ($WorktreeManagement -and $WorktreeManagement -notin @('PRIMARY', 'CODEX_MANAGED', 'ROUTER_MANAGED', 'EXTERNAL', 'UNKNOWN')) {
        throw "Invalid WorktreeManagement: $WorktreeManagement"
    }
    if ($StartingSha -and $StartingSha -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw 'StartingSha must be an exact Git object ID.'
    }
    if ($CreatedByRouter.IsPresent -and [string]::IsNullOrWhiteSpace($RouterCreationEvidence)) {
        throw 'createdByRouter=true requires RouterCreationEvidence.'
    }
    if ($CreatedByRouter.IsPresent -and $WorktreeManagement -notin @('CODEX_MANAGED', 'ROUTER_MANAGED')) {
        throw 'createdByRouter=true requires CODEX_MANAGED or ROUTER_MANAGED lifecycle classification.'
    }
    if ($ContainmentStatus -eq 'PASS') {
        foreach ($requiredEvidence in @{
            CheckoutPath = $CheckoutPath
            CheckoutType = $CheckoutType
            GitCommonDir = $GitCommonDir
            StartingSha = $StartingSha
            ContainmentCategory = $ContainmentCategory
        }.GetEnumerator()) {
            if ([string]::IsNullOrWhiteSpace("$($requiredEvidence.Value)")) {
                throw "ContainmentStatus=PASS requires $($requiredEvidence.Key)."
            }
        }
    }
}

function Parse-JsonArray {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ,([string[]]@())
    }
    if (-not $Value.TrimStart().StartsWith('[')) {
        throw "$Name must be a JSON array."
    }
    $parsed = @($Value | ConvertFrom-Json)
    return ,([string[]]@($parsed | ForEach-Object { "$_" }))
}

function Assert-BatchState {
    param([string]$Value)
    if ($Value -notin @('PROPOSED', 'ACTIVE', 'INTEGRATING', 'PASS', 'FAIL', 'BLOCKED', 'CLOSED')) {
        throw "Invalid batch state: $Value"
    }
}

function Assert-WorkstreamState {
    param([string]$Value)
    if ($Value -notin @('PROPOSED', 'DISPATCHED', 'RUNNING', 'WORK_COMPLETED', 'DELIVERY_PENDING', 'DELIVERED', 'ACKNOWLEDGED', 'PASS', 'FAIL', 'BLOCKED', 'CLOSED', 'DEGRADED_DELIVERY', 'DELIVERY_EVIDENCE_CONFLICT', 'STALE_THREAD')) {
        throw "Invalid workstream state: $Value"
    }
}

function Convert-AndValidateReceipt {
    param(
        [string]$Json,
        [string]$ExpectedBatchId,
        [string]$ExpectedWorkstreamId,
        [string]$ExpectedThreadId
    )
    $receiptObject = $Json | ConvertFrom-Json
    $receipt = ConvertTo-Hashtable $receiptObject
    $allowed = @('TaskId', 'BatchId', 'WorkstreamId', 'ThreadId', 'DeliveryStatus', 'ResultStatus', 'CommitSHA', 'GitClean', 'TestsSummary', 'EvidenceSummary', 'Timestamp', 'ReceiptHash')
    foreach ($key in $receipt.Keys) {
        if ($key -notin $allowed) {
            throw "Receipt contains a forbidden or unsupported field: $key"
        }
    }
    foreach ($required in @('TaskId', 'BatchId', 'WorkstreamId', 'ThreadId', 'DeliveryStatus', 'ResultStatus', 'Timestamp', 'ReceiptHash')) {
        if (-not $receipt.Contains($required) -or [string]::IsNullOrWhiteSpace("$($receipt[$required])")) {
            throw "Receipt field is required: $required"
        }
    }
    if ($receipt['BatchId'] -ne $ExpectedBatchId -or $receipt['WorkstreamId'] -ne $ExpectedWorkstreamId) {
        throw 'Receipt identity does not match the target batch/workstream.'
    }
    if ($ExpectedThreadId -and $receipt['ThreadId'] -ne $ExpectedThreadId) {
        throw 'Receipt ThreadId does not match the registered Workstream Thread.'
    }
    if ($receipt['ResultStatus'] -notin @('PASS', 'FAIL', 'BLOCKED')) {
        throw 'Receipt ResultStatus must be PASS, FAIL, or BLOCKED.'
    }
    foreach ($summaryName in @('TestsSummary', 'EvidenceSummary')) {
        $summary = "$($receipt[$summaryName])"
        if ($summary.Length -gt 1200 -or @($summary -split "\r?\n").Count -gt 12) {
            throw "$summaryName exceeds the compact Receipt limit."
        }
    }
    return $receipt
}

$homePath = Resolve-CodexHome $CodexHome
$runtimeRoot = Join-Path $homePath 'auto-visible-team-router'
$registryPath = Join-Path $runtimeRoot 'workstream-registry.json'
$lockPath = Join-Path $runtimeRoot 'workstream-registry.lock'

if ($Action -eq 'Status') {
    $statusRegistry = Load-Registry $registryPath
    $statusRegistry | ConvertTo-Json -Depth 40
    exit 0
}

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$lockStream = $null
try {
    $lockStream = Acquire-RegistryLock $lockPath
    $registry = Load-Registry $registryPath

    switch ($Action) {
        'Init' {
            Save-Registry $registryPath $registry
            Write-Output "V2_REGISTRY_INITIALIZED=$registryPath"
        }

        'BeginBatch' {
            Require-Value 'ProjectKey' $ProjectKey
            Assert-ProjectKeyFormat $ProjectKey
            Assert-ProjectIdentitySource $ProjectIdentitySource
            Require-Value 'BatchId' $BatchId
            Require-Value 'Objective' $Objective
            if (-not $registry['projects'].Contains($ProjectKey)) {
                $registry['projects'][$ProjectKey] = [ordered]@{
                    projectIdentity = [ordered]@{
                        projectKey = $ProjectKey
                        source = if ($ProjectIdentitySource) { $ProjectIdentitySource } else { $null }
                        projectId = if ($ProjectId) { $ProjectId } else { $null }
                        canonicalGitRoot = if ($CanonicalGitRoot) { $CanonicalGitRoot } else { $null }
                        canonicalGitCommonDir = if ($CanonicalGitCommonDir) { $CanonicalGitCommonDir } else { $null }
                    }
                    batches = [ordered]@{}
                }
            }
            elseif (-not $registry['projects'][$ProjectKey].Contains('projectIdentity')) {
                $registry['projects'][$ProjectKey]['projectIdentity'] = [ordered]@{
                    projectKey = $ProjectKey
                    source = if ($ProjectIdentitySource) { $ProjectIdentitySource } else { $null }
                    projectId = if ($ProjectId) { $ProjectId } else { $null }
                    canonicalGitRoot = if ($CanonicalGitRoot) { $CanonicalGitRoot } else { $null }
                    canonicalGitCommonDir = if ($CanonicalGitCommonDir) { $CanonicalGitCommonDir } else { $null }
                }
            }
            else {
                $existingProjectIdentity = $registry['projects'][$ProjectKey]['projectIdentity']
                if ($CanonicalGitRoot -and $existingProjectIdentity['canonicalGitRoot'] -and -not [string]::Equals($CanonicalGitRoot, "$($existingProjectIdentity['canonicalGitRoot'])", [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'CanonicalGitRoot is immutable for an existing ProjectKey.'
                }
                if ($CanonicalGitCommonDir -and $existingProjectIdentity['canonicalGitCommonDir'] -and -not [string]::Equals($CanonicalGitCommonDir, "$($existingProjectIdentity['canonicalGitCommonDir'])", [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'CanonicalGitCommonDir is immutable for an existing ProjectKey.'
                }
            }
            $batches = $registry['projects'][$ProjectKey]['batches']
            if ($batches.Contains($BatchId)) {
                throw "Batch already exists: $ProjectKey / $BatchId"
            }
            $batches[$BatchId] = [ordered]@{
                batchId = $BatchId
                objective = $Objective
                state = 'PROPOSED'
                createdAt = (Get-Date).ToString('o')
                workstreams = [ordered]@{}
            }
            Save-Registry $registryPath $registry
            Write-Output "V2_BATCH_CREATED=$BatchId"
        }

        'UpsertWorkstream' {
            Require-Value 'ProjectKey' $ProjectKey
            Require-Value 'BatchId' $BatchId
            Require-Value 'WorkstreamId' $WorkstreamId
            Require-Value 'State' $State
            Assert-WorkstreamState $State
            Assert-CheckoutEvidence
            if (-not $registry['projects'].Contains($ProjectKey)) {
                throw 'Unknown ProjectKey.'
            }
            $batches = $registry['projects'][$ProjectKey]['batches']
            if (-not $batches.Contains($BatchId)) {
                throw 'Unknown BatchId.'
            }
            $workstreams = $batches[$BatchId]['workstreams']
            $ownedScope = Parse-JsonArray -Name 'OwnedScopeJson' -Value $OwnedScopeJson
            $dependencies = Parse-JsonArray -Name 'DependenciesJson' -Value $DependenciesJson
            if (-not $workstreams.Contains($WorkstreamId)) {
                $workstreams[$WorkstreamId] = [ordered]@{
                    workstreamId = $WorkstreamId
                    capability = if ($Capability) { $Capability } else { $null }
                    threadId = if ($ThreadId) { $ThreadId } else { $null }
                    threadIdentity = [ordered]@{
                        threadId = if ($ThreadId) { $ThreadId } else { $null }
                    }
                    state = $State
                    commitSha = if ($CommitSha) { $CommitSha } else { $null }
                    worktree = if ($Worktree) { $Worktree } elseif ($CheckoutPath -and $CheckoutType -in @('CODEX_MANAGED_WORKTREE', 'PERMANENT_WORKTREE')) { $CheckoutPath } else { $null }
                    branch = if ($Branch) { $Branch } elseif ($BranchOrDetached) { $BranchOrDetached } else { $null }
                    checkoutIdentity = [ordered]@{
                        checkoutPath = if ($CheckoutPath) { $CheckoutPath } elseif ($Worktree) { $Worktree } else { $null }
                        checkoutType = if ($CheckoutType) { $CheckoutType } else { $null }
                        gitCommonDir = if ($GitCommonDir) { $GitCommonDir } else { $null }
                        startingSha = if ($StartingSha) { $StartingSha } else { $null }
                        containmentCategory = if ($ContainmentCategory) { $ContainmentCategory } else { 'UNKNOWN' }
                        containmentStatus = if ($ContainmentStatus) { $ContainmentStatus } else { 'UNKNOWN' }
                    }
                    worktreeIdentity = [ordered]@{
                        management = if ($WorktreeManagement) { $WorktreeManagement } else { 'UNKNOWN' }
                        createdByRouter = $CreatedByRouter.IsPresent
                        routerCreationEvidence = if ($RouterCreationEvidence) { $RouterCreationEvidence } else { $null }
                    }
                    branchIdentity = [ordered]@{
                        branchOrDetached = if ($BranchOrDetached) { $BranchOrDetached } elseif ($Branch) { $Branch } else { $null }
                    }
                    ownedScope = $ownedScope
                    dependencies = $dependencies
                    delivery = $null
                    createdAt = (Get-Date).ToString('o')
                }
            }
            else {
                $existing = $workstreams[$WorkstreamId]
                if ($ThreadId -and $existing['threadId'] -and $existing['threadId'] -ne $ThreadId) {
                    throw 'A Workstream ThreadId is immutable; use an explicit recovery record rather than silent replacement.'
                }
                if ($Worktree -and $existing['worktree'] -and $existing['worktree'] -ne $Worktree) {
                    throw 'A Workstream worktree is immutable without a new packet/batch identity.'
                }
                if ($CheckoutPath -and $existing['checkoutIdentity'] -and $existing['checkoutIdentity']['checkoutPath'] -and -not [string]::Equals($CheckoutPath, "$($existing['checkoutIdentity']['checkoutPath'])", [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'A Workstream CheckoutIdentity path is immutable without a new packet/batch identity.'
                }
                if ($Capability) { $existing['capability'] = $Capability }
                if ($ThreadId) {
                    $existing['threadId'] = $ThreadId
                    if (-not $existing.Contains('threadIdentity')) { $existing['threadIdentity'] = [ordered]@{} }
                    $existing['threadIdentity']['threadId'] = $ThreadId
                }
                if ($CommitSha) { $existing['commitSha'] = $CommitSha }
                if ($Worktree) { $existing['worktree'] = $Worktree }
                if ($Branch) { $existing['branch'] = $Branch }
                if ($CheckoutPath -or $CheckoutType -or $GitCommonDir -or $StartingSha -or $ContainmentCategory -or $ContainmentStatus) {
                    if (-not $existing.Contains('checkoutIdentity')) { $existing['checkoutIdentity'] = [ordered]@{} }
                    if ($CheckoutPath) {
                        $existing['checkoutIdentity']['checkoutPath'] = $CheckoutPath
                        if ($CheckoutType -in @('CODEX_MANAGED_WORKTREE', 'PERMANENT_WORKTREE')) {
                            $existing['worktree'] = $CheckoutPath
                        }
                        elseif ($existing['worktree'] -and [string]::Equals("$($existing['worktree'])", $CheckoutPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $existing['worktree'] = $null
                        }
                    }
                    if ($CheckoutType) { $existing['checkoutIdentity']['checkoutType'] = $CheckoutType }
                    if ($GitCommonDir) { $existing['checkoutIdentity']['gitCommonDir'] = $GitCommonDir }
                    if ($StartingSha) { $existing['checkoutIdentity']['startingSha'] = $StartingSha }
                    if ($ContainmentCategory) { $existing['checkoutIdentity']['containmentCategory'] = $ContainmentCategory }
                    if ($ContainmentStatus) { $existing['checkoutIdentity']['containmentStatus'] = $ContainmentStatus }
                }
                if ($WorktreeManagement -or $PSBoundParameters.ContainsKey('CreatedByRouter') -or $RouterCreationEvidence) {
                    if (-not $existing.Contains('worktreeIdentity')) { $existing['worktreeIdentity'] = [ordered]@{} }
                    if ($WorktreeManagement) { $existing['worktreeIdentity']['management'] = $WorktreeManagement }
                    if ($PSBoundParameters.ContainsKey('CreatedByRouter')) { $existing['worktreeIdentity']['createdByRouter'] = $CreatedByRouter.IsPresent }
                    if ($RouterCreationEvidence) { $existing['worktreeIdentity']['routerCreationEvidence'] = $RouterCreationEvidence }
                }
                if ($BranchOrDetached) {
                    if (-not $existing.Contains('branchIdentity')) { $existing['branchIdentity'] = [ordered]@{} }
                    $existing['branchIdentity']['branchOrDetached'] = $BranchOrDetached
                    $existing['branch'] = $BranchOrDetached
                }
                if ($OwnedScopeJson) { $existing['ownedScope'] = $ownedScope }
                if ($DependenciesJson) { $existing['dependencies'] = $dependencies }
                $existing['state'] = $State
                $existing['updatedAt'] = (Get-Date).ToString('o')
            }
            Save-Registry $registryPath $registry
            Write-Output "V2_WORKSTREAM_UPSERTED=$WorkstreamId"
        }

        'SetBatchState' {
            Require-Value 'ProjectKey' $ProjectKey
            Require-Value 'BatchId' $BatchId
            Require-Value 'State' $State
            Assert-BatchState $State
            if (-not $registry['projects'].Contains($ProjectKey)) {
                throw 'Unknown ProjectKey.'
            }
            $batches = $registry['projects'][$ProjectKey]['batches']
            if (-not $batches.Contains($BatchId)) {
                throw 'Unknown BatchId.'
            }
            $batches[$BatchId]['state'] = $State
            $batches[$BatchId]['updatedAt'] = (Get-Date).ToString('o')
            Save-Registry $registryPath $registry
            Write-Output "V2_BATCH_STATE=$State"
        }

        'RecordReceipt' {
            Require-Value 'ProjectKey' $ProjectKey
            Require-Value 'BatchId' $BatchId
            Require-Value 'WorkstreamId' $WorkstreamId
            Require-Value 'ReceiptJson' $ReceiptJson
            if (-not $registry['projects'].Contains($ProjectKey)) {
                throw 'Unknown ProjectKey.'
            }
            $batches = $registry['projects'][$ProjectKey]['batches']
            if (-not $batches.Contains($BatchId)) {
                throw 'Unknown BatchId.'
            }
            $workstreams = $batches[$BatchId]['workstreams']
            if (-not $workstreams.Contains($WorkstreamId)) {
                throw 'Unknown WorkstreamId.'
            }
            $expectedThread = $workstreams[$WorkstreamId]['threadId']
            $receipt = Convert-AndValidateReceipt -Json $ReceiptJson -ExpectedBatchId $BatchId -ExpectedWorkstreamId $WorkstreamId -ExpectedThreadId $expectedThread
            $workstreams[$WorkstreamId]['delivery'] = $receipt
            $workstreams[$WorkstreamId]['updatedAt'] = (Get-Date).ToString('o')
            Save-Registry $registryPath $registry
            Write-Output "V2_RECEIPT_RECORDED=$WorkstreamId"
        }
    }
}
finally {
    Release-RegistryLock -Stream $lockStream -Path $lockPath
}
