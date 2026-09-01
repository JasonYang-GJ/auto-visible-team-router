[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$registryScript = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("router-lifecycle-registry-" + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'registry.json'
$legacyRegistryPath = Join-Path $testRoot 'legacy-registry.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Registry([hashtable]$Parameters) {
    (& $registryScript @Parameters | Out-String) | ConvertFrom-Json
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    $init = Invoke-Registry @{ Action='Init'; RegistryPath=$registryPath }
    Assert-True ($init.schemaVersion -eq 2) 'V1.1.1 Registry schema must be 2.'
    Assert-True ($init.defaultWorktreeBudget -eq 3) 'Default Worktree Budget must be 3.'

    $adopted = Invoke-Registry @{
        Action='Adopt'; RegistryPath=$registryPath
        ProjectId='project-island'; ProjectName='超级灵动岛'; ProjectPath='C:\safe\island'
        Role='Developer'; ThreadId='thread-dev'; Title='Yuanshu Island｜Stage 2 Developer'
        State='Active'; Worktree='C:\safe\wt-dev'; Branch='codex/stage2c-developer'
        BaseCommit='1111111111111111111111111111111111111111'
        WorktreeCreatedAt='2026-08-24T20:00:00+08:00'; WorktreeState='Active'
        CommitSha='2222222222222222222222222222222222222222'
        QaStatus='PASS'; IntegrationState='Merged'
    }
    Assert-True ($adopted.entry.thread.id -eq 'thread-dev') 'Thread identity must live in the Thread object.'
    Assert-True ($adopted.entry.thread.origin -eq 'Adopted') 'Adopted Thread origin was not recorded.'
    Assert-True ($adopted.entry.worktree.path -eq 'C:\safe\wt-dev') 'Worktree path was not recorded separately.'
    Assert-True ($adopted.entry.worktree.threadId -eq 'thread-dev') 'Worktree must record its Thread ID.'
    Assert-True ($adopted.entry.worktree.branch -eq 'codex/stage2c-developer') 'Worktree must record its Branch.'
    Assert-True ($adopted.entry.worktree.baseCommit -eq '1111111111111111111111111111111111111111') 'Worktree Base Commit is missing.'
    Assert-True ($adopted.entry.worktree.createdAt -eq '2026-08-24T20:00:00+08:00') 'Worktree CreatedAt is missing.'
    Assert-True ($adopted.entry.worktree.state -eq 'Active') 'Worktree state is missing.'
    Assert-True ($adopted.entry.worktree.management -eq 'Adopted') 'Adopted worktree management was not recorded.'
    Assert-True (-not $adopted.entry.worktree.createdByRouter) 'Adopted worktree must not be claimed as Router-created.'
    Assert-True ($adopted.entry.branch.name -eq 'codex/stage2c-developer') 'Branch identity must live in the Branch object.'
    Assert-True ($adopted.entry.branch.ownership -eq 'PreExisting') 'Pre-existing Branch ownership was not preserved.'
    Assert-True (-not $adopted.entry.branch.autoDeleteEligible) 'Pre-existing Branch must not be auto-delete eligible.'

    $refreshed = Invoke-Registry @{
        Action='Upsert'; RegistryPath=$registryPath; ProjectId='project-island'
        ProjectName='超级灵动岛'; Role='Developer'; ThreadId='thread-dev'
        Title='Yuanshu Island｜Stage 2 Developer'; State='Active'
        VerifiedAt='2026-08-25T10:00:00+08:00'
    }
    Assert-True ($refreshed.entry.thread.origin -eq 'Adopted') 'A verification refresh must preserve adopted Thread origin.'
    Assert-True ($refreshed.entry.worktree.path -eq 'C:\safe\wt-dev') 'A verification refresh must preserve Worktree metadata.'
    Assert-True ($refreshed.entry.branch.ownership -eq 'PreExisting') 'A verification refresh must preserve Branch ownership.'

    $budget = Invoke-Registry @{
        Action='GetProjectBudget'; RegistryPath=$registryPath; ProjectId='project-island'
    }
    Assert-True ($budget.budget -eq 3) 'Project default budget must resolve to 3.'
    Assert-True ($budget.activeManagedWorktrees -eq 1) 'Adopted active worktree must count toward the managed budget.'
    Assert-True ($budget.remaining -eq 2) 'Remaining budget is incorrect.'
    Assert-True ($budget.whenReached[0] -eq 'ReuseIdle') 'Budget response must prefer idle worktree reuse.'
    Assert-True ($budget.whenReached[1] -eq 'Wait') 'Budget response must next prefer waiting.'
    Assert-True ($budget.whenReached[2] -eq 'Serialize') 'Budget response must finally serialize.'

    $metadataBlocked = $false
    try {
        Invoke-Registry @{
            Action='Upsert'; RegistryPath=$registryPath
            ProjectId='project-2'; ProjectName='项目2'; Role='Backend'
            ThreadId='thread-backend'; Title='项目2｜后端'; State='Active'
            Worktree='C:\safe\wt-backend'; Branch='codex/backend'
            WorktreeManagement='RouterCreated'; TemporaryWorktree=$true
        } | Out-Null
    } catch {
        $metadataBlocked = $true
    }
    Assert-True $metadataBlocked 'Router-created temporary worktree must require full lifecycle metadata.'

    $detached = Invoke-Registry @{
        Action='Upsert'; RegistryPath=$registryPath
        ProjectId='project-3'; ProjectName='项目3'; Role='Backend'
        ThreadId='thread-detached'; Title='项目3｜后端'; State='Active'
        Worktree='C:\safe\wt-detached'; DetachedWorktree=$true
        BaseCommit='3333333333333333333333333333333333333333'
        WorktreeCreatedAt='2026-08-25T11:00:00+08:00'; WorktreeState='Active'
        WorktreeManagement='RouterCreated'; TemporaryWorktree=$true
    }
    Assert-True ($detached.entry.worktree.branch -eq 'DETACHED') 'Detached Worktree state was not explicit.'
    Assert-True ($null -eq $detached.entry.branch) 'Detached Worktree must not invent a Git Branch object.'

    $legacyJson = @'
{"schemaVersion":1,"updatedAt":"2026-08-25T00:00:00+08:00","entries":[{"projectKey":"id:legacy","projectId":"legacy","projectName":"旧项目","projectPath":"C:\\safe\\legacy","role":"QA","threadId":"legacy-thread","title":"旧项目｜QA","createdAt":"2026-08-24T00:00:00+08:00","lastVerifiedAt":null,"state":"Archived","worktree":"C:\\safe\\legacy-wt","branch":"release/1","replacesThreadId":null,"purpose":"保留","result":"完成"}],"events":[]}
'@
    [System.IO.File]::WriteAllText($legacyRegistryPath, $legacyJson, (New-Object System.Text.UTF8Encoding($false)))
    $migrated = Invoke-Registry @{ Action='Init'; RegistryPath=$legacyRegistryPath }
    Assert-True ($migrated.schemaVersion -eq 2) 'Schema 1 Registry was not migrated to schema 2.'
    Assert-True ($migrated.entries[0].thread.id -eq 'legacy-thread') 'Migration lost the legacy Thread ID.'
    Assert-True ($migrated.entries[0].worktree.path -eq 'C:\safe\legacy-wt') 'Migration lost the legacy Worktree path.'
    Assert-True ($migrated.entries[0].branch.protected) 'Migration did not protect a release Branch.'
    Assert-True (-not $migrated.entries[0].branch.autoDeleteEligible) 'Migrated unknown Branch must not become auto-delete eligible.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{
    suite='V1.1.1 lifecycle registry'
    passed=($failures.Count -eq 0)
    failures=$failures
} | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { exit 1 }
