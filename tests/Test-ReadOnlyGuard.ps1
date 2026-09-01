[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$guardScript = Join-Path $SkillRoot 'scripts\ReadOnly-Guard.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("router-readonly-test-" + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $testRoot 'repo'
$guardStore = Join-Path $testRoot 'guards'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Guard([hashtable]$Parameters) {
    $raw = & $guardScript @Parameters | Out-String
    return ($raw | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init --initial-branch=main | Out-Null
    git -C $repo config user.name 'Router Test'
    git -C $repo config user.email 'router-test@example.invalid'
    [System.IO.File]::WriteAllText((Join-Path $repo 'owned.txt'), "baseline`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $repo add owned.txt
    git -C $repo commit -m 'initial' | Out-Null

    Assert-True (Test-Path -LiteralPath $guardScript) 'Read-only guard public command is missing.'
    if (-not (Test-Path -LiteralPath $guardScript)) { throw 'RED: ReadOnly-Guard.ps1 does not exist.' }

    $startClean = Invoke-Guard @{ Action='Start'; Repository=$repo; GuardStore=$guardStore; CheckId='clean-check'; Role='QA' }
    Assert-True ($startClean.status -eq 'BASELINE_CAPTURED') 'Start did not capture a baseline.'
    $finishClean = Invoke-Guard @{ Action='Finish'; Repository=$repo; GuardStore=$guardStore; CheckId='clean-check'; Role='QA' }
    Assert-True $finishClean.passed 'Unchanged read-only role should pass.'
    Assert-True ($finishClean.status -eq 'READ_ONLY_CONFIRMED') 'Clean finish has wrong status.'

    Invoke-Guard @{ Action='Start'; Repository=$repo; GuardStore=$guardStore; CheckId='research-check'; Role='Research' } | Out-Null
    $finishResearch = Invoke-Guard @{ Action='Finish'; Repository=$repo; GuardStore=$guardStore; CheckId='research-check'; Role='Research' }
    Assert-True $finishResearch.passed 'Unchanged Research role should pass.'
    Assert-True ($finishResearch.status -eq 'READ_ONLY_CONFIRMED') 'Research clean finish has wrong status.'

    Invoke-Guard @{ Action='Start'; Repository=$repo; GuardStore=$guardStore; CheckId='dirty-check'; Role='Architect' } | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'owned.txt'), "changed`n", (New-Object System.Text.UTF8Encoding($false)))
    $finishDirty = Invoke-Guard @{ Action='Finish'; Repository=$repo; GuardStore=$guardStore; CheckId='dirty-check'; Role='Architect' }
    Assert-True (-not $finishDirty.passed) 'A repository-state change during a read-only guard must fail closed.'
    Assert-True ($finishDirty.status -eq 'READ_ONLY_STATE_CHANGED') 'State-change status is missing.'
    Assert-True ($finishDirty.attribution -match 'Unresolved') 'The guard must not blame one role without attribution evidence.'
    Assert-True $finishDirty.failClosed 'A changed checkout must fail closed.'
    Assert-True ($finishDirty.before.fingerprint -ne $finishDirty.after.fingerprint) 'Before/after evidence must differ.'

    git -C $repo restore -- owned.txt
    Invoke-Guard @{ Action='Start'; Repository=$repo; GuardStore=$guardStore; CheckId='head-check'; Role='Reviewer' } | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'reviewer.txt'), "unauthorized`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $repo add reviewer.txt
    git -C $repo commit -m 'unauthorized reviewer commit' | Out-Null
    $finishHead = Invoke-Guard @{ Action='Finish'; Repository=$repo; GuardStore=$guardStore; CheckId='head-check'; Role='Reviewer' }
    Assert-True (-not $finishHead.passed) 'A read-only role commit must fail.'
    Assert-True ($finishHead.before.head -ne $finishHead.after.head) 'HEAD change evidence was not captured.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{
    suite = 'Policy-enforced read-only role guard'
    passed = ($failures.Count -eq 0)
    failures = $failures
} | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { exit 1 }
