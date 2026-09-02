[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $Root 'scripts\Resolve-ProjectIdentity.ps1'
$registryScript = Join-Path $Root 'scripts\Workstream-Registry.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-project-identity-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function New-TestGitRepository {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & git -C $Path init --initial-branch=main | Out-Null
    & git -C $Path config user.name 'Router V2 Test'
    & git -C $Path config user.email 'router-v2-test@invalid.local'
    [System.IO.File]::WriteAllText((Join-Path $Path 'identity.txt'), "identity fixture`n", [System.Text.UTF8Encoding]::new($false))
    & git -C $Path add identity.txt
    & git -C $Path commit -m 'identity fixture' | Out-Null
}

function Get-ExpectedIdentityPath {
    param([string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $rootPath.Length) {
        $fullPath = $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    if ([System.OperatingSystem]::IsWindows()) {
        $fullPath = $fullPath.ToLowerInvariant()
    }
    return $fullPath
}

try {
    $gitRepository = Join-Path $temporaryRoot 'repo-with-project-id'
    New-TestGitRepository -Path $gitRepository

    $case1 = & $resolver -ProjectId 'project-123' -CandidatePath $gitRepository | ConvertFrom-Json
    Assert-True ($case1.status -eq 'PASS') 'CASE 1 must PASS.'
    Assert-True ($case1.projectIdentitySource -eq 'APP_PROJECT_ID') 'CASE 1 must prefer app-native projectId.'
    Assert-True ($case1.projectKey -eq 'id:project-123') 'CASE 1 projectKey must use id:<projectId>.'
    Assert-True ($case1.projectId -eq 'project-123') 'CASE 1 must preserve projectId.'
    Assert-True (-not [string]::IsNullOrWhiteSpace($case1.canonicalGitRoot)) 'CASE 1 must retain canonical Git metadata.'
    Assert-True ($case1.headSha -match '^[0-9a-f]{40}$') 'CASE 1 must retain exact HEAD SHA.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_1_PASS'

    $case2 = & $resolver -CandidatePath $gitRepository | ConvertFrom-Json
    $expectedGitKey = 'git:' + (Get-ExpectedIdentityPath -Path $gitRepository)
    Assert-True ($case2.status -eq 'PASS') 'CASE 2 must PASS without projectId when Git identity is available.'
    Assert-True ($case2.projectIdentitySource -eq 'GIT_ROOT') 'CASE 2 must use canonical Git root identity.'
    Assert-True ($case2.projectKey -eq $expectedGitKey) 'CASE 2 projectKey must use git:<canonical-root>.'
    Assert-True ($null -eq $case2.projectId) 'CASE 2 projectId must remain null.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_2_PASS'

    Assert-True ($null -eq $case2.remoteUrl) 'CASE 3 remote must remain optional.'
    Assert-True ($case2.projectKey -eq $expectedGitKey) 'CASE 3 Git root must remain sufficient without a remote.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_3_PASS'

    $localFolder = Join-Path $temporaryRoot 'plain-local-workspace'
    New-Item -ItemType Directory -Path $localFolder -Force | Out-Null
    $case4 = & $resolver -CandidatePath $localFolder | ConvertFrom-Json
    $expectedPathKey = 'path:' + (Get-ExpectedIdentityPath -Path $localFolder)
    Assert-True ($case4.status -eq 'PASS') 'CASE 4 must PASS for an unambiguous non-Git local folder.'
    Assert-True ($case4.projectIdentitySource -eq 'CANONICAL_PATH') 'CASE 4 must use canonical path identity.'
    Assert-True ($case4.projectKey -eq $expectedPathKey) 'CASE 4 projectKey must use path:<canonical-path>.'
    Assert-True ($null -eq $case4.canonicalGitRoot) 'CASE 4 must not invent Git identity.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_4_PASS'

    $case5 = & $resolver -CandidatePath $localFolder -PathAmbiguous | ConvertFrom-Json
    Assert-True ($case5.status -eq 'BLOCKED') 'CASE 5 must block ambiguous canonical path identity.'
    Assert-True ($case5.projectIdentitySource -eq 'NONE') 'CASE 5 must not select an identity source.'
    Assert-True ($null -eq $case5.projectKey) 'CASE 5 must not invent a projectKey.'
    Assert-True ($case5.blocker -eq 'PROJECT_IDENTITY_BLOCKED') 'CASE 5 must return the exact blocker.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_5_PASS'

    $sameTitleFolderA = Join-Path $temporaryRoot 'parent-a\same-title'
    $sameTitleFolderB = Join-Path $temporaryRoot 'parent-b\same-title'
    New-Item -ItemType Directory -Path $sameTitleFolderA, $sameTitleFolderB -Force | Out-Null
    $case6a = & $resolver -CandidatePath $sameTitleFolderA | ConvertFrom-Json
    $case6b = & $resolver -CandidatePath $sameTitleFolderB | ConvertFrom-Json
    Assert-True ($case6a.status -eq 'PASS' -and $case6b.status -eq 'PASS') 'CASE 6 both folders must resolve.'
    Assert-True ((Split-Path -Leaf $case6a.canonicalPath) -eq (Split-Path -Leaf $case6b.canonicalPath)) 'CASE 6 fixture must have the same display title.'
    Assert-True ($case6a.projectKey -ne $case6b.projectKey) 'CASE 6 different canonical paths must have different projectKey values.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_6_PASS'

    $case7CodexHome = Join-Path $temporaryRoot 'case-7-codex-home'
    $case7Runtime = Join-Path $case7CodexHome 'auto-visible-team-router'
    New-Item -ItemType Directory -Path $case7Runtime -Force | Out-Null
    $legacyThreadId = 'legacy-v1-developer-thread'
    $legacyRegistry = [ordered]@{
        schemaVersion = 2
        entries = @(
            [ordered]@{
                projectPath = $gitRepository
                role = 'Developer'
                thread = [ordered]@{ id = $legacyThreadId }
            }
        )
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $case7Runtime 'thread-registry.json'), $legacyRegistry + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    & $registryScript -Action Init -CodexHome $case7CodexHome | Out-Null
    & $registryScript -Action BeginBatch -CodexHome $case7CodexHome -ProjectKey $case2.projectKey -BatchId 'case-7-current-batch' -Objective 'prove old permanent-role Thread is not adopted' | Out-Null
    & $registryScript -Action UpsertWorkstream -CodexHome $case7CodexHome -ProjectKey $case2.projectKey -BatchId 'case-7-current-batch' -WorkstreamId 'current-workstream' -State PROPOSED -OwnedScopeJson '["identity.txt"]' -DependenciesJson '[]' | Out-Null
    $case7Registry = & $registryScript -Action Status -CodexHome $case7CodexHome | ConvertFrom-Json
    $case7Workstream = $case7Registry.projects.($case2.projectKey).batches.'case-7-current-batch'.workstreams.'current-workstream'
    Assert-True ($null -eq $case7Workstream.threadId) 'CASE 7 must not auto-adopt the old V1 Developer Thread.'
    Assert-True (($case7Registry | ConvertTo-Json -Depth 40) -notmatch [regex]::Escape($legacyThreadId)) 'CASE 7 V2 Registry must not copy the V1 role Thread identity.'

    Write-Output 'V2_PROJECT_IDENTITY_CASE_7_PASS'
    Write-Output 'V2_PROJECT_IDENTITY_PASS=7'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Get-ChildItem -LiteralPath $resolvedTemporaryRoot -Recurse -Force | ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
