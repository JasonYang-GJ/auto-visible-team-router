[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJson
)

$ErrorActionPreference = 'Stop'

function Get-Bool {
    param($Object, [string]$Name, [bool]$Default = $false)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }
    return [bool]$property.Value
}

function Normalize-ScopePath {
    param([string]$Path)
    return ($Path.Replace('\', '/').Trim('/')).ToLowerInvariant()
}

function Test-ScopeOverlap {
    param([object[]]$CodingDeliverables)
    for ($leftIndex = 0; $leftIndex -lt $CodingDeliverables.Count; $leftIndex++) {
        $leftPaths = @($CodingDeliverables[$leftIndex].writeScope | ForEach-Object { Normalize-ScopePath "$_" })
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $CodingDeliverables.Count; $rightIndex++) {
            $rightPaths = @($CodingDeliverables[$rightIndex].writeScope | ForEach-Object { Normalize-ScopePath "$_" })
            foreach ($left in $leftPaths) {
                foreach ($right in $rightPaths) {
                    if (-not $left -or -not $right) {
                        continue
                    }
                    if ($left -eq $right -or $left.StartsWith("$right/") -or $right.StartsWith("$left/")) {
                        return $true
                    }
                }
            }
        }
    }
    return $false
}

$inputObject = $InputJson | ConvertFrom-Json
foreach ($required in @('mode', 'batchId', 'objective', 'deliverables')) {
    if ($null -eq $inputObject.PSObject.Properties[$required]) {
        throw "Missing route input field: $required"
    }
}
if ($inputObject.mode -notin @('SHADOW', 'CANARY', 'ACTIVE')) {
    throw 'mode must be SHADOW, CANARY, or ACTIVE.'
}

$deliverables = @($inputObject.deliverables)
if ($deliverables.Count -eq 0) {
    throw 'At least one observable deliverable is required.'
}
$codingDeliverables = @($deliverables | Where-Object { Get-Bool $_ 'coding' $true })
$codingCount = $codingDeliverables.Count
$ownerCanFinish = Get-Bool $inputObject 'ownerCanFinishVerticalSlice' $true
$dualRouterConflict = Get-Bool $inputObject 'dualRouterConflict' $false
$trueParallelRequired = Get-Bool $inputObject 'trueParallelRequired' $false
$manualVisibleRequested = Get-Bool $inputObject 'manualVisibleRequested' $false

$dependenciesSatisfied = @($codingDeliverables | Where-Object { -not (Get-Bool $_ 'dependenciesSatisfied' $true) }).Count -eq 0
$contractsStable = @($codingDeliverables | Where-Object { -not (Get-Bool $_ 'contractStable' $true) }).Count -eq 0
$parallelBenefit = @($codingDeliverables | Where-Object { -not (Get-Bool $_ 'parallelBenefit' $false) }).Count -eq 0
$scopeOverlap = if ($codingCount -gt 1) { Test-ScopeOverlap $codingDeliverables } else { $false }

$logicalRoute = 'LOCAL'
$reason = 'One owner can safely complete the bounded vertical slice.'
$maxParallelCodingLanes = if ($codingCount -gt 0) { 1 } else { 0 }
$waveCount = if ($codingCount -gt 0) { 1 } else { 0 }

if ($dualRouterConflict -and $inputObject.mode -in @('CANARY', 'ACTIVE')) {
    $logicalRoute = 'BLOCKED'
    $reason = 'DUAL_ROUTER_BLOCKED'
    $maxParallelCodingLanes = 0
    $waveCount = 0
}
elseif (-not $dependenciesSatisfied -or (-not $contractsStable -and $codingCount -gt 1)) {
    $logicalRoute = 'PLAN_FIRST'
    $reason = 'A hard dependency or shared contract is unresolved.'
    $maxParallelCodingLanes = 0
    $waveCount = 0
}
elseif ($codingCount -gt 1 -and $scopeOverlap) {
    $logicalRoute = 'SERIAL_1'
    $reason = 'Writer scopes overlap and must be serialized.'
}
elseif ($codingCount -gt 1 -and $contractsStable -and $parallelBenefit) {
    $maxParallelCodingLanes = [Math]::Min(3, $codingCount)
    $waveCount = [Math]::Ceiling($codingCount / 3.0)
    $logicalRoute = "PARALLEL_$maxParallelCodingLanes"
    $reason = if ($codingCount -gt 3) {
        'Independent deliverables are scheduled in waves with a three-lane cap.'
    }
    else {
        'Independent deliverables have disjoint writes, stable contracts, and material parallel benefit.'
    }
}
elseif (-not $ownerCanFinish -or $codingCount -gt 1) {
    $logicalRoute = 'SERIAL_1'
    $reason = 'One task-scoped Workstream should execute the deliverables serially.'
}

$backendCapabilities = if ($null -ne $inputObject.PSObject.Properties['backendCapabilities']) {
    $inputObject.backendCapabilities
}
else {
    [pscustomobject]@{}
}
$backendInput = [ordered]@{
    logicalRoute = $logicalRoute
    codingDeliverableCount = $codingCount
    trueParallelRequired = $trueParallelRequired
    manualVisibleRequested = $manualVisibleRequested
    backendCapabilities = $backendCapabilities
}
$backendResolver = Join-Path $PSScriptRoot 'Resolve-ExecutionBackend.ps1'
$backendResult = & $backendResolver -InputJson ($backendInput | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
$route = if ($backendResult.executionMode -eq 'BLOCKED' -and $logicalRoute -ne 'BLOCKED') { 'BLOCKED' } else { $logicalRoute }
if ($route -eq 'BLOCKED' -and $logicalRoute -ne 'BLOCKED') {
    $reason = "$($backendResult.reason)"
}

$risk = if ($null -ne $inputObject.PSObject.Properties['risk']) { $inputObject.risk } else { [pscustomobject]@{} }
$securityRequired =
    (Get-Bool $risk 'credentials') -or
    (Get-Bool $risk 'authentication') -or
    (Get-Bool $risk 'permissions') -or
    (Get-Bool $risk 'privacy') -or
    (Get-Bool $risk 'externalTrustBoundary') -or
    (Get-Bool $risk 'codeExecutionBoundary') -or
    (Get-Bool $risk 'encryption')
$qaRequired =
    (Get-Bool $risk 'cancellation') -or
    (Get-Bool $risk 'concurrency') -or
    (Get-Bool $risk 'recovery') -or
    $securityRequired -or
    (Get-Bool $risk 'migration') -or
    (Get-Bool $risk 'criticalPersistence') -or
    (Get-Bool $risk 'releaseCandidate') -or
    (Get-Bool $risk 'highImpactBug') -or
    (Get-Bool $risk 'sharedContractChange') -or
    (Get-Bool $risk 'repeatedRepair') -or
    ($logicalRoute -in @('PARALLEL_2', 'PARALLEL_3'))
$architectRequired =
    (Get-Bool $risk 'newSystemBoundary') -or
    (Get-Bool $risk 'majorOwnershipChange') -or
    ((Get-Bool $risk 'sharedContractChange') -and $codingCount -gt 1)
$reviewerRequired =
    (Get-Bool $risk 'ambiguousCorrectness') -or
    (Get-Bool $risk 'repeatedQaRejection')

[ordered]@{
    mode = $inputObject.mode
    route = $route
    logicalRoute = $logicalRoute
    batchId = $inputObject.batchId
    objective = $inputObject.objective
    deliverableCount = $deliverables.Count
    codingDeliverableCount = $codingCount
    maxParallelCodingLanes = $maxParallelCodingLanes
    waveCount = [int]$waveCount
    executionBackend = $backendResult.executionBackend
    executionMode = $backendResult.executionMode
    backendStatus = $backendResult.backendStatus
    safeParallelBackend = $backendResult.safeParallelBackend
    parallelDegraded = $backendResult.parallelDegraded
    manualDispatchRequired = $backendResult.manualDispatchRequired
    actualConcurrentCodingLanes = $backendResult.actualConcurrentCodingLanes
    executionWaveCount = $backendResult.executionWaveCount
    collabCodingParallelism = $backendResult.collabCodingParallelism
    autoVisibleWorktree = $backendResult.autoVisibleWorktree
    scopeOverlap = $scopeOverlap
    dependenciesSatisfied = $dependenciesSatisfied
    contractsStable = $contractsStable
    parallelBenefit = $parallelBenefit
    sideEffectsAllowed = $inputObject.mode -in @('CANARY', 'ACTIVE') -and $route -ne 'BLOCKED'
    newWorktreeAllowed = $backendResult.routerMayCreateWorktree
    reason = $reason
    backendReason = $backendResult.reason
    riskGates = [ordered]@{
        architect = $architectRequired
        qa = $qaRequired
        security = $securityRequired
        reviewer = $reviewerRequired
    }
} | ConvertTo-Json -Depth 20
