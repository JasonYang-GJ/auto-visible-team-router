[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
$manage = Join-Path $Root 'scripts\Manage-Global.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('auto-visible-router-v2-rollback-' + [guid]::NewGuid().ToString('N'))
$codexHome = Join-Path $temporaryRoot 'codex-home'
$skillRoot = Join-Path $temporaryRoot 'agents\skills\auto-visible-team-router'
$runtimeRoot = Join-Path $codexHome 'auto-visible-team-router'
$agentsPath = Join-Path $codexHome 'AGENTS.md'
$badSource = Join-Path $temporaryRoot 'bad-v2-source'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

try {
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $badSource | Out-Null
    foreach ($fileName in @('README.md', 'SKILL.md', 'VERSION', 'V2_COMPLETE_PLAN.md')) {
        Copy-Item -LiteralPath (Join-Path $Root $fileName) -Destination (Join-Path $badSource $fileName)
    }
    foreach ($directoryName in @('agents', 'examples', 'references', 'schemas', 'scripts', 'templates', 'tests')) {
        Copy-Item -Recurse -LiteralPath (Join-Path $Root $directoryName) -Destination (Join-Path $badSource $directoryName)
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $badSource 'templates\AGENTS-v2-shadow.md'),
        "BROKEN SHADOW TEMPLATE WITHOUT MANAGED MARKERS`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    [System.IO.File]::WriteAllText((Join-Path $skillRoot 'VERSION'), "1.3.3`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $skillRoot 'SKILL.md'), "# V1 rollback fixture`n", [System.Text.UTF8Encoding]::new($false))
    $legacyRegistry = '{"schemaVersion":2,"entries":[{"thread":{"id":"rollback-thread"}}]}' + [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $runtimeRoot 'thread-registry.json'), $legacyRegistry, [System.Text.UTF8Encoding]::new($false))
    $agentsBefore = @'
ROLLBACK-PREFIX

<!-- BEGIN auto-visible-team-router:v1 separatorChars=0 -->
## V1 rollback fixture
<!-- END auto-visible-team-router:v1 -->

ROLLBACK-SUFFIX
'@
    [System.IO.File]::WriteAllText($agentsPath, $agentsBefore, [System.Text.UTF8Encoding]::new($false))

    $failed = $false
    try {
        & $manage -Action InstallShadow -SourceRoot $badSource -CodexHome $codexHome -SkillRoot $skillRoot | Out-Null
    }
    catch {
        $failed = $true
    }
    Assert-True $failed 'Broken SHADOW installation must fail.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $skillRoot 'VERSION') -Raw).Trim() -eq '1.3.3') 'Automatic rollback did not restore V1 Skill.'
    Assert-True ((Get-Content -LiteralPath $agentsPath -Raw).Contains('V1 rollback fixture')) 'Automatic rollback did not restore the V1 AGENTS block.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $runtimeRoot 'thread-registry.json') -Raw) -eq $legacyRegistry) 'Automatic rollback did not restore the V1 Registry.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot 'v2-state.json'))) 'Failed install left active V2 state.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot 'workstream-registry.json'))) 'Failed install left active V2 Registry.'

    Write-Output 'V2_INSTALL_ROLLBACK_PASS'
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ((Test-Path -LiteralPath $resolvedTemporaryRoot) -and $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
