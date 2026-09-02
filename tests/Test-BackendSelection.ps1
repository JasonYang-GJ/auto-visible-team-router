[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $Root 'scripts\Resolve-ExecutionBackend.ps1'
$passes = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected=$Expected Actual=$Actual"
    }
}

function Invoke-BackendCase {
    param(
        [string]$Name,
        [string]$LogicalRoute,
        [int]$CodingCount,
        [string]$ExpectedBackend,
        [string]$ExpectedMode,
        [bool]$ManualVisibleRequested = $false,
        [bool]$TrueParallelRequired = $false,
        [hashtable]$Collab = @{},
        [scriptblock]$ExtraAssertion
    )
    $inputObject = [ordered]@{
        logicalRoute = $LogicalRoute
        codingDeliverableCount = $CodingCount
        manualVisibleRequested = $ManualVisibleRequested
        trueParallelRequired = $TrueParallelRequired
        backendCapabilities = [ordered]@{
            collabSubagent = $Collab
        }
    }
    $result = & $resolver -InputJson ($inputObject | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
    Assert-Equal $result.executionBackend $ExpectedBackend "$Name backend mismatch."
    Assert-Equal $result.executionMode $ExpectedMode "$Name mode mismatch."
    if ($ExtraAssertion) {
        & $ExtraAssertion $result
    }
    $script:passes++
}

Invoke-BackendCase 'local-current' 'LOCAL' 1 'CURRENT_THREAD' 'DIRECT'
Invoke-BackendCase 'serial-current' 'SERIAL_1' 2 'CURRENT_THREAD' 'SERIAL'
Invoke-BackendCase 'parallel2-fallback' 'PARALLEL_2' 2 'CURRENT_THREAD' 'SERIALIZED_FALLBACK' -ExtraAssertion {
    param($result)
    Assert-Equal $result.parallelDegraded $true 'Parallel fallback must be explicit.'
    Assert-Equal $result.actualConcurrentCodingLanes 1 'Fallback has one writer at a time.'
}
Invoke-BackendCase 'parallel3-waves' 'PARALLEL_3' 4 'CURRENT_THREAD' 'SERIALIZED_WAVES' -ExtraAssertion {
    param($result)
    Assert-Equal $result.executionWaveCount 4 'Serialized waves must preserve four Workstream boundaries.'
}
Invoke-BackendCase 'collab-shared-worktree' 'PARALLEL_2' 2 'CURRENT_THREAD' 'SERIALIZED_FALLBACK' -Collab @{ available = $true; independentCheckout = $false } -ExtraAssertion {
    param($result)
    Assert-Equal $result.collabCodingParallelism 'FORBIDDEN' 'Shared checkout must forbid coding parallelism.'
}
Invoke-BackendCase 'future-collab-isolated' 'PARALLEL_2' 2 'COLLAB_SUBAGENT' 'PARALLEL' -Collab @{ available = $true; independentCheckout = $true }
Invoke-BackendCase 'manual-visible' 'PARALLEL_2' 2 'MANUAL_VISIBLE_WORKTREE' 'READY_FOR_MANUAL_VISIBLE_DISPATCH' -ManualVisibleRequested $true -ExtraAssertion {
    param($result)
    Assert-Equal $result.manualDispatchRequired $true 'Manual visible flow must wait for the user.'
    Assert-Equal $result.routerMayCreateWorktree $false 'Router must not create the manual Worktree.'
}
Invoke-BackendCase 'auto-visible-stays-disabled' 'PARALLEL_2' 2 'CURRENT_THREAD' 'SERIALIZED_FALLBACK' -Collab @{ available = $false; independentCheckout = $false } -ExtraAssertion {
    param($result)
    Assert-Equal $result.autoVisibleWorktree.availability 'UNSUPPORTED' 'AUTO_VISIBLE must remain unsupported.'
    Assert-Equal $result.autoVisibleWorktree.reason 'THREAD_CREATION_PLATFORM_LIMITATION' 'AUTO_VISIBLE reason mismatch.'
}
Invoke-BackendCase 'true-parallel-required' 'PARALLEL_2' 2 'NONE' 'BLOCKED' -TrueParallelRequired $true -ExtraAssertion {
    param($result)
    Assert-Equal $result.reason 'SAFE_PARALLEL_BACKEND_UNAVAILABLE' 'True parallel blocker mismatch.'
}

Write-Output "V2_BACKEND_SELECTION_PASS=$passes"
