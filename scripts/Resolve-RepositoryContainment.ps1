[CmdletBinding()]
param(
    [string]$ThreadId,

    [Parameter(Mandatory = $true)]
    [string]$ThreadCwd,

    [Parameter(Mandatory = $true)]
    [string]$CanonicalGitRoot,

    [Parameter(Mandatory = $true)]
    [string]$BatchBaselineSha,

    [string]$CodexHome,
    [string]$AttributedDirtyPathsJson,
    [string]$AppManagedEvidenceJson,
    [string]$RouterCreatedEvidenceJson,
    [string]$LineageEvidenceJson
)

$ErrorActionPreference = 'Stop'

function Resolve-CanonicalPath {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $full = [System.IO.Path]::GetFullPath($resolved)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-PathEqual {
    param([string]$Left, [string]$Right)
    return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathWithin {
    param([string]$Candidate, [string]$Parent)
    if (-not $Candidate -or -not $Parent) { return $false }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $parentPrefix = $Parent.TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    return $Candidate.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-GitValue {
    param([string]$WorkingDirectory, [string[]]$Arguments)
    $output = @(& git -C $WorkingDirectory @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        return $null
    }
    return "$($output[0])".Trim()
}

function Resolve-GitReportedPath {
    param([string]$RepositoryRoot, [string]$ReportedPath)
    if ([string]::IsNullOrWhiteSpace($ReportedPath)) { return $null }
    if ([System.IO.Path]::IsPathRooted($ReportedPath)) {
        return Resolve-CanonicalPath $ReportedPath
    }
    return Resolve-CanonicalPath (Join-Path $RepositoryRoot $ReportedPath)
}

function Get-WorktreeInventoryPaths {
    param([string]$RepositoryRoot)
    $lines = @(& git -C $RepositoryRoot worktree list --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    $paths = @()
    foreach ($line in $lines) {
        if ($line -like 'worktree *') {
            $paths += Resolve-CanonicalPath $line.Substring(9)
        }
    }
    return $paths
}

function ConvertFrom-JsonStringArray {
    param([string]$Name, [string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    if (-not $Json.TrimStart().StartsWith('[')) { throw "$Name must be a JSON array." }
    return @($Json | ConvertFrom-Json | ForEach-Object { "$_" })
}

function Normalize-RelativePath {
    param([string]$Path)
    return $Path.Trim().Trim('"').Replace('/', '\').ToLowerInvariant()
}

function Get-DirtyState {
    param([string]$RepositoryRoot)
    $entries = @(& git -C $RepositoryRoot -c core.quotepath=false status --porcelain=v1 --untracked-files=all 2>$null | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read checkout dirty state.' }
    $paths = @()
    foreach ($entry in $entries) {
        if ($entry.Length -lt 4) { continue }
        $pathPart = $entry.Substring(3)
        if ($pathPart.Contains(' -> ')) {
            $paths += @($pathPart -split ' -> ' | ForEach-Object { Normalize-RelativePath $_ })
        }
        else {
            $paths += Normalize-RelativePath $pathPart
        }
    }
    return [ordered]@{ entries = @($entries); paths = @($paths | Select-Object -Unique) }
}

function Resolve-CodexHomePath {
    if ($CodexHome -and (Test-Path -LiteralPath $CodexHome)) { return Resolve-CanonicalPath $CodexHome }
    if ($env:CODEX_HOME -and (Test-Path -LiteralPath $env:CODEX_HOME)) { return Resolve-CanonicalPath $env:CODEX_HOME }
    $default = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    if (Test-Path -LiteralPath $default) { return Resolve-CanonicalPath $default }
    return $null
}

function Test-AppManagedEvidence {
    param([string]$Json, [string]$ExpectedThreadId, [string]$ExpectedCheckoutPath, [string]$ExpectedCanonicalRoot)
    if ([string]::IsNullOrWhiteSpace($Json)) { return $false }
    try {
        $evidence = $Json | ConvertFrom-Json
        if (-not $evidence.evidenceSource -or -not $evidence.threadId -or -not $evidence.checkoutPath -or -not $evidence.canonicalGitRoot) { return $false }
        return ($ExpectedThreadId -and $evidence.threadId -eq $ExpectedThreadId -and
            (Test-PathEqual (Resolve-CanonicalPath $evidence.checkoutPath) $ExpectedCheckoutPath) -and
            (Test-PathEqual (Resolve-CanonicalPath $evidence.canonicalGitRoot) $ExpectedCanonicalRoot))
    }
    catch { return $false }
}

function Test-RouterCreationEvidence {
    param([string]$Json, [string]$ExpectedThreadId, [string]$ExpectedCheckoutPath)
    if ([string]::IsNullOrWhiteSpace($Json)) { return $false }
    try {
        $evidence = $Json | ConvertFrom-Json
        if (-not $evidence.evidenceSource -or -not $evidence.requestId -or -not $evidence.threadId -or -not $evidence.checkoutPath) { return $false }
        return ($ExpectedThreadId -and $evidence.threadId -eq $ExpectedThreadId -and
            (Test-PathEqual (Resolve-CanonicalPath $evidence.checkoutPath) $ExpectedCheckoutPath))
    }
    catch { return $false }
}

function Test-LineageEvidence {
    param([string]$Json, [string]$RepositoryRoot, [string]$BaselineSha, [string]$StartingSha)
    if ($BaselineSha -eq $StartingSha) { return $true }
    if ([string]::IsNullOrWhiteSpace($Json)) { return $false }
    try {
        $evidence = $Json | ConvertFrom-Json
        if ($evidence.batchBaselineSha -ne $BaselineSha -or $evidence.startingSha -ne $StartingSha -or -not $evidence.reason -or -not $evidence.evidenceId) { return $false }
        if ($evidence.relationship -eq 'DESCENDANT_OF_BASELINE') {
            $null = & git -C $RepositoryRoot merge-base --is-ancestor $BaselineSha $StartingSha 2>$null
            return $LASTEXITCODE -eq 0
        }
        if ($evidence.relationship -eq 'ANCESTOR_OF_BASELINE') {
            $null = & git -C $RepositoryRoot merge-base --is-ancestor $StartingSha $BaselineSha 2>$null
            return $LASTEXITCODE -eq 0
        }
        return $false
    }
    catch { return $false }
}

function New-Result {
    param(
        [string]$Status,
        [string]$Blocker,
        [string]$ThreadRoot,
        [string]$ThreadGitDir,
        [string]$ThreadCommonDir,
        [string]$CanonicalRoot,
        [string]$CanonicalCommonDir,
        [bool]$InventoryMatch,
        [string]$StartingSha,
        [string]$CheckoutType,
        [string]$Containment,
        [string]$BranchOrDetached,
        [string[]]$DirtyPaths,
        [string]$Management,
        [bool]$AppEvidenceMatch = $false,
        [bool]$DirtyStateAttributed = $false,
        [bool]$LineageExplained = $false,
        [bool]$CreatedByRouter = $false
    )
    $keyComponent = if ($CanonicalRoot) { $CanonicalRoot.ToLowerInvariant() } else { $null }
    [ordered]@{
        threadId = if ($ThreadId) { $ThreadId } else { $null }
        threadCwd = $ThreadCwd
        threadGitRoot = $ThreadRoot
        threadGitDir = $ThreadGitDir
        threadGitCommonDir = $ThreadCommonDir
        canonicalGitRoot = $CanonicalRoot
        canonicalGitCommonDir = $CanonicalCommonDir
        projectKey = if ($keyComponent) { "git:$keyComponent" } else { $null }
        worktreeInventoryMatch = $InventoryMatch
        appManagedEvidenceMatch = $AppEvidenceMatch
        startingSha = $StartingSha
        batchBaselineSha = $BatchBaselineSha
        lineageExplained = $LineageExplained
        branchOrDetached = $BranchOrDetached
        checkoutType = $CheckoutType
        containment = $Containment
        containmentStatus = $Status
        dirtyPaths = @($DirtyPaths)
        dirtyStateAttributed = $DirtyStateAttributed
        management = $Management
        createdByRouter = $CreatedByRouter
        blocker = $Blocker
    } | ConvertTo-Json -Depth 12
}

$canonicalRoot = $null
$canonicalCommonDir = $null
$threadRoot = $null
$threadGitDir = $null
$threadCommonDir = $null
$threadSha = $null

try {
    $canonicalRoot = Resolve-CanonicalPath $CanonicalGitRoot
    $canonicalReportedRoot = Invoke-GitValue $canonicalRoot @('rev-parse', '--show-toplevel')
    if (-not $canonicalReportedRoot) { throw 'Authorized root is not a Git repository.' }
    $canonicalReportedRoot = Resolve-CanonicalPath $canonicalReportedRoot
    if (-not (Test-PathEqual $canonicalRoot $canonicalReportedRoot)) {
        throw 'Authorized root is not the canonical repository top level.'
    }
    $canonicalCommonDir = Resolve-GitReportedPath $canonicalRoot (Invoke-GitValue $canonicalRoot @('rev-parse', '--git-common-dir'))
}
catch {
    New-Result -Status 'BLOCKED' -Blocker 'CANONICAL_REPOSITORY_INVALID' -ThreadRoot $null -ThreadGitDir $null -ThreadCommonDir $null -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $false -StartingSha $null -CheckoutType 'UNKNOWN' -Containment 'UNKNOWN' -BranchOrDetached $null -DirtyPaths @() -Management 'UNKNOWN'
    exit 0
}

try {
    $threadPath = Resolve-CanonicalPath $ThreadCwd
    $threadRootValue = Invoke-GitValue $threadPath @('rev-parse', '--show-toplevel')
    if (-not $threadRootValue) { throw 'Thread cwd is not a Git checkout.' }
    $threadRoot = Resolve-CanonicalPath $threadRootValue
    $threadGitDir = Resolve-GitReportedPath $threadRoot (Invoke-GitValue $threadRoot @('rev-parse', '--git-dir'))
    $threadCommonDir = Resolve-GitReportedPath $threadRoot (Invoke-GitValue $threadRoot @('rev-parse', '--git-common-dir'))
    $threadSha = Invoke-GitValue $threadRoot @('rev-parse', 'HEAD')
}
catch {
    New-Result -Status 'BLOCKED' -Blocker 'CONTAINMENT_UNPROVEN' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $false -StartingSha $threadSha -CheckoutType 'UNKNOWN' -Containment 'UNKNOWN' -BranchOrDetached $null -DirtyPaths @() -Management 'UNKNOWN'
    exit 0
}

$inventoryPaths = @(Get-WorktreeInventoryPaths $canonicalRoot)
$inventoryMatch = @($inventoryPaths | Where-Object { Test-PathEqual $_ $threadRoot }).Count -gt 0
$appEvidenceMatch = Test-AppManagedEvidence -Json $AppManagedEvidenceJson -ExpectedThreadId $ThreadId -ExpectedCheckoutPath $threadRoot -ExpectedCanonicalRoot $canonicalRoot
$relationshipEvidenceMatch = $inventoryMatch -or $appEvidenceMatch
$branch = Invoke-GitValue $threadRoot @('symbolic-ref', '--short', '-q', 'HEAD')
$branchOrDetached = if ($branch) { $branch } else { 'DETACHED' }
try {
    $dirtyState = Get-DirtyState $threadRoot
    $dirtyPaths = @($dirtyState.paths)
    $attributedDirtyPaths = @(ConvertFrom-JsonStringArray -Name 'AttributedDirtyPathsJson' -Json $AttributedDirtyPathsJson | ForEach-Object { Normalize-RelativePath $_ })
}
catch {
    New-Result -Status 'BLOCKED' -Blocker 'DIRTY_ATTRIBUTION_INVALID' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType 'UNKNOWN' -Containment 'UNKNOWN' -BranchOrDetached $branchOrDetached -DirtyPaths @() -Management 'UNKNOWN' -AppEvidenceMatch $appEvidenceMatch
    exit 0
}

$unattributedDirtyPaths = @($dirtyPaths | Where-Object { $_ -notin $attributedDirtyPaths })
$dirtyStateAttributed = $unattributedDirtyPaths.Count -eq 0
$isPrimary = Test-PathEqual $threadRoot $canonicalRoot
$commonDirMatch = Test-PathEqual $threadCommonDir $canonicalCommonDir
$resolvedCodexHome = Resolve-CodexHomePath
$codexWorktreesCandidate = if ($resolvedCodexHome) { Join-Path $resolvedCodexHome 'worktrees' } else { $null }
$codexWorktreesRoot = if ($codexWorktreesCandidate -and (Test-Path -LiteralPath $codexWorktreesCandidate)) { Resolve-CanonicalPath $codexWorktreesCandidate } else { $null }
$isCodexManaged = (-not $isPrimary) -and ((Test-PathWithin $threadRoot $codexWorktreesRoot) -or $appEvidenceMatch)
$checkoutType = if ($isPrimary) { 'PRIMARY_CHECKOUT' } elseif ($isCodexManaged) { 'CODEX_MANAGED_WORKTREE' } else { 'PERMANENT_WORKTREE' }
$containment = if ($isPrimary) { 'PRIMARY_CHECKOUT' } else { 'RELATED_GIT_WORKTREE' }
$management = if ($isPrimary) { 'PRIMARY' } elseif ($isCodexManaged) { 'CODEX_MANAGED' } else { 'EXTERNAL' }
$lineageExplained = Test-LineageEvidence -Json $LineageEvidenceJson -RepositoryRoot $threadRoot -BaselineSha $BatchBaselineSha -StartingSha $threadSha
$createdByRouter = $isCodexManaged -and (Test-RouterCreationEvidence -Json $RouterCreatedEvidenceJson -ExpectedThreadId $ThreadId -ExpectedCheckoutPath $threadRoot)

if (-not $commonDirMatch) {
    New-Result -Status 'BLOCKED' -Blocker 'UNRELATED_CHECKOUT' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType 'UNRELATED_CHECKOUT' -Containment 'UNRELATED_CHECKOUT' -BranchOrDetached $branchOrDetached -DirtyPaths $dirtyPaths -Management 'EXTERNAL' -AppEvidenceMatch $appEvidenceMatch -DirtyStateAttributed $dirtyStateAttributed -LineageExplained $lineageExplained
    exit 0
}

if (($isPrimary -and -not $inventoryMatch) -or ((-not $isPrimary) -and -not $relationshipEvidenceMatch)) {
    New-Result -Status 'BLOCKED' -Blocker 'CONTAINMENT_UNPROVEN' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType 'UNKNOWN' -Containment 'UNKNOWN' -BranchOrDetached $branchOrDetached -DirtyPaths $dirtyPaths -Management 'UNKNOWN' -AppEvidenceMatch $appEvidenceMatch -DirtyStateAttributed $dirtyStateAttributed -LineageExplained $lineageExplained
    exit 0
}

if (-not $dirtyStateAttributed) {
    New-Result -Status 'BLOCKED' -Blocker 'UNATTRIBUTED_DIRTY_STATE' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType $checkoutType -Containment $containment -BranchOrDetached $branchOrDetached -DirtyPaths $dirtyPaths -Management $management -AppEvidenceMatch $appEvidenceMatch -DirtyStateAttributed $false -LineageExplained $lineageExplained -CreatedByRouter $createdByRouter
    exit 0
}

if (-not $lineageExplained) {
    New-Result -Status 'BLOCKED' -Blocker 'BASELINE_LINEAGE_UNEXPLAINED' -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType $checkoutType -Containment $containment -BranchOrDetached $branchOrDetached -DirtyPaths $dirtyPaths -Management $management -AppEvidenceMatch $appEvidenceMatch -DirtyStateAttributed $true -LineageExplained $false -CreatedByRouter $createdByRouter
    exit 0
}

New-Result -Status 'PASS' -Blocker $null -ThreadRoot $threadRoot -ThreadGitDir $threadGitDir -ThreadCommonDir $threadCommonDir -CanonicalRoot $canonicalRoot -CanonicalCommonDir $canonicalCommonDir -InventoryMatch $inventoryMatch -StartingSha $threadSha -CheckoutType $checkoutType -Containment $containment -BranchOrDetached $branchOrDetached -DirtyPaths $dirtyPaths -Management $management -AppEvidenceMatch $appEvidenceMatch -DirtyStateAttributed $true -LineageExplained $true -CreatedByRouter $createdByRouter
