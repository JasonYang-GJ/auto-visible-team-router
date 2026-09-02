[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $Root 'scripts\Resolve-RepositoryContainment.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-containment-' + [guid]::NewGuid().ToString('N'))
$script:caseCount = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Git {
    param([string]$WorkingDirectory, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git -C $WorkingDirectory @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in ${WorkingDirectory}: $($output -join '; ')"
    }
    return $output
}

function New-TestRepository {
    param([string]$Path, [string]$FileName = 'baseline.txt')
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $null = Invoke-Git $Path init
    $null = Invoke-Git $Path config user.email 'router-tests@example.invalid'
    $null = Invoke-Git $Path config user.name 'Router Tests'
    [System.IO.File]::WriteAllText((Join-Path $Path $FileName), "baseline`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-Git $Path add -- $FileName
    $null = Invoke-Git $Path commit -m 'baseline'
    return (@(Invoke-Git $Path rev-parse HEAD)[0]).Trim()
}

function Invoke-ContainmentResolver {
    param(
        [string]$ThreadCwd,
        [string]$CanonicalGitRoot,
        [string]$BatchBaselineSha,
        [string]$ThreadId = 'thread-fixture',
        [string]$CodexHome
    )
    $arguments = @{
        ThreadCwd = $ThreadCwd
        CanonicalGitRoot = $CanonicalGitRoot
        BatchBaselineSha = $BatchBaselineSha
        ThreadId = $ThreadId
    }
    if ($CodexHome) { $arguments['CodexHome'] = $CodexHome }
    return (& $resolver @arguments | ConvertFrom-Json)
}

function Pass-Case {
    param([string]$Name)
    $script:caseCount++
    Write-Output "PASS $Name"
}

try {
    $case1Root = Join-Path $temporaryRoot 'case1-primary'
    $case1Baseline = New-TestRepository $case1Root
    $case1 = Invoke-ContainmentResolver -ThreadCwd $case1Root -CanonicalGitRoot $case1Root -BatchBaselineSha $case1Baseline -ThreadId 'case1-thread'
    Assert-True ($case1.containmentStatus -eq 'PASS') 'CASE1 primary checkout must pass.'
    Assert-True ($case1.checkoutType -eq 'PRIMARY_CHECKOUT') 'CASE1 checkout type must be PRIMARY_CHECKOUT.'
    Assert-True ($case1.containment -eq 'PRIMARY_CHECKOUT') 'CASE1 containment category must be PRIMARY_CHECKOUT.'
    Pass-Case 'CASE1_PRIMARY_CHECKOUT'

    $case2Root = Join-Path $temporaryRoot 'case2-canonical'
    $case2Worktree = Join-Path $temporaryRoot 'case2-related-worktree'
    $case2Baseline = New-TestRepository $case2Root
    $null = Invoke-Git $case2Root worktree add -b 'case2-related' $case2Worktree $case2Baseline
    $case2 = Invoke-ContainmentResolver -ThreadCwd $case2Worktree -CanonicalGitRoot $case2Root -BatchBaselineSha $case2Baseline -ThreadId 'case2-thread'
    Assert-True ($case2.containmentStatus -eq 'PASS') 'CASE2 related Git worktree must pass.'
    Assert-True ($case2.checkoutType -eq 'PERMANENT_WORKTREE') 'CASE2 checkout type must be PERMANENT_WORKTREE.'
    Assert-True ($case2.containment -eq 'RELATED_GIT_WORKTREE') 'CASE2 containment category must be RELATED_GIT_WORKTREE.'
    Assert-True $case2.worktreeInventoryMatch 'CASE2 canonical worktree inventory must identify the checkout.'
    Pass-Case 'CASE2_RELATED_GIT_WORKTREE'

    $case3Root = Join-Path $temporaryRoot 'case3-canonical'
    $case3CodexHome = Join-Path $temporaryRoot 'case3-codex-home'
    $case3Worktree = Join-Path $case3CodexHome 'worktrees\1234\case3-repo'
    $case3Baseline = New-TestRepository $case3Root
    $null = Invoke-Git $case3Root worktree add --detach $case3Worktree $case3Baseline
    $case3 = Invoke-ContainmentResolver -ThreadCwd $case3Worktree -CanonicalGitRoot $case3Root -BatchBaselineSha $case3Baseline -ThreadId 'case3-thread' -CodexHome $case3CodexHome
    Assert-True ($case3.containmentStatus -eq 'PASS') 'CASE3 Codex-managed worktree must pass.'
    Assert-True ($case3.checkoutType -eq 'CODEX_MANAGED_WORKTREE') 'CASE3 checkout type must be CODEX_MANAGED_WORKTREE.'
    Assert-True ($case3.management -eq 'CODEX_MANAGED') 'CASE3 management must be CODEX_MANAGED.'
    Assert-True (-not $case3.createdByRouter) 'CASE3 must not claim Router creation without evidence.'
    Pass-Case 'CASE3_CODEX_MANAGED_WORKTREE'

    $case4Root = Join-Path $temporaryRoot 'case4-canonical'
    $case4Worktree = Join-Path $temporaryRoot 'case4-repo-2'
    $case4Baseline = New-TestRepository $case4Root
    $null = Invoke-Git $case4Root worktree add -b 'case4-related' $case4Worktree $case4Baseline
    $case4 = Invoke-ContainmentResolver -ThreadCwd $case4Worktree -CanonicalGitRoot $case4Root -BatchBaselineSha $case4Baseline -ThreadId 'case4-thread'
    Assert-True ($case4.containmentStatus -eq 'PASS') 'CASE4 repo-2 name must not block a real related worktree.'
    Assert-True ($case4.containment -eq 'RELATED_GIT_WORKTREE') 'CASE4 must be classified by Git relationship, not folder suffix.'
    Pass-Case 'CASE4_REPO_2_RELATED_WORKTREE'

    $case5Root = Join-Path $temporaryRoot 'case5-canonical'
    $case5Clone = Join-Path $temporaryRoot 'case5-canonical-2'
    $case5Baseline = New-TestRepository $case5Root
    $null = Invoke-Git $temporaryRoot clone --no-local $case5Root $case5Clone
    $case5 = Invoke-ContainmentResolver -ThreadCwd $case5Clone -CanonicalGitRoot $case5Root -BatchBaselineSha $case5Baseline -ThreadId 'case5-thread'
    Assert-True ($case5.containmentStatus -eq 'BLOCKED') 'CASE5 independent clone must be blocked.'
    Assert-True ($case5.checkoutType -eq 'UNRELATED_CHECKOUT') 'CASE5 must be classified as UNRELATED_CHECKOUT.'
    Assert-True ($case5.containment -eq 'UNRELATED_CHECKOUT') 'CASE5 containment category must be UNRELATED_CHECKOUT.'
    Assert-True ($case5.blocker -eq 'UNRELATED_CHECKOUT') 'CASE5 exact blocker must be UNRELATED_CHECKOUT.'
    Pass-Case 'CASE5_SIMILAR_NAME_SAME_HEAD_UNRELATED'

    $case6Seed = Join-Path $temporaryRoot 'case6-seed'
    $case6Remote = Join-Path $temporaryRoot 'case6-remote.git'
    $case6Root = Join-Path $temporaryRoot 'case6-canonical'
    $case6Clone = Join-Path $temporaryRoot 'case6-independent'
    $null = New-TestRepository $case6Seed
    $null = Invoke-Git $temporaryRoot clone --bare $case6Seed $case6Remote
    $null = Invoke-Git $temporaryRoot clone $case6Remote $case6Root
    $null = Invoke-Git $temporaryRoot clone $case6Remote $case6Clone
    $case6Baseline = (@(Invoke-Git $case6Root rev-parse HEAD)[0]).Trim()
    $case6CanonicalRemote = (@(Invoke-Git $case6Root remote get-url origin)[0]).Trim()
    $case6CloneRemote = (@(Invoke-Git $case6Clone remote get-url origin)[0]).Trim()
    Assert-True ($case6CanonicalRemote -eq $case6CloneRemote) 'CASE6 fixture must use the same remote URL.'
    $case6 = Invoke-ContainmentResolver -ThreadCwd $case6Clone -CanonicalGitRoot $case6Root -BatchBaselineSha $case6Baseline -ThreadId 'case6-thread'
    Assert-True ($case6.containmentStatus -eq 'BLOCKED') 'CASE6 same-remote independent clone must be blocked.'
    Assert-True ($case6.blocker -eq 'UNRELATED_CHECKOUT') 'CASE6 same remote must not override git-common-dir mismatch.'
    Pass-Case 'CASE6_SAME_REMOTE_INDEPENDENT_CLONE'

    $case7Root = Join-Path $temporaryRoot 'case7-canonical'
    $case7Worktree = Join-Path $temporaryRoot 'case7-dirty-worktree'
    $case7Baseline = New-TestRepository $case7Root
    $null = Invoke-Git $case7Root worktree add -b 'case7-related' $case7Worktree $case7Baseline
    [System.IO.File]::WriteAllText((Join-Path $case7Worktree 'unattributed.txt'), "unknown change`n", [System.Text.UTF8Encoding]::new($false))
    $case7 = Invoke-ContainmentResolver -ThreadCwd $case7Worktree -CanonicalGitRoot $case7Root -BatchBaselineSha $case7Baseline -ThreadId 'case7-thread'
    Assert-True ($case7.containmentStatus -eq 'BLOCKED') 'CASE7 unattributed dirty worktree must be blocked.'
    Assert-True ($case7.blocker -eq 'UNATTRIBUTED_DIRTY_STATE') 'CASE7 exact blocker must identify unattributed dirty state.'
    Assert-True ($case7.containment -eq 'RELATED_GIT_WORKTREE') 'CASE7 relationship should remain known even though state is blocked.'
    Assert-True (@($case7.dirtyPaths).Count -gt 0) 'CASE7 must report dirty evidence.'
    Pass-Case 'CASE7_UNATTRIBUTED_DIRTY_STATE'

    $case8Root = Join-Path $temporaryRoot 'case8-canonical'
    $case8Worktree = Join-Path $temporaryRoot 'case8-detached-worktree'
    $case8Baseline = New-TestRepository $case8Root
    $null = Invoke-Git $case8Root worktree add --detach $case8Worktree $case8Baseline
    $case8 = Invoke-ContainmentResolver -ThreadCwd $case8Worktree -CanonicalGitRoot $case8Root -BatchBaselineSha $case8Baseline -ThreadId 'case8-thread'
    Assert-True ($case8.containmentStatus -eq 'PASS') 'CASE8 valid detached worktree at baseline must pass.'
    Assert-True ($case8.branchOrDetached -eq 'DETACHED') 'CASE8 must report detached HEAD without treating it as failure.'
    Assert-True ($case8.containment -eq 'RELATED_GIT_WORKTREE') 'CASE8 detached checkout must remain a related worktree.'
    Pass-Case 'CASE8_DETACHED_BASELINE_PASS'

    $case9Root = Join-Path $temporaryRoot 'case9-canonical'
    $case9Worktree = Join-Path $temporaryRoot 'case9-mismatched-worktree'
    $case9Baseline = New-TestRepository $case9Root
    [System.IO.File]::WriteAllText((Join-Path $case9Root 'second.txt'), "second commit`n", [System.Text.UTF8Encoding]::new($false))
    $null = Invoke-Git $case9Root add -- 'second.txt'
    $null = Invoke-Git $case9Root commit -m 'second'
    $case9NewHead = (@(Invoke-Git $case9Root rev-parse HEAD)[0]).Trim()
    $null = Invoke-Git $case9Root worktree add --detach $case9Worktree $case9NewHead
    $case9 = Invoke-ContainmentResolver -ThreadCwd $case9Worktree -CanonicalGitRoot $case9Root -BatchBaselineSha $case9Baseline -ThreadId 'case9-thread'
    Assert-True ($case9.containmentStatus -eq 'BLOCKED') 'CASE9 unexplained baseline mismatch must be blocked.'
    Assert-True ($case9.blocker -eq 'BASELINE_LINEAGE_UNEXPLAINED') 'CASE9 exact blocker must identify unexplained lineage.'
    Assert-True ($case9.containment -eq 'RELATED_GIT_WORKTREE') 'CASE9 repository relationship should remain known.'
    Assert-True ($case9.startingSha -eq $case9NewHead) 'CASE9 must report the actual starting SHA.'
    Pass-Case 'CASE9_BASELINE_LINEAGE_UNEXPLAINED'

    $case10Root = Join-Path $temporaryRoot 'case10-canonical'
    $case10Worktree = Join-Path $temporaryRoot 'physically-different\nested\checkout'
    $case10Baseline = New-TestRepository $case10Root
    $null = Invoke-Git $case10Root worktree add -b 'case10-related' $case10Worktree $case10Baseline
    $case10 = Invoke-ContainmentResolver -ThreadCwd $case10Worktree -CanonicalGitRoot $case10Root -BatchBaselineSha $case10Baseline -ThreadId 'case10-thread'
    $case10ExpectedKey = 'git:' + ([System.IO.Path]::GetFullPath($case10Root)).ToLowerInvariant()
    Assert-True ($case10.containmentStatus -eq 'PASS') 'CASE10 physically different related worktree must pass.'
    Assert-True ($case10.projectKey -eq $case10ExpectedKey) 'CASE10 ProjectKey must remain the canonical repository identity.'
    Assert-True ($case10.threadGitRoot -ne $case10.canonicalGitRoot) 'CASE10 fixture must have different physical checkout paths.'
    Pass-Case 'CASE10_PROJECT_KEY_STAYS_CANONICAL'

    Write-Output "V2_REPOSITORY_CONTAINMENT_PASS=$script:caseCount"
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}
