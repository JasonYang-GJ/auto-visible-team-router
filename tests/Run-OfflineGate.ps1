[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [string]$PythonCommand = 'python'
)

$ErrorActionPreference = 'Stop'

function Assert-Marker {
    param([object[]]$Output, [string]$Marker, [string]$Name)
    if ($Output -notcontains $Marker -and -not (($Output -join "`n").Contains($Marker))) {
        throw "$Name failed or did not return $Marker. Output: $($Output -join '; ')"
    }
}

$parseErrors = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'scripts'), (Join-Path $Root 'tests') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($error in $errors) {
        $parseErrors += "$($file.Name):$($error.Extent.StartLineNumber):$($error.Message)"
    }
}
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parser failures: $($parseErrors -join '; ')"
}
Write-Output 'V2_POWERSHELL_PARSE_PASS'

$powerShellValidation = @(& (Join-Path $Root 'scripts\Validate-Router.ps1') -Root $Root)
Assert-Marker $powerShellValidation 'V2_OFFLINE_VALIDATION_PASS' 'PowerShell static validator'
$powerShellValidation | Write-Output

$pythonValidation = @(& $PythonCommand (Join-Path $Root 'tests\validate_package.py'))
if ($LASTEXITCODE -ne 0) {
    throw "Python validator failed: $($pythonValidation -join '; ')"
}
Assert-Marker $pythonValidation 'V2_OFFLINE_STATIC_PASS' 'Python static/schema validator'
$pythonValidation | Write-Output

$routeOutput = @(& (Join-Path $Root 'tests\Test-RouteAcceptance.ps1') -Root $Root)
Assert-Marker $routeOutput 'V2_ROUTE_ACCEPTANCE_PASS=16' 'Route acceptance'
$routeOutput | Write-Output

$backendOutput = @(& (Join-Path $Root 'tests\Test-BackendSelection.ps1') -Root $Root)
Assert-Marker $backendOutput 'V2_BACKEND_SELECTION_PASS=9' 'Execution backend selection'
$backendOutput | Write-Output

$projectIdentityOutput = @(& (Join-Path $Root 'tests\Test-ProjectIdentity.ps1') -Root $Root)
Assert-Marker $projectIdentityOutput 'V2_PROJECT_IDENTITY_PASS=7' 'Project Identity resolution'
$projectIdentityOutput | Write-Output

$containmentOutput = @(& (Join-Path $Root 'tests\Test-RepositoryContainment.ps1') -Root $Root)
Assert-Marker $containmentOutput 'V2_REPOSITORY_CONTAINMENT_PASS=10' 'Repository/Worktree containment'
$containmentOutput | Write-Output

$registryOutput = @(& (Join-Path $Root 'tests\Test-WorkstreamRegistry.ps1') -Root $Root)
Assert-Marker $registryOutput 'V2_WORKSTREAM_REGISTRY_PASS' 'Workstream Registry lifecycle'
$registryOutput | Write-Output

$managementOutput = @(& (Join-Path $Root 'tests\Test-ManagementLifecycle.ps1') -Root $Root)
Assert-Marker $managementOutput 'V2_MANAGEMENT_LIFECYCLE_PASS' 'Management lifecycle'
$managementOutput | Write-Output

$rollbackOutput = @(& (Join-Path $Root 'tests\Test-InstallRollback.ps1') -Root $Root)
Assert-Marker $rollbackOutput 'V2_INSTALL_ROLLBACK_PASS' 'Migration rollback'
$rollbackOutput | Write-Output

$readOnlyOutput = @(& (Join-Path $Root 'tests\Test-ReadOnlyGuard.ps1') -Root $Root)
Assert-Marker $readOnlyOutput 'V2_READ_ONLY_GUARD_PASS' 'ReadOnly Guard'
$readOnlyOutput | Write-Output

$adaptedSyntheticOutput = @(& (Join-Path $Root 'tests\Test-PlatformAdaptedSynthetic.ps1') -Root $Root)
Assert-Marker $adaptedSyntheticOutput 'V2_PLATFORM_ADAPTED_SYNTHETIC_PASS' 'Platform-adapted synthetic gate'
$adaptedSyntheticOutput | Write-Output

$gitRoot = & git -C $Root rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0) {
    $diffCheck = @(& git -C $Root diff --check 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed: $($diffCheck -join '; ')"
    }
    Write-Output 'V2_GIT_DIFF_CHECK_PASS'
}

Write-Output 'V2_PLATFORM_ADAPTATION_PASS'
Write-Output 'V2_OFFLINE_ENGINEERING_PASS'
