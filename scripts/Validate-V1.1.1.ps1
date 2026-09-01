[CmdletBinding()]
param(
    [string]$SkillRoot,
    [string]$AgentsPath
)

$ErrorActionPreference = 'Stop'
if (-not $SkillRoot) { $SkillRoot = Split-Path -Parent $PSScriptRoot }
$SkillRoot = [System.IO.Path]::GetFullPath($SkillRoot)
if (-not $AgentsPath) {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
    $AgentsPath = Join-Path $codexHome 'AGENTS.md'
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Router([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

$required = @(
    'SKILL.md', 'VERSION', 'README.md', 'agents\openai.yaml',
    'references\routing-policy.md', 'references\role-catalog.md',
    'references\thread-lifecycle.md', 'references\acceptance-tests.md',
    'scripts\Manage-Global.ps1', 'scripts\Thread-Registry.ps1',
    'scripts\ReadOnly-Guard.ps1', 'scripts\Validate-V1.ps1',
    'scripts\Validate-V1.1.ps1', 'scripts\Validate-V1.1.1.ps1',
    'tests\Test-ThreadRegistry.ps1', 'tests\Test-LifecycleRegistry.ps1',
    'tests\Test-ReadOnlyGuard.ps1', 'tests\Test-ManagementLifecycle.ps1',
    'tests\Test-RegistryScale.ps1'
)
foreach ($relative in $required) {
    Assert-Router (Test-Path -LiteralPath (Join-Path $SkillRoot $relative)) "Missing required file: $relative"
}

$skillText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'SKILL.md'), $utf8NoBom)
$yamlText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'agents\openai.yaml'), $utf8NoBom)
$readmeText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'README.md'), $utf8NoBom)
$lifecycleText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\thread-lifecycle.md'), $utf8NoBom)
$acceptanceText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'references\acceptance-tests.md'), $utf8NoBom)
$registryText = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'), $utf8NoBom)
$version = [System.IO.File]::ReadAllText((Join-Path $SkillRoot 'VERSION'), $utf8NoBom).Trim()

Assert-Router ($skillText -match '(?m)^name:\s*auto-visible-team-router\s*$') 'Invalid skill name.'
Assert-Router ($skillText -match '(?m)^description:\s*\S') 'Missing skill description.'
Assert-Router ($skillText -match '(?m)^\s+version:\s*"1\.1\.1"\s*$') 'Missing V1.1.1 metadata.'
Assert-Router ($version -eq '1.1.1') 'VERSION is not 1.1.1.'
Assert-Router ($yamlText -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$') 'Implicit invocation is not enabled.'
Assert-Router ($skillText -notmatch '(?m)^\s*(model|thinking)\s*:') 'Pinned model or thinking route found.'
Assert-Router ($skillText -notmatch '(?i)C:\\Users\\|/Users/[^/]+/') 'Machine-specific user path found in SKILL.md.'
Assert-Router ($skillText.Contains('Registry-first reuse')) 'Registry-first reuse policy is missing.'
Assert-Router ($skillText.Contains('Team Adoption')) 'Team Adoption policy is missing.'
Assert-Router ($skillText.Contains('Thread, Worktree, and Branch are different objects')) 'Three-object distinction is missing.'
Assert-Router ($skillText.Contains('default per-project Worktree Budget is three')) 'Worktree Budget policy is missing.'
Assert-Router ($skillText.Contains('two or more coding Agents')) 'Parallel writer gate is missing.'
Assert-Router ($skillText.Contains('Policy-Enforced Read')) 'Read-only role policy is missing.'
Assert-Router ($skillText.Contains('new SHA')) 'QA new-SHA gate is missing.'
Assert-Router ($lifecycleText -match 'source of\s+truth') 'Thread API truth-source rule is missing.'
Assert-Router ($lifecycleText.Contains('git merge-base --is-ancestor')) 'Branch containment proof is missing.'
Assert-Router ($lifecycleText.Contains('createdByRouter=false')) 'Adopted ownership rule is missing.'
Assert-Router ($lifecycleText.Contains('reuse a compatible idle Worktree')) 'Budget fallback order is missing.'
Assert-Router ($readmeText.Contains('once per run/session')) 'Old-task AGENTS reload guidance is missing.'
Assert-Router ($registryText.Contains("schemaVersion = 2")) 'Registry schema 2 is missing.'
Assert-Router ($registryText.Contains("'Adopt'")) 'Registry Adopt action is missing.'
Assert-Router ($registryText.Contains("'GetProjectBudget'")) 'Registry budget query is missing.'

$numbered = [regex]::Matches($acceptanceText, '(?m)^(\d+)\.\s')
Assert-Router ($numbered.Count -eq 35) "Expected 35 acceptance tests, found $($numbered.Count)."
if ($numbered.Count -eq 35) {
    for ($i = 1; $i -le 35; $i++) {
        Assert-Router ([int]$numbered[$i - 1].Groups[1].Value -eq $i) "Acceptance numbering breaks at $i."
    }
}

$agentsText = if (Test-Path -LiteralPath $AgentsPath) { [System.IO.File]::ReadAllText($AgentsPath, $utf8NoBom) } else { '' }
$beginCount = ([regex]::Matches($agentsText, '<!-- BEGIN auto-visible-team-router:v1(?: separatorChars=\d+)? -->')).Count
$endCount = ([regex]::Matches($agentsText, [regex]::Escape('<!-- END auto-visible-team-router:v1 -->'))).Count
Assert-Router ($beginCount -eq 1) "Expected one begin marker, found $beginCount."
Assert-Router ($endCount -eq 1) "Expected one end marker, found $endCount."

$parseErrors = @()
Get-ChildItem -LiteralPath $SkillRoot -Filter '*.ps1' -File -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($error in @($errors)) { $parseErrors += "$($_.FullName): $($error.Message)" }
}
Assert-Router ($parseErrors.Count -eq 0) "PowerShell parse errors: $($parseErrors -join '; ')"

$fixtures = @(
    [pscustomobject]@{test=1;name='tiny-edit';applicable=$true;score=3;expectedLevel=0;expectedNew=0},
    [pscustomobject]@{test=2;name='responsive-frontend';applicable=$true;score=18;expectedLevel=1;expectedNew=1},
    [pscustomobject]@{test=3;name='profile-cross-layer';applicable=$true;score=47;expectedLevel=2;expectedNew=2},
    [pscustomobject]@{test=4;name='windows-ai-system';applicable=$true;score=82;expectedLevel=3;expectedNew=3},
    [pscustomobject]@{test=5;name='reuse';applicable=$true;score=74;expectedLevel=3;expectedNew=0},
    [pscustomobject]@{test=6;name='failure-escalation';applicable=$true;score=32;expectedLevel=1;expectedNew=1},
    [pscustomobject]@{test=7;name='ordinary-chat';applicable=$false;score=$null;expectedLevel=$null;expectedNew=0}
)
function Get-Level([int]$Score) {
    if ($Score -le 14) { return 0 }
    if ($Score -le 34) { return 1 }
    if ($Score -le 59) { return 2 }
    return 3
}
$fixtureResults = foreach ($fixture in $fixtures) {
    $actual = if ($fixture.applicable) { Get-Level $fixture.score } else { $null }
    $passed = $actual -eq $fixture.expectedLevel
    Assert-Router $passed "Routing fixture $($fixture.name) failed."
    [pscustomobject]@{test=$fixture.test;name=$fixture.name;level=$actual;expectedNew=$fixture.expectedNew;passed=$passed}
}

[pscustomobject]@{
    suite='V1.1.1 static validation'; skillRoot=$SkillRoot
    agentsPath=[System.IO.Path]::GetFullPath($AgentsPath); version=$version
    requiredFiles=$required.Count; acceptanceTests=$numbered.Count
    markers=[pscustomobject]@{begin=$beginCount;end=$endCount}
    routingFixtures=$fixtureResults; failures=$failures; passed=($failures.Count -eq 0)
} | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) { exit 1 }
