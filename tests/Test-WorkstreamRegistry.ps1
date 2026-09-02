[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$registryScript = Join-Path $Root 'scripts\Workstream-Registry.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-registry-' + [guid]::NewGuid().ToString('N'))
$codexHome = Join-Path $temporaryRoot 'codex-home'
$registryPath = Join-Path $codexHome 'auto-visible-team-router\workstream-registry.json'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

try {
    & $registryScript -Action Init -CodexHome $codexHome | Out-Null
    & $registryScript -Action BeginBatch -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -Objective 'first bounded objective' -ProjectIdentitySource 'CANONICAL_PATH' -CanonicalGitRoot 'C:\fixture' -CanonicalGitCommonDir 'C:\fixture\.git' | Out-Null
    & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -WorkstreamId 'core-producer' -Capability 'Fullstack' -ThreadId 'thread-a' -State 'DISPATCHED' -Worktree 'C:\fixture\wt-a' -Branch 'codex/v2-a' -CheckoutPath 'C:\fixture\wt-a' -CheckoutType 'CODEX_MANAGED_WORKTREE' -GitCommonDir 'C:\fixture\.git' -StartingSha ('a' * 40) -BranchOrDetached 'DETACHED' -ContainmentCategory 'RELATED_GIT_WORKTREE' -ContainmentStatus 'PASS' -WorktreeManagement 'CODEX_MANAGED' -OwnedScopeJson '["core/"]' -DependenciesJson '[]' | Out-Null
    & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -WorkstreamId 'core-producer' -State 'WORK_COMPLETED' -CommitSha 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' | Out-Null

    $receipt = [ordered]@{
        TaskId = 'task-a'
        BatchId = 'batch-a'
        WorkstreamId = 'core-producer'
        ThreadId = 'thread-a'
        DeliveryStatus = 'DELIVERED'
        ResultStatus = 'PASS'
        CommitSHA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        GitClean = $true
        TestsSummary = 'targeted: PASS'
        EvidenceSummary = 'exact SHA and clean worktree'
        Timestamp = (Get-Date).ToString('o')
        ReceiptHash = ('b' * 64)
    } | ConvertTo-Json -Compress
    & $registryScript -Action RecordReceipt -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -WorkstreamId 'core-producer' -ReceiptJson $receipt | Out-Null
    & $registryScript -Action SetBatchState -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -State PASS | Out-Null

    & $registryScript -Action BeginBatch -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-b' -Objective 'unrelated objective' | Out-Null
    & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-b' -WorkstreamId 'core-producer' -Capability 'Fullstack' -ThreadId 'thread-b' -State 'PROPOSED' -OwnedScopeJson '["core/"]' -DependenciesJson '[]' | Out-Null

    $registry = & $registryScript -Action Status -CodexHome $codexHome | ConvertFrom-Json
    Assert-True ($registry.schemaVersion -eq 1) 'Registry schema must be 1.'
    Assert-True ($registry.defaults.worktreeBudget -eq 3 -and $registry.defaults.maxCodingLanes -eq 3) 'Registry safety defaults are invalid.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.threadId -eq 'thread-a') 'Batch A Workstream identity is wrong.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-b'.workstreams.'core-producer'.threadId -eq 'thread-b') 'A new batch must not reuse the old permanent Thread.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.delivery.ResultStatus -eq 'PASS') 'Receipt was not recorded.'
    Assert-True ($registry.projects.'path:C:\fixture'.projectIdentity.projectKey -eq 'path:C:\fixture') 'ProjectIdentity must remain separate from Thread/Checkout identity.'
    Assert-True ($registry.projects.'path:C:\fixture'.projectIdentity.canonicalGitCommonDir -eq 'C:\fixture\.git') 'Canonical git-common-dir evidence is missing.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.threadIdentity.threadId -eq 'thread-a') 'ThreadIdentity is missing.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.checkoutIdentity.checkoutType -eq 'CODEX_MANAGED_WORKTREE') 'CheckoutIdentity is missing.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.worktreeIdentity.management -eq 'CODEX_MANAGED') 'WorktreeIdentity management is missing.'
    Assert-True (-not $registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.worktreeIdentity.createdByRouter) 'App-managed Worktree must not be claimed as Router-created.'
    Assert-True ($registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.branchIdentity.branchOrDetached -eq 'DETACHED') 'BranchIdentity is missing.'
    $singleScope = $registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.ownedScope
    $emptyDependencies = $registry.projects.'path:C:\fixture'.batches.'batch-a'.workstreams.'core-producer'.dependencies
    Assert-True (($singleScope -is [System.Array]) -and @($singleScope).Count -eq 1 -and $singleScope[0] -eq 'core/') 'A one-item ownedScope must persist as a JSON array.'
    Assert-True (($emptyDependencies -is [System.Array]) -and @($emptyDependencies).Count -eq 0) 'An empty dependencies value must persist as a JSON array.'
    Assert-True (Test-Path -LiteralPath "$registryPath.bak") 'Parsed known-good backup is missing.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $registryPath) 'workstream-registry.lock'))) 'Registry lock was not released.'

    $duplicateBlocked = $false
    try {
        & $registryScript -Action BeginBatch -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -Objective 'duplicate' | Out-Null
    }
    catch {
        $duplicateBlocked = $_.Exception.Message -match 'already exists'
    }
    Assert-True $duplicateBlocked 'Duplicate batch identity must be blocked.'

    $legacyProjectKeyBlocked = $false
    try {
        & $registryScript -Action BeginBatch -CodexHome $codexHome -ProjectKey 'name:legacy-role-project' -BatchId 'legacy-key-batch' -Objective 'must not create new V2 batch from legacy display identity' | Out-Null
    }
    catch {
        $legacyProjectKeyBlocked = $_.Exception.Message -match 'id:, git:, or path:'
    }
    Assert-True $legacyProjectKeyBlocked 'New V2 batches must reject legacy/display-title project keys.'

    $threadReplacementBlocked = $false
    try {
        & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -WorkstreamId 'core-producer' -ThreadId 'thread-replacement' -State 'RUNNING' | Out-Null
    }
    catch {
        $threadReplacementBlocked = $_.Exception.Message -match 'immutable'
    }
    Assert-True $threadReplacementBlocked 'Silent Thread replacement must be blocked.'

    $receiptMismatchBlocked = $false
    try {
        $wrongReceipt = $receipt | ConvertFrom-Json
        $wrongReceipt.BatchId = 'batch-b'
        & $registryScript -Action RecordReceipt -CodexHome $codexHome -ProjectKey 'path:C:\fixture' -BatchId 'batch-a' -WorkstreamId 'core-producer' -ReceiptJson ($wrongReceipt | ConvertTo-Json -Compress) | Out-Null
    }
    catch {
        $receiptMismatchBlocked = $_.Exception.Message -match 'does not match'
    }
    Assert-True $receiptMismatchBlocked 'Receipt identity mismatch must be blocked.'

    Write-Output 'V2_WORKSTREAM_REGISTRY_PASS'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
