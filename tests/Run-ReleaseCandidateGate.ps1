[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha,
    [string]$PythonCommand = 'python'
)

$ErrorActionPreference = 'Stop'

function Assert-Marker {
    param([object[]]$Output, [string]$Marker, [string]$Name)
    if ($Output -notcontains $Marker -and -not (($Output -join "`n").Contains($Marker))) {
        throw "$Name failed or did not return $Marker."
    }
}

$resolvedRoot = (& git -C $Root rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Release Candidate root is not a Git repository.'
}
$headBefore = (& git -C $resolvedRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($headBefore -ne $ExpectedSha.ToLowerInvariant()) {
    throw "Release Candidate SHA mismatch. Expected=$ExpectedSha Actual=$headBefore"
}
$parent = (& git -C $resolvedRoot rev-parse HEAD^).Trim().ToLowerInvariant()
$statusBefore = @(& git -C $resolvedRoot status --porcelain=v1 --untracked-files=all)
if ($statusBefore.Count -gt 0) {
    throw "Release Candidate working tree is not clean before validation: $($statusBefore -join '; ')"
}

$offlineOutput = @(& (Join-Path $resolvedRoot 'tests\Run-OfflineGate.ps1') -Root $resolvedRoot -PythonCommand $PythonCommand)
Assert-Marker $offlineOutput 'V2_PLATFORM_ADAPTATION_PASS' 'Platform adaptation regression'
Assert-Marker $offlineOutput 'V2_OFFLINE_ENGINEERING_PASS' 'Offline engineering gate'
$offlineOutput | Write-Output

$headAfter = (& git -C $resolvedRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($headAfter -ne $headBefore) {
    throw "Release Candidate HEAD changed during validation. Before=$headBefore After=$headAfter"
}
$diffCheck = @(& git -C $resolvedRoot diff --check 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Release Candidate git diff --check failed: $($diffCheck -join '; ')"
}
$statusAfter = @(& git -C $resolvedRoot status --porcelain=v1 --untracked-files=all)
if ($statusAfter.Count -gt 0) {
    throw "Release Candidate gate changed the working tree: $($statusAfter -join '; ')"
}

Write-Output "V2_CANDIDATE_SHA=$headBefore"
Write-Output "V2_CANDIDATE_PARENT=$parent"
Write-Output 'V2_RELEASE_CANDIDATE_GATE_PASS'
