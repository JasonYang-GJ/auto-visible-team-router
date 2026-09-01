[CmdletBinding()]
param(
    [ValidateSet('Start','Finish')]
    [string]$Action,
    [Parameter(Mandatory=$true)]
    [string]$Repository,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$CheckId,
    [Parameter(Mandatory=$true)]
    [ValidateSet('Architect','Research','QA','Security','Reviewer')]
    [string]$Role,
    [string]$GuardStore
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Repository = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
    throw "Repository does not exist: $Repository"
}
$reportedRoot = @(& git -c "safe.directory=$Repository" -C $Repository rev-parse --show-toplevel 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Not a Git repository: $Repository" }
$Repository = [System.IO.Path]::GetFullPath(($reportedRoot -join [Environment]::NewLine).Trim()).TrimEnd('\','/')
if (-not $GuardStore) {
    $routerCodexHome = if ($env:CODEX_HOME) {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    } else {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    }
    $GuardStore = Join-Path $routerCodexHome 'auto-visible-team-router\role-checks'
}
$GuardStore = [System.IO.Path]::GetFullPath($GuardStore)
$baselinePath = Join-Path $GuardStore ($CheckId + '.baseline.json')
$reportPath = Join-Path $GuardStore ($CheckId + '.result.json')

function Invoke-Git([string[]]$Arguments) {
    $lines = @(& git -c "safe.directory=$Repository" -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed in ${Repository}: git $($Arguments -join ' ')`n$($lines -join [Environment]::NewLine)"
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-TextSha256([string]$Text) {
    $bytes = $utf8NoBom.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash)
}

function Get-RepositorySnapshot {
    $topLevel = (Invoke-Git @('rev-parse','--show-toplevel')).Trim()
    $resolvedTop = [System.IO.Path]::GetFullPath($topLevel).TrimEnd('\','/')
    if (-not $resolvedTop.Equals($Repository, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Repository root mismatch. Expected $Repository, Git reported $resolvedTop"
    }
    $head = (Invoke-Git @('rev-parse','HEAD')).Trim()
    $branch = (Invoke-Git @('branch','--show-current')).Trim()
    $status = Invoke-Git @('status','--porcelain=v2','--untracked-files=all')
    $workingDiff = Invoke-Git @('diff','--no-ext-diff','--binary','HEAD','--')
    $cachedDiff = Invoke-Git @('diff','--no-ext-diff','--cached','--binary','HEAD','--')
    $untrackedPathsText = Invoke-Git @('ls-files','--others','--exclude-standard')
    $untracked = @()
    if (-not [string]::IsNullOrWhiteSpace($untrackedPathsText)) {
        foreach ($relative in ($untrackedPathsText -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $full = Join-Path $Repository $relative
            $untracked += [pscustomobject]@{
                path = $relative
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash
            }
        }
    }
    $state = [ordered]@{
        repository = $Repository
        head = $head
        branch = $branch
        status = $status
        workingDiffSha256 = Get-TextSha256 $workingDiff
        cachedDiffSha256 = Get-TextSha256 $cachedDiff
        untracked = $untracked
    }
    $canonical = $state | ConvertTo-Json -Depth 8 -Compress
    [pscustomobject]@{
        capturedAt = (Get-Date).ToString('o')
        repository = $Repository
        head = $head
        branch = $branch
        status = $status
        workingDiffSha256 = $state.workingDiffSha256
        cachedDiffSha256 = $state.cachedDiffSha256
        untracked = $untracked
        fingerprint = Get-TextSha256 $canonical
    }
}

New-Item -ItemType Directory -Path $GuardStore -Force | Out-Null

if ($Action -eq 'Start') {
    if (Test-Path -LiteralPath $baselinePath) { throw "CheckId already exists: $CheckId" }
    $snapshot = Get-RepositorySnapshot
    $baseline = [pscustomobject]@{
        schemaVersion = 1
        checkId = $CheckId
        role = $Role
        policy = 'Policy-Enforced Read Only'
        status = 'BASELINE_CAPTURED'
        guardMode = 'Quiescent exact-checkout comparison'
        snapshot = $snapshot
    }
    [System.IO.File]::WriteAllText($baselinePath, ($baseline | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8NoBom)
    [pscustomobject]@{
        checkId = $CheckId
        role = $Role
        status = 'BASELINE_CAPTURED'
        baselinePath = $baselinePath
        snapshot = $snapshot
    } | ConvertTo-Json -Depth 10
    exit 0
}

if (-not (Test-Path -LiteralPath $baselinePath)) { throw "Baseline not found: $baselinePath" }
$baseline = [System.IO.File]::ReadAllText($baselinePath, $utf8NoBom) | ConvertFrom-Json
if ($baseline.role -ne $Role) { throw "Role mismatch. Baseline=$($baseline.role), finish=$Role" }
if (-not $baseline.snapshot.repository.Equals($Repository, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Repository does not match the baseline.'
}
$after = Get-RepositorySnapshot
$passed = $baseline.snapshot.fingerprint -eq $after.fingerprint
$status = if ($passed) { 'READ_ONLY_CONFIRMED' } else { 'READ_ONLY_STATE_CHANGED' }
$report = [pscustomobject]@{
    schemaVersion = 1
    checkId = $CheckId
    role = $Role
    policy = 'Policy-Enforced Read Only'
    passed = $passed
    status = $status
    failClosed = (-not $passed)
    attribution = $(if ($passed) { 'No change observed' } else { 'Unresolved; another concurrent writer or process may have changed the checkout' })
    exactHeadStable = ($baseline.snapshot.head -eq $after.head)
    sameCheckout = $baseline.snapshot.repository.Equals($after.repository, [System.StringComparison]::OrdinalIgnoreCase)
    before = $baseline.snapshot
    after = $after
    resultPath = $reportPath
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8NoBom)
$report | ConvertTo-Json -Depth 10
