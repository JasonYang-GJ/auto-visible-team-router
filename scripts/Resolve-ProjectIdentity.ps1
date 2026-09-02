[CmdletBinding()]
param(
    [string]$ProjectId,
    [string]$CandidatePath,
    [switch]$PathAmbiguous
)

$ErrorActionPreference = 'Stop'

function Resolve-CanonicalPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }
    $fullPath = [System.IO.Path]::GetFullPath($PathValue)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $rootPath.Length) {
        $fullPath = $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $fullPath
}

function ConvertTo-IdentityPath {
    param([string]$PathValue)
    $identityPath = Resolve-CanonicalPath -PathValue $PathValue
    if ($identityPath -and [System.OperatingSystem]::IsWindows()) {
        $identityPath = $identityPath.ToLowerInvariant()
    }
    return $identityPath
}

$canonicalPath = Resolve-CanonicalPath -PathValue $CandidatePath
$canonicalGitRoot = $null
$headSha = $null
$remoteUrl = $null

if ($canonicalPath -and (Test-Path -LiteralPath $canonicalPath -PathType Container)) {
    $gitRootOutput = @(& git -C $canonicalPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $gitRootOutput.Count -gt 0) {
        $canonicalGitRoot = Resolve-CanonicalPath -PathValue $gitRootOutput[0]
        $headOutput = @(& git -C $canonicalGitRoot rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $headOutput.Count -gt 0) {
            $headSha = "$($headOutput[0])".Trim().ToLowerInvariant()
        }
        $remoteOutput = @(& git -C $canonicalGitRoot remote get-url origin 2>$null)
        if ($LASTEXITCODE -eq 0 -and $remoteOutput.Count -gt 0) {
            $remoteUrl = "$($remoteOutput[0])".Trim()
        }
    }
}

$repositoryIdentity = if ($canonicalGitRoot) {
    [ordered]@{
        canonicalRoot = $canonicalGitRoot
        headSha = $headSha
        remoteUrl = $remoteUrl
    }
}
else {
    $null
}

if (-not [string]::IsNullOrWhiteSpace($ProjectId)) {
    [ordered]@{
        status = 'PASS'
        projectIdentitySource = 'APP_PROJECT_ID'
        projectKey = 'id:' + $ProjectId.Trim()
        projectId = $ProjectId.Trim()
        canonicalGitRoot = $canonicalGitRoot
        canonicalPath = $canonicalPath
        headSha = $headSha
        remoteUrl = $remoteUrl
        repositoryIdentity = $repositoryIdentity
        blocker = $null
    } | ConvertTo-Json -Depth 10
    exit 0
}

if ($canonicalGitRoot -and $headSha) {
    [ordered]@{
        status = 'PASS'
        projectIdentitySource = 'GIT_ROOT'
        projectKey = 'git:' + (ConvertTo-IdentityPath -PathValue $canonicalGitRoot)
        projectId = $null
        canonicalGitRoot = $canonicalGitRoot
        canonicalPath = $canonicalPath
        headSha = $headSha
        remoteUrl = $remoteUrl
        repositoryIdentity = $repositoryIdentity
        blocker = $null
    } | ConvertTo-Json -Depth 10
    exit 0
}

if (-not $PathAmbiguous -and $canonicalPath -and (Test-Path -LiteralPath $canonicalPath -PathType Container)) {
    [ordered]@{
        status = 'PASS'
        projectIdentitySource = 'CANONICAL_PATH'
        projectKey = 'path:' + (ConvertTo-IdentityPath -PathValue $canonicalPath)
        projectId = $null
        canonicalGitRoot = $null
        canonicalPath = $canonicalPath
        headSha = $null
        remoteUrl = $null
        repositoryIdentity = $null
        blocker = $null
    } | ConvertTo-Json -Depth 10
    exit 0
}

[ordered]@{
    status = 'BLOCKED'
    projectIdentitySource = 'NONE'
    projectKey = $null
    projectId = $null
    canonicalGitRoot = $canonicalGitRoot
    canonicalPath = $canonicalPath
    headSha = $headSha
    remoteUrl = $remoteUrl
    repositoryIdentity = $repositoryIdentity
    blocker = 'PROJECT_IDENTITY_BLOCKED'
} | ConvertTo-Json -Depth 10
exit 0
