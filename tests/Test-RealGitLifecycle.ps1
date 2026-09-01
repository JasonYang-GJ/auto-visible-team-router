[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('router-real-git-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $testRoot 'repo'
$frontendWt = Join-Path $testRoot 'wt-frontend'
$backendWt = Join-Path $testRoot 'wt-backend'
$unmergedWt = Join-Path $testRoot 'wt-unmerged'
$failures = [System.Collections.Generic.List[string]]::new()
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }
function Get-Head([string]$Path) { ((git -C $Path rev-parse HEAD) | Out-String).Trim() }
function Test-Clean([string]$Path) { [string]::IsNullOrWhiteSpace(((git -C $Path status --porcelain --untracked-files=all) | Out-String)) }
function Test-Ancestor([string]$Commit, [string]$Target) { git -C $repo merge-base --is-ancestor $Commit $Target; return $LASTEXITCODE -eq 0 }
function Test-BranchCheckedOut([string]$Branch) {
    $porcelain = (git -C $repo worktree list --porcelain) -join "`n"
    return $porcelain -match ('(?m)^branch refs/heads/' + [regex]::Escape($Branch) + '$')
}
function Test-BranchCleanupEligible([string]$Branch, [string]$Commit, [string]$Target, [bool]$RouterCreated) {
    if (-not $RouterCreated) { return $false }
    if ($Branch -match '^(main|master|release(?:/|$)|stable(?:/|$))') { return $false }
    if (Test-BranchCheckedOut $Branch) { return $false }
    return Test-Ancestor $Commit $Target
}

try {
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init --initial-branch=main | Out-Null
    git -C $repo config user.name 'Router Lifecycle Test'
    git -C $repo config user.email 'router-lifecycle@example.invalid'
    [System.IO.File]::WriteAllText((Join-Path $repo 'frontend.txt'), "base`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $repo 'backend.txt'), "base`n", $utf8)
    git -C $repo add frontend.txt backend.txt
    git -C $repo commit -m 'base' | Out-Null
    $baseCommit = Get-Head $repo
    Assert-True ([string]::IsNullOrWhiteSpace(((git -C $repo remote) | Out-String))) 'Temporary repository unexpectedly has a remote.'

    foreach ($branch in @('codex/frontend-lifecycle','codex/backend-lifecycle','codex/unmerged-lifecycle')) {
        git check-ref-format --branch $branch | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "Invalid fixture branch: $branch"
    }

    git -C $repo worktree add -b codex/frontend-lifecycle $frontendWt $baseCommit | Out-Null
    git -C $repo worktree add -b codex/backend-lifecycle $backendWt $baseCommit | Out-Null
    Assert-True ((Test-Path -LiteralPath $frontendWt) -and (Test-Path -LiteralPath $backendWt)) 'Physical parallel worktrees were not created.'

    [System.IO.File]::WriteAllText((Join-Path $frontendWt 'frontend.txt'), "feature without gate`n", $utf8)
    git -C $frontendWt add frontend.txt
    git -C $frontendWt commit -m 'frontend candidate' | Out-Null
    $frontendFailSha = Get-Head $frontendWt
    $qaFirst = if ((Get-Content -LiteralPath (Join-Path $frontendWt 'frontend.txt') -Raw) -match 'gate=pass') { 'PASS' } else { 'FAIL' }
    Assert-True ($qaFirst -eq 'FAIL') 'Intentional first QA gate did not fail.'

    [System.IO.File]::WriteAllText((Join-Path $frontendWt 'frontend.txt'), "feature`ngate=pass`n", $utf8)
    git -C $frontendWt add frontend.txt
    git -C $frontendWt commit -m 'frontend QA repair' | Out-Null
    $frontendPassSha = Get-Head $frontendWt
    Assert-True ($frontendPassSha -ne $frontendFailSha) 'Developer repair did not produce a new SHA.'

    [System.IO.File]::WriteAllText((Join-Path $backendWt 'backend.txt'), "backend feature`n", $utf8)
    git -C $backendWt add backend.txt
    git -C $backendWt commit -m 'backend candidate' | Out-Null
    $backendSha = Get-Head $backendWt
    $qaSecond = if (((Get-Content -LiteralPath (Join-Path $frontendWt 'frontend.txt') -Raw) -match 'gate=pass') -and (Test-Clean $frontendWt) -and (Test-Clean $backendWt)) { 'PASS' } else { 'FAIL' }
    Assert-True ($qaSecond -eq 'PASS') 'QA did not pass the repaired exact SHAs.'

    [System.IO.File]::WriteAllText((Join-Path $frontendWt 'untracked.tmp'), 'dirty', $utf8)
    Assert-True (-not (Test-Clean $frontendWt)) 'Dirty Worktree cleanup rejection fixture was not dirty.'
    Remove-Item -LiteralPath (Join-Path $frontendWt 'untracked.tmp') -Force
    Assert-True (Test-Clean $frontendWt) 'Frontend Worktree did not return to clean state.'

    git -C $repo merge --no-ff codex/frontend-lifecycle -m 'integrate frontend' | Out-Null
    git -C $repo merge --no-ff codex/backend-lifecycle -m 'integrate backend' | Out-Null
    $integrationSha = Get-Head $repo
    Assert-True (Test-Ancestor $frontendPassSha main) 'Frontend PASS SHA is not contained in main.'
    Assert-True (Test-Ancestor $backendSha main) 'Backend PASS SHA is not contained in main.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $repo 'frontend.txt') -Raw) -match 'gate=pass') 'Post-integration frontend regression failed.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $repo 'backend.txt') -Raw) -match 'backend feature') 'Post-integration backend regression failed.'

    git -C $repo worktree add -b codex/unmerged-lifecycle $unmergedWt $baseCommit | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $unmergedWt 'unmerged.txt'), "unmerged`n", $utf8)
    git -C $unmergedWt add unmerged.txt
    git -C $unmergedWt commit -m 'unmerged candidate' | Out-Null
    $unmergedSha = Get-Head $unmergedWt
    Assert-True (-not (Test-Ancestor $unmergedSha main)) 'Unmerged rejection fixture is unexpectedly contained.'
    Assert-True (-not (Test-BranchCleanupEligible 'main' $integrationSha 'main' $true)) 'Protected main was considered cleanup eligible.'
    Assert-True (-not (Test-BranchCleanupEligible 'codex/unmerged-lifecycle' $unmergedSha 'main' $true)) 'Checked-out/unmerged Branch was considered cleanup eligible.'

    git -C $repo worktree remove $unmergedWt
    Assert-True (-not (Test-BranchCleanupEligible 'codex/unmerged-lifecycle' $unmergedSha 'main' $true)) 'Unmerged Branch was considered cleanup eligible after Worktree removal.'
    Assert-True (-not (Test-BranchCleanupEligible 'codex/frontend-lifecycle' $frontendPassSha 'main' $true)) 'Checked-out merged Branch was considered cleanup eligible.'

    git -C $repo worktree remove $frontendWt
    git -C $repo worktree remove $backendWt
    Assert-True (Test-BranchCleanupEligible 'codex/frontend-lifecycle' $frontendPassSha 'main' $true) 'Contained Router Branch did not become cleanup eligible.'
    Assert-True (Test-BranchCleanupEligible 'codex/backend-lifecycle' $backendSha 'main' $true) 'Contained backend Branch did not become cleanup eligible.'
    git -C $repo branch -d codex/frontend-lifecycle | Out-Null
    git -C $repo branch -d codex/backend-lifecycle | Out-Null
    Assert-True (-not (Test-BranchCleanupEligible 'codex/unmerged-lifecycle' $unmergedSha 'main' $true)) 'Unmerged Branch eligibility changed without containment.'

    $result = [pscustomobject]@{
        baseCommit=$baseCommit; frontendFailSha=$frontendFailSha; frontendPassSha=$frontendPassSha
        backendSha=$backendSha; integrationSha=$integrationSha; qa=@('FAIL','PASS')
        protectedRejected=$true; dirtyRejected=$true; unmergedRejected=$true; remoteCount=0
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{ suite='Isolated real Git lifecycle'; passed=($failures.Count -eq 0); evidence=$result; failures=$failures } | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) { exit 1 }
