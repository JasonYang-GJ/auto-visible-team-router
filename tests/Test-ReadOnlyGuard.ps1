[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$guard = Join-Path $Root 'scripts\ReadOnly-Guard.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-readonly-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $temporaryRoot 'repo'
$snapshot = Join-Path $temporaryRoot 'snapshot.json'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

try {
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init --quiet
    git -C $repo config user.name 'V2 Fixture'
    git -C $repo config user.email 'v2-fixture@example.invalid'
    [System.IO.File]::WriteAllText((Join-Path $repo 'tracked.txt'), "baseline`n", [System.Text.UTF8Encoding]::new($false))
    git -C $repo add tracked.txt
    git -C $repo commit --quiet -m 'baseline'

    $capture = @(& $guard -Action Capture -RepoRoot $repo -SnapshotPath $snapshot)
    Assert-True ($capture -contains 'READ_ONLY_BASELINE_CAPTURED') 'ReadOnly baseline capture failed.'
    $cleanCompare = @(& $guard -Action Compare -RepoRoot $repo -SnapshotPath $snapshot)
    Assert-True ($cleanCompare -contains 'READ_ONLY_CONFIRMED') 'Unchanged repository was not confirmed read-only.'

    [System.IO.File]::WriteAllText((Join-Path $repo 'synthetic-change.txt'), "change`n", [System.Text.UTF8Encoding]::new($false))
    $changedCompare = @(& $guard -Action Compare -RepoRoot $repo -SnapshotPath $snapshot)
    Assert-True (($changedCompare -join "`n").Contains('READ_ONLY_STATE_CHANGED')) 'Synthetic write was not detected.'

    Write-Output 'V2_READ_ONLY_GUARD_PASS'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Get-ChildItem -LiteralPath $resolvedTemporaryRoot -Recurse -Force | ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
