[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$registryScript = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("router-registry-test-" + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'thread-registry.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Registry([hashtable]$Parameters) {
    $raw = & $registryScript @Parameters | Out-String
    if ($LASTEXITCODE) { throw "Registry command failed with exit code $LASTEXITCODE" }
    return ($raw | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Assert-True (Test-Path -LiteralPath $registryScript) 'Registry public command is missing.'
    if (-not (Test-Path -LiteralPath $registryScript)) { throw 'RED: Thread-Registry.ps1 does not exist.' }

    $init = Invoke-Registry @{ Action = 'Init'; RegistryPath = $registryPath }
    Assert-True ($init.schemaVersion -eq 2) 'Registry schema version must be 2.'
    Assert-True ($init.defaultWorktreeBudget -eq 3) 'Registry default Worktree Budget must be 3.'
    Assert-True (Test-Path -LiteralPath $registryPath) 'Init must persist the registry file.'

    $created = '2026-08-25T09:00:00+08:00'
    $verified = '2026-08-25T09:01:00+08:00'
    Invoke-Registry @{
        Action = 'Upsert'; RegistryPath = $registryPath
        ProjectId = 'project-1'; ProjectName = '测试项目'; ProjectPath = 'C:\safe\repo'
        Role = 'Frontend'; ThreadId = 'thread-frontend-1'; Title = '测试项目｜前端'
        State = 'Active'; Worktree = 'C:\safe\wt-frontend'; Branch = 'codex/frontend'
        CreatedAt = $created; VerifiedAt = $verified; Purpose = '测试可见任务复用'; Result = '初始已验证'
    } | Out-Null

    $found = Invoke-Registry @{
        Action = 'Find'; RegistryPath = $registryPath; ProjectId = 'project-1'; Role = 'Frontend'
    }
    Assert-True $found.found 'Find must return the persisted role.'
    Assert-True ($found.entry.thread.id -eq 'thread-frontend-1') 'Find returned the wrong thread id.'
    Assert-True ($found.entry.thread.lastVerifiedAt -eq $verified) 'Last verified time was not persisted.'
    Assert-True ($found.entry.worktree.path -eq 'C:\safe\wt-frontend') 'Worktree metadata was not persisted.'
    Assert-True ($found.entry.branch.name -eq 'codex/frontend') 'Branch metadata was not persisted separately.'
    Assert-True ($found.entry.purpose -eq '测试可见任务复用') 'Purpose was not persisted.'
    Assert-True ($found.entry.result -eq '初始已验证') 'Result was not persisted.'

    $duplicateBlocked = $false
    try {
        Invoke-Registry @{
            Action = 'Upsert'; RegistryPath = $registryPath
            ProjectId = 'project-1'; ProjectName = '测试项目'; Role = 'Frontend'
            ThreadId = 'thread-frontend-2'; Title = '测试项目｜前端'; State = 'Active'
        } | Out-Null
    } catch {
        $duplicateBlocked = $true
    }
    Assert-True $duplicateBlocked 'A second active same-project same-role thread must be blocked.'

    Invoke-Registry @{
        Action = 'SetState'; RegistryPath = $registryPath
        ThreadId = 'thread-frontend-1'; State = 'Stale'; VerifiedAt = '2026-08-25T09:02:00+08:00'
    } | Out-Null
    Invoke-Registry @{
        Action = 'Upsert'; RegistryPath = $registryPath
        ProjectId = 'project-1'; ProjectName = '测试项目'; Role = 'Frontend'
        ThreadId = 'thread-frontend-2'; Title = '测试项目｜前端'; State = 'Active'
        ReplacesThreadId = 'thread-frontend-1'
    } | Out-Null

    $replacement = Invoke-Registry @{
        Action = 'Find'; RegistryPath = $registryPath; ProjectId = 'project-1'; Role = 'Frontend'
    }
    Assert-True ($replacement.entry.thread.id -eq 'thread-frontend-2') 'Stale replacement was not selected.'
    Assert-True ($replacement.entry.replacesThreadId -eq 'thread-frontend-1') 'Replacement lineage was not recorded.'

    Invoke-Registry @{
        Action = 'SetState'; RegistryPath = $registryPath
        ThreadId = 'thread-frontend-2'; State = 'Archived'; VerifiedAt = '2026-08-25T09:03:00+08:00'
    } | Out-Null
    $archived = Invoke-Registry @{
        Action = 'Find'; RegistryPath = $registryPath; ProjectId = 'project-1'; Role = 'Frontend'; IncludeInactive = $true
    }
    Assert-True ($archived.entry.thread.state -eq 'Archived') 'Archived state was not persisted.'

    $raw = [System.IO.File]::ReadAllText($registryPath, (New-Object System.Text.UTF8Encoding($false)))
    $parsed = $raw | ConvertFrom-Json
    Assert-True ($parsed.entries.Count -eq 2) 'Registry must preserve stale history and current entry.'
    Assert-True ($parsed.events.Count -ge 4) 'Registry event history is incomplete.'
    Assert-True (-not (Test-Path -LiteralPath ($registryPath + '.lock'))) 'Registry lock leaked after operations.'

    # A fresh PowerShell process proves persistence across a new Codex/process session boundary.
    $fresh = & pwsh -NoProfile -File $registryScript -Action Find -RegistryPath $registryPath -ProjectId 'project-1' -Role 'Frontend' -IncludeInactive | ConvertFrom-Json
    Assert-True ($fresh.entry.thread.id -eq 'thread-frontend-2') 'Fresh-process recovery failed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$result = [pscustomobject]@{
    suite = 'Thread Registry public behavior'
    passed = ($failures.Count -eq 0)
    failures = $failures
}
$result | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { exit 1 }
