[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$script = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("router-registry-scale-" + [guid]::NewGuid().ToString('N'))
$registry = Join-Path $testRoot 'registry.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }
function Invoke-Registry([hashtable]$Parameters) { (& $script @Parameters | Out-String) | ConvertFrom-Json }

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Invoke-Registry @{Action='Init';RegistryPath=$registry} | Out-Null
    for ($i = 1; $i -le 60; $i++) {
        Invoke-Registry @{
            Action='Upsert';RegistryPath=$registry;ProjectId=("project-{0:D2}" -f $i)
            ProjectName=("项目{0:D2}" -f $i);Role='Frontend';ThreadId=("thread-{0:D2}" -f $i)
            Title=("项目{0:D2}｜前端" -f $i);State='Active'
        } | Out-Null
    }
    $status = Invoke-Registry @{Action='Status';RegistryPath=$registry}
    Assert-True ($status.entryCount -eq 60) 'Registry did not persist all 60 entries.'
    $target = Invoke-Registry @{Action='Find';RegistryPath=$registry;ProjectId='project-60';Role='Frontend'}
    Assert-True $target.found 'Target beyond the first 50 was not found.'
    Assert-True ($target.entry.thread.id -eq 'thread-60') 'Target beyond 50 returned the wrong ID.'
    $fresh = & pwsh -NoProfile -File $script -Action Find -RegistryPath $registry -ProjectId 'project-60' -Role Frontend | ConvertFrom-Json
    Assert-True ($fresh.entry.thread.id -eq 'thread-60') 'Fresh-process lookup beyond 50 failed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{suite='Registry over-50 compensation';passed=($failures.Count -eq 0);failures=$failures} | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { exit 1 }
