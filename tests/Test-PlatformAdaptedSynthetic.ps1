[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$routeResolver = Join-Path $Root 'scripts\Resolve-Route.ps1'
$registryScript = Join-Path $Root 'scripts\Workstream-Registry.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-adapted-' + [guid]::NewGuid().ToString('N'))
$codexHome = Join-Path $temporaryRoot 'codex-home'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function New-Deliverable {
    param([string]$Id, [string[]]$Scope, [bool]$ParallelBenefit = $false)
    return [ordered]@{
        id = $Id
        coding = $true
        writeScope = $Scope
        parallelBenefit = $ParallelBenefit
        contractStable = $true
        dependenciesSatisfied = $true
    }
}

function Resolve-Case {
    param([string]$BatchId, [object[]]$Deliverables, [bool]$OwnerCanFinish = $true, [hashtable]$Risk = @{})
    $inputObject = [ordered]@{
        mode = 'ACTIVE'
        batchId = $BatchId
        objective = $BatchId
        deliverables = $Deliverables
        ownerCanFinishVerticalSlice = $OwnerCanFinish
        risk = $Risk
        backendCapabilities = [ordered]@{
            collabSubagent = [ordered]@{
                available = $true
                independentCheckout = $false
            }
        }
    }
    return & $routeResolver -InputJson ($inputObject | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
}

function New-ReceiptJson {
    param([string]$WorkstreamId)
    return ([ordered]@{
        TaskId = 'current-coordinator'
        BatchId = 'platform-adapted-synthetic'
        WorkstreamId = $WorkstreamId
        ThreadId = 'current-coordinator'
        DeliveryStatus = 'DELIVERED'
        ResultStatus = 'PASS'
        CommitSHA = ''
        GitClean = $true
        TestsSummary = 'offline synthetic acceptance: PASS'
        EvidenceSummary = 'bounded CURRENT_THREAD Workstream with compact checkpoint'
        Timestamp = (Get-Date).ToString('o')
        ReceiptHash = ('a' * 64)
    } | ConvertTo-Json -Compress)
}

try {
    $local = Resolve-Case 'adapted-local' @((New-Deliverable 'local' @('local/')))
    Assert-True ($local.logicalRoute -eq 'LOCAL' -and $local.executionBackend -eq 'CURRENT_THREAD' -and $local.executionMode -eq 'DIRECT') 'LOCAL must use CURRENT_THREAD.'

    $serial = Resolve-Case 'adapted-serial' @(
        (New-Deliverable 'serial-a' @('serial/a/')),
        (New-Deliverable 'serial-b' @('serial/b/'))
    ) -OwnerCanFinish $false
    Assert-True ($serial.logicalRoute -eq 'SERIAL_1' -and $serial.executionBackend -eq 'CURRENT_THREAD' -and $serial.executionMode -eq 'SERIAL') 'SERIAL_1 must use CURRENT_THREAD.'

    $parallel = Resolve-Case 'adapted-parallel' @(
        (New-Deliverable 'lane-a' @('lane-a/') $true),
        (New-Deliverable 'lane-b' @('lane-b/') $true)
    )
    Assert-True ($parallel.logicalRoute -eq 'PARALLEL_2' -and $parallel.executionMode -eq 'SERIALIZED_FALLBACK') 'PARALLEL_2 must degrade to serialized fallback.'
    Assert-True ($parallel.route -ne 'BLOCKED' -and $parallel.actualConcurrentCodingLanes -eq 1) 'Ordinary parallel plan must not block.'
    Assert-True ($parallel.riskGates.qa -and -not $parallel.riskGates.security) 'Multi-workstream integration must retain QA.'
    Assert-True ($parallel.autoVisibleWorktree.availability -eq 'UNSUPPORTED' -and -not $parallel.newWorktreeAllowed) 'AUTO_VISIBLE must remain disabled.'

    $credential = Resolve-Case 'adapted-credential' @((New-Deliverable 'credential' @('auth/'))) -Risk @{ credentials = $true }
    Assert-True ($credential.riskGates.qa -and $credential.riskGates.security) 'Credential route must require QA and Security.'

    $backendSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\Resolve-ExecutionBackend.ps1') -Raw
    Assert-True ($backendSource -notmatch 'create_thread') 'Offline backend selector must never call automatic Thread creation.'
    $contextContract = Get-Content -LiteralPath (Join-Path $Root 'references\context-delegation.md') -Raw
    Assert-True ($contextContract.Contains('Workstream Packet') -and $contextContract.Contains('Context Delta')) 'Packet/Context Delta contract is missing.'
    $deliveryContract = Get-Content -LiteralPath (Join-Path $Root 'references\delivery-reliability.md') -Raw
    Assert-True ($deliveryContract.Contains('WORK_COMPLETED') -and $deliveryContract.Contains('ACKNOWLEDGED')) 'Delivery lifecycle contract is missing.'
    $history = Get-Content -LiteralPath (Join-Path $Root 'references\platform-capability-history.md') -Raw
    Assert-True ($history.Contains('AUTO_VISIBLE_WORKTREE = UNSUPPORTED_BY_CURRENT_TOOL_SURFACE') -and $history.Contains('r4')) 'Platform history is missing.'

    & $registryScript -Action Init -CodexHome $codexHome | Out-Null
    & $registryScript -Action BeginBatch -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -Objective 'serialized CURRENT_THREAD Workstreams' -ProjectIdentitySource 'CANONICAL_PATH' | Out-Null
    foreach ($lane in @(
        @{ Id = 'lane-a'; Scope = '["lane-a/"]' },
        @{ Id = 'lane-b'; Scope = '["lane-b/"]' }
    )) {
        & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -WorkstreamId $lane.Id -Capability 'CurrentThreadOwner' -ThreadId 'current-coordinator' -State 'PROPOSED' -OwnedScopeJson $lane.Scope -DependenciesJson '[]' | Out-Null
        & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -WorkstreamId $lane.Id -State 'WORK_COMPLETED' | Out-Null
        & $registryScript -Action RecordReceipt -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -WorkstreamId $lane.Id -ReceiptJson (New-ReceiptJson $lane.Id) | Out-Null
        & $registryScript -Action UpsertWorkstream -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -WorkstreamId $lane.Id -State 'ACKNOWLEDGED' | Out-Null
    }
    & $registryScript -Action SetBatchState -CodexHome $codexHome -ProjectKey 'path:C:\platform-adapted-fixture' -BatchId 'platform-adapted-synthetic' -State PASS | Out-Null

    $registry = & $registryScript -Action Status -CodexHome $codexHome | ConvertFrom-Json
    $batch = $registry.projects.'path:C:\platform-adapted-fixture'.batches.'platform-adapted-synthetic'
    Assert-True ($batch.state -eq 'PASS') 'Adapted synthetic Registry batch did not pass.'
    Assert-True ($batch.workstreams.'lane-a'.threadId -eq 'current-coordinator' -and $batch.workstreams.'lane-b'.threadId -eq 'current-coordinator') 'CURRENT_THREAD identity was not retained across serial Workstreams.'
    Assert-True ($batch.workstreams.'lane-a'.ownedScope[0] -eq 'lane-a/' -and $batch.workstreams.'lane-b'.ownedScope[0] -eq 'lane-b/') 'Serialized Workstream scopes must remain disjoint.'
    Assert-True ($batch.workstreams.'lane-a'.delivery.ResultStatus -eq 'PASS' -and $batch.workstreams.'lane-b'.delivery.ResultStatus -eq 'PASS') 'Compact delivery reconciliation failed.'

    Write-Output 'V2_PLATFORM_ADAPTED_SYNTHETIC_PASS'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
