[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $Root 'scripts\Resolve-Route.ps1'
$passes = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected=$Expected Actual=$Actual"
    }
}

function New-Deliverable {
    param(
        [string]$Id,
        [string[]]$Scope,
        [bool]$ParallelBenefit = $false,
        [bool]$ContractStable = $true,
        [bool]$DependenciesSatisfied = $true
    )
    return [ordered]@{
        id = $Id
        coding = $true
        writeScope = $Scope
        parallelBenefit = $ParallelBenefit
        contractStable = $ContractStable
        dependenciesSatisfied = $DependenciesSatisfied
    }
}

function Invoke-RouteCase {
    param(
        [string]$Name,
        [object[]]$Deliverables,
        [string]$ExpectedRoute,
        [hashtable]$Risk = @{},
        [bool]$OwnerCanFinish = $true,
        [string]$Mode = 'ACTIVE',
        [bool]$DualRouterConflict = $false,
        [scriptblock]$ExtraAssertion
    )
    $inputObject = [ordered]@{
        mode = $Mode
        batchId = "fixture-$Name"
        objective = $Name
        deliverables = $Deliverables
        ownerCanFinishVerticalSlice = $OwnerCanFinish
        dualRouterConflict = $DualRouterConflict
        risk = $Risk
        backendCapabilities = [ordered]@{
            collabSubagent = [ordered]@{
                available = $true
                independentCheckout = $false
            }
        }
    }
    $result = & $resolver -InputJson ($inputObject | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json
    Assert-Equal $result.route $ExpectedRoute "$Name route mismatch."
    if ($ExtraAssertion) {
        & $ExtraAssertion $result
    }
    $script:passes++
}

Invoke-RouteCase 'tiny-low-risk' @(
    (New-Deliverable 'typo' @('ui/label.ts'))
) 'LOCAL' -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $false 'Tiny task must not add QA.'
    Assert-Equal $result.newWorktreeAllowed $false 'One lane must not create a Worktree.'
    Assert-Equal $result.executionBackend 'CURRENT_THREAD' 'Tiny task must use CURRENT_THREAD.'
    Assert-Equal $result.executionMode 'DIRECT' 'Tiny task must execute directly.'
}

Invoke-RouteCase 'contained-eight-file-vertical-slice' @(
    (New-Deliverable 'vertical-slice' @('ui/a.ts', 'ui/b.ts', 'state/c.ts', 'provider/d.ts', 'tests/a.ts', 'tests/b.ts', 'docs/a.md', 'config/a.json'))
) 'LOCAL' -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $false 'Multi-file alone must not add QA.'
}

Invoke-RouteCase 'two-independent-frozen' @(
    (New-Deliverable 'core' @('core/') $true),
    (New-Deliverable 'ui' @('ui/') $true)
) 'PARALLEL_2' -ExtraAssertion {
    param($result)
    Assert-Equal $result.maxParallelCodingLanes 2 'Two lanes expected.'
    Assert-Equal $result.riskGates.qa $true 'Multi-lane integration requires QA.'
    Assert-Equal $result.logicalRoute 'PARALLEL_2' 'Logical route must remain parallel.'
    Assert-Equal $result.executionMode 'SERIALIZED_FALLBACK' 'Unsafe platform parallelism must serialize.'
    Assert-Equal $result.newWorktreeAllowed $false 'Router must not auto-create a Worktree.'
}

Invoke-RouteCase 'three-independent-frozen' @(
    (New-Deliverable 'a' @('a/') $true),
    (New-Deliverable 'b' @('b/') $true),
    (New-Deliverable 'c' @('c/') $true)
) 'PARALLEL_3' -ExtraAssertion {
    param($result)
    Assert-Equal $result.maxParallelCodingLanes 3 'Three-lane cap expected.'
    Assert-Equal $result.waveCount 1 'Three lanes fit one wave.'
    Assert-Equal $result.executionMode 'SERIALIZED_WAVES' 'Three logical lanes must use serialized waves.'
}

Invoke-RouteCase 'four-independent-wave' @(
    (New-Deliverable 'a' @('a/') $true),
    (New-Deliverable 'b' @('b/') $true),
    (New-Deliverable 'c' @('c/') $true),
    (New-Deliverable 'd' @('d/') $true)
) 'PARALLEL_3' -ExtraAssertion {
    param($result)
    Assert-Equal $result.maxParallelCodingLanes 3 'Four deliverables must keep the cap at three.'
    Assert-Equal $result.waveCount 2 'Four deliverables require wave scheduling.'
    Assert-Equal $result.executionWaveCount 4 'Execution must retain four serialized Workstream checkpoints.'
}

Invoke-RouteCase 'overlapping-writers' @(
    (New-Deliverable 'a' @('core/') $true),
    (New-Deliverable 'b' @('core/factory.ts') $true)
) 'SERIAL_1' -OwnerCanFinish $false -ExtraAssertion {
    param($result)
    Assert-Equal $result.scopeOverlap $true 'Overlap must be detected.'
    Assert-Equal $result.executionMode 'SERIAL' 'Overlapping ownership must serialize.'
}

Invoke-RouteCase 'unstable-shared-contract' @(
    (New-Deliverable 'producer' @('core/') $true $false),
    (New-Deliverable 'consumer' @('ui/') $true $false)
) 'PLAN_FIRST'

Invoke-RouteCase 'cancellation-risk' @(
    (New-Deliverable 'cancel' @('session/'))
) 'LOCAL' -Risk @{ cancellation = $true } -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $true 'Cancellation requires QA.'
}

Invoke-RouteCase 'credential-risk' @(
    (New-Deliverable 'credential' @('auth/'))
) 'LOCAL' -Risk @{ credentials = $true } -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $true 'Credential changes require QA.'
    Assert-Equal $result.riskGates.security $true 'Credential changes require Security.'
}

Invoke-RouteCase 'migration-risk' @(
    (New-Deliverable 'migration' @('db/'))
) 'LOCAL' -Risk @{ migration = $true } -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $true 'Migration requires QA.'
}

Invoke-RouteCase 'release-risk' @(
    (New-Deliverable 'release' @('release/'))
) 'LOCAL' -Risk @{ releaseCandidate = $true } -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $true 'Release candidate requires QA.'
}

Invoke-RouteCase 'ordinary-multifile-feature' @(
    (New-Deliverable 'feature' @('a.ts', 'b.ts', 'c.ts'))
) 'LOCAL' -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.qa $false 'Ordinary multi-file Feature must not add QA.'
}

Invoke-RouteCase 'one-lane-no-worktree' @(
    (New-Deliverable 'single' @('single/'))
) 'LOCAL' -ExtraAssertion {
    param($result)
    Assert-Equal $result.newWorktreeAllowed $false 'One coding lane must not justify a Worktree.'
}

Invoke-RouteCase 'dual-router-block' @(
    (New-Deliverable 'single' @('single/'))
) 'BLOCKED' -DualRouterConflict $true -ExtraAssertion {
    param($result)
    Assert-Equal $result.reason 'DUAL_ROUTER_BLOCKED' 'Dual router reason must be explicit.'
    Assert-Equal $result.executionBackend 'NONE' 'Blocked route must not select a backend.'
}

Invoke-RouteCase 'shadow-no-side-effects' @(
    (New-Deliverable 'single' @('single/'))
) 'LOCAL' -Mode 'SHADOW' -ExtraAssertion {
    param($result)
    Assert-Equal $result.sideEffectsAllowed $false 'SHADOW must forbid side effects.'
}

Invoke-RouteCase 'new-system-boundary' @(
    (New-Deliverable 'boundary' @('architecture/'))
) 'LOCAL' -Risk @{ newSystemBoundary = $true } -ExtraAssertion {
    param($result)
    Assert-Equal $result.riskGates.architect $true 'New system boundary requires Architect.'
}

Write-Output "V2_ROUTE_ACCEPTANCE_PASS=$passes"
