[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Capture','Compare')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$RepoRoot,

    [Parameter(Mandatory=$true)]
    [string]$SnapshotPath
)

$ErrorActionPreference = 'Stop'

function Invoke-GitText {
    param([string[]]$GitArgs)
    $output = & git -C $RepoRoot @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $output" }
    return (($output | ForEach-Object { "$_" }) -join "`n").TrimEnd()
}

function Current-Snapshot {
    return [ordered]@{
        repoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
        head = Invoke-GitText @('rev-parse','HEAD')
        branch = Invoke-GitText @('rev-parse','--abbrev-ref','HEAD')
        status = Invoke-GitText @('status','--porcelain=v1','--untracked-files=all')
        capturedAt = (Get-Date).ToString('o')
    }
}

switch ($Action) {
    'Capture' {
        $snap = Current-Snapshot
        $dir = Split-Path -Parent $SnapshotPath
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $snap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SnapshotPath -Encoding UTF8
        Write-Output 'READ_ONLY_BASELINE_CAPTURED'
    }

    'Compare' {
        if (-not (Test-Path -LiteralPath $SnapshotPath)) { throw 'SnapshotPath does not exist.' }
        $before = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
        $after = Current-Snapshot

        $same = ($before.repoRoot -eq $after.repoRoot) -and
                ($before.head -eq $after.head) -and
                ($before.branch -eq $after.branch) -and
                ($before.status -eq $after.status)

        if ($same) {
            Write-Output 'READ_ONLY_CONFIRMED'
            exit 0
        }

        [pscustomobject]@{
            result = 'READ_ONLY_STATE_CHANGED'
            before = $before
            after = $after
        } | ConvertTo-Json -Depth 10
        exit 2
    }
}
