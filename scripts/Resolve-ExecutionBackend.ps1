[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJson
)

$ErrorActionPreference = 'Stop'

function Get-Bool {
    param($Object, [string]$Name, [bool]$Default = $false)
    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }
    return [bool]$property.Value
}

$inputObject = $InputJson | ConvertFrom-Json
foreach ($required in @('logicalRoute', 'codingDeliverableCount')) {
    if ($null -eq $inputObject.PSObject.Properties[$required]) {
        throw "Missing backend input field: $required"
    }
}

$logicalRoute = "$($inputObject.logicalRoute)"
if ($logicalRoute -notin @('LOCAL', 'SERIAL_1', 'PARALLEL_2', 'PARALLEL_3', 'PLAN_FIRST', 'BLOCKED')) {
    throw 'logicalRoute is invalid.'
}

$codingCount = [int]$inputObject.codingDeliverableCount
if ($codingCount -lt 0) {
    throw 'codingDeliverableCount cannot be negative.'
}

$capabilities = if ($null -ne $inputObject.PSObject.Properties['backendCapabilities']) {
    $inputObject.backendCapabilities
}
else {
    [pscustomobject]@{}
}
$collab = if ($null -ne $capabilities.PSObject.Properties['collabSubagent']) {
    $capabilities.collabSubagent
}
else {
    [pscustomobject]@{}
}

$collabAvailable = Get-Bool $collab 'available' $true
$collabIndependentCheckout = Get-Bool $collab 'independentCheckout' $false
$manualVisibleRequested = Get-Bool $inputObject 'manualVisibleRequested' $false
$trueParallelRequired = Get-Bool $inputObject 'trueParallelRequired' $false
$parallelRoute = $logicalRoute -in @('PARALLEL_2', 'PARALLEL_3')

$backend = 'CURRENT_THREAD'
$executionMode = 'DIRECT'
$backendStatus = 'AVAILABLE'
$safeParallelBackend = if ($collabAvailable -and $collabIndependentCheckout) { 'AVAILABLE' } else { 'UNAVAILABLE' }
$parallelDegraded = $false
$manualDispatchRequired = $false
$actualConcurrentCodingLanes = if ($codingCount -gt 0) { 1 } else { 0 }
$executionWaveCount = if ($codingCount -gt 0) { 1 } else { 0 }
$reason = 'The current task can execute the bounded work safely.'

switch ($logicalRoute) {
    'BLOCKED' {
        $backend = 'NONE'
        $executionMode = 'BLOCKED'
        $backendStatus = 'NOT_SELECTED'
        $actualConcurrentCodingLanes = 0
        $executionWaveCount = 0
        $reason = 'Logical routing is blocked before backend selection.'
    }
    'PLAN_FIRST' {
        $executionMode = 'PLAN_FIRST'
        $actualConcurrentCodingLanes = 0
        $executionWaveCount = 0
        $reason = 'The current task freezes the required contract before coding.'
    }
    'SERIAL_1' {
        $executionMode = 'SERIAL'
        $reason = 'The current task executes one bounded Workstream at a time.'
    }
    'PARALLEL_2' {
        $parallelDegraded = $true
    }
    'PARALLEL_3' {
        $parallelDegraded = $true
    }
}

if ($parallelRoute) {
    if ($collabAvailable -and $collabIndependentCheckout) {
        $backend = 'COLLAB_SUBAGENT'
        $executionMode = 'PARALLEL'
        $parallelDegraded = $false
        $actualConcurrentCodingLanes = [Math]::Min(3, $codingCount)
        $executionWaveCount = if ($codingCount -gt 0) { [int][Math]::Ceiling($codingCount / 3.0) } else { 0 }
        $reason = 'A collaboration backend proves independent safe checkouts.'
    }
    elseif ($manualVisibleRequested) {
        $backend = 'MANUAL_VISIBLE_WORKTREE'
        $executionMode = 'READY_FOR_MANUAL_VISIBLE_DISPATCH'
        $backendStatus = 'USER_ACTION_REQUIRED'
        $safeParallelBackend = 'USER_ASSISTED_PENDING'
        $parallelDegraded = $false
        $manualDispatchRequired = $true
        $actualConcurrentCodingLanes = 0
        $executionWaveCount = 0
        $reason = 'The user requested visible parallel tasks; wait for app-native manual creation and verified adoption.'
    }
    elseif ($trueParallelRequired) {
        $backend = 'NONE'
        $executionMode = 'BLOCKED'
        $backendStatus = 'UNAVAILABLE'
        $actualConcurrentCodingLanes = 0
        $executionWaveCount = 0
        $reason = 'SAFE_PARALLEL_BACKEND_UNAVAILABLE'
    }
    else {
        $backend = 'CURRENT_THREAD'
        $executionMode = if ($logicalRoute -eq 'PARALLEL_3') { 'SERIALIZED_WAVES' } else { 'SERIALIZED_FALLBACK' }
        $parallelDegraded = $true
        $actualConcurrentCodingLanes = if ($codingCount -gt 0) { 1 } else { 0 }
        $executionWaveCount = $codingCount
        $reason = 'Safe parallel backend unavailable; preserve Workstream boundaries and execute sequentially.'
    }
}

[ordered]@{
    logicalRoute = $logicalRoute
    executionBackend = $backend
    executionMode = $executionMode
    backendStatus = $backendStatus
    safeParallelBackend = $safeParallelBackend
    parallelDegraded = $parallelDegraded
    manualDispatchRequired = $manualDispatchRequired
    actualConcurrentCodingLanes = $actualConcurrentCodingLanes
    executionWaveCount = $executionWaveCount
    routerMayCreateWorktree = $false
    collabCodingParallelism = if ($collabAvailable -and $collabIndependentCheckout) { 'ALLOWED' } else { 'FORBIDDEN' }
    autoVisibleWorktree = [ordered]@{
        availability = 'UNSUPPORTED'
        reason = 'THREAD_CREATION_PLATFORM_LIMITATION'
    }
    reason = $reason
} | ConvertTo-Json -Depth 20
