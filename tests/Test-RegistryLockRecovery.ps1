[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$threadScript = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('router-lock-recovery-' + [guid]::NewGuid().ToString('N'))
$registry = Join-Path $testRoot 'thread-registry.json'
$lockPath = $registry + '.lock'
$failures = [System.Collections.Generic.List[string]]::new()
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }
function Write-Lock([string]$CreatedAt) {
    $metadata = [pscustomobject]@{
        pid=2147483000; processStartTimeUtc='2000-01-01T00:00:00.0000000Z'; createdAt=$CreatedAt
        registryPath=[System.IO.Path]::GetFullPath($registry); host=[Environment]::MachineName; sessionId='test-session'
    }
    [System.IO.File]::WriteAllText($lockPath, ($metadata | ConvertTo-Json -Compress), $utf8)
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Write-Lock ([datetimeoffset]::UtcNow.AddMinutes(-30).ToString('o'))
    $init = (((& $threadScript -Action Init -RegistryPath $registry -LockStaleMinutes 1) | Out-String) | ConvertFrom-Json)
    Assert-True ($init.schemaVersion -eq 2 -and (Test-Path -LiteralPath $registry)) 'Verified stale lock was not recovered.'
    Assert-True (-not (Test-Path -LiteralPath $lockPath)) 'Recovered lock residue remained.'

    Write-Lock ([datetimeoffset]::UtcNow.ToString('o'))
    $recentBlocked = $false
    try { & $threadScript -Action SetProjectBudget -RegistryPath $registry -ProjectId 'lock-test' -WorktreeBudget 3 -LockStaleMinutes 1 | Out-Null }
    catch { $recentBlocked = $_.Exception.Message -match 'cannot be proven stale|busy' }
    Assert-True $recentBlocked 'A recent lock with uncertain ownership did not fail closed.'
    Remove-Item -LiteralPath $lockPath -Force

    & $threadScript -Action SetProjectBudget -RegistryPath $registry -ProjectId 'lock-test' -WorktreeBudget 3 | Out-Null
    Assert-True (Test-Path -LiteralPath ($registry + '.bak')) 'Previous known-good Thread Registry backup is missing.'
    [System.IO.File]::WriteAllText($registry, '{corrupt', $utf8)
    $corruptionBlocked = $false
    try { & $threadScript -Action Status -RegistryPath $registry | Out-Null } catch { $corruptionBlocked = $_.Exception.Message -match 'corrupt' }
    Assert-True $corruptionBlocked 'Unknown Registry corruption was automatically hidden or restored.'
    Assert-True (([System.IO.File]::ReadAllText($registry,$utf8)) -eq '{corrupt') 'Corrupt Registry was silently overwritten.'
    $backup = Get-Content -LiteralPath ($registry + '.bak') -Raw | ConvertFrom-Json
    Assert-True ($backup.schemaVersion -eq 2) 'Known-good backup is not independently parseable.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{ suite='Registry lock verified stale recovery'; passed=($failures.Count -eq 0); failures=$failures } | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { exit 1 }
