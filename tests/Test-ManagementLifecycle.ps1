[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$manager = Join-Path $SkillRoot 'scripts\Manage-Global.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("router-management-test-" + [guid]::NewGuid().ToString('N'))
$fakeProfile = Join-Path $testRoot 'user'
$fakeCodex = Join-Path $fakeProfile '.codex'
$agentsPath = Join-Path $fakeCodex 'AGENTS.md'
$installedRoot = Join-Path $fakeProfile '.agents\skills\auto-visible-team-router'
$registryPath = Join-Path $fakeCodex 'auto-visible-team-router\thread-registry.json'
$moduleRegistryPath = Join-Path $fakeCodex 'auto-visible-team-router\module-registry.json'
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-JsonScript([string]$Script, [hashtable]$Parameters) {
    $raw = & $Script @Parameters | Out-String
    return ($raw | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $fakeCodex -Force | Out-Null
    $original = "# 用户原有全局规则`r`n`r`n- 不得覆盖。`r`n"
    [System.IO.File]::WriteAllText($agentsPath, $original, $utf8NoBom)

    $managerText = [System.IO.File]::ReadAllText($manager, $utf8NoBom)
    Assert-True ($managerText -match 'UserProfileRoot') 'Manager lacks an isolated user-profile seam.'
    if ($managerText -notmatch 'UserProfileRoot') { throw 'RED: isolated lifecycle seam is missing.' }

    $install1 = Invoke-JsonScript $manager @{ Action='Install'; SourceRoot=$SkillRoot; UserProfileRoot=$fakeProfile }
    Assert-True $install1.skill_installed 'Install did not place the skill.'
    Assert-True ($install1.managed_rule_version -eq '1.3.3') 'Install did not report V1.3.3.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installedRoot 'SKILL.md')) 'Installed SKILL.md is missing.'
    $afterInstall1 = [System.IO.File]::ReadAllText($agentsPath, $utf8NoBom)
    Assert-True $afterInstall1.StartsWith($original, [System.StringComparison]::Ordinal) 'Install changed original AGENTS bytes.'
    $hash1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $agentsPath).Hash

    $install2 = Invoke-JsonScript $manager @{ Action='Install'; SourceRoot=$SkillRoot; UserProfileRoot=$fakeProfile }
    $hash2 = (Get-FileHash -Algorithm SHA256 -LiteralPath $agentsPath).Hash
    Assert-True ($hash1 -eq $hash2) 'Repeat install changed AGENTS content.'
    Assert-True ($install2.begin_markers -eq 1 -and $install2.end_markers -eq 1) 'Repeat install duplicated markers.'

    $installedRegistry = Join-Path $installedRoot 'scripts\Thread-Registry.ps1'
    $registryInit = Invoke-JsonScript $installedRegistry @{ Action='Init' }
    Assert-True ($registryInit.schemaVersion -eq 2) 'Installed Registry script did not initialize schema 2.'
    Assert-True (Test-Path -LiteralPath $registryPath) 'Installed Registry script did not derive the real profile from its install path.'

    $installedModuleRegistry = Join-Path $installedRoot 'scripts\Module-Registry.ps1'
    $moduleStatus = Invoke-JsonScript $installedModuleRegistry @{ Action='Status' }
    Assert-True (-not $moduleStatus.exists) 'Install must not create Module Registry state in default Shadow mode.'
    $moduleInit = Invoke-JsonScript $installedModuleRegistry @{ Action='Init' }
    Assert-True ($moduleInit.schemaVersion -eq 1) 'Installed Module Registry script did not initialize separate schema 1.'
    Assert-True (Test-Path -LiteralPath $moduleRegistryPath) 'Installed Module Registry script did not derive the real profile from its install path.'

    $installedManager = Join-Path $installedRoot 'scripts\Manage-Global.ps1'
    $disabled = Invoke-JsonScript $installedManager @{ Action='Disable' }
    Assert-True (-not $disabled.managed_rule_enabled) 'Disable left the global rule enabled.'
    Assert-True (Test-Path -LiteralPath $installedRoot) 'Disable removed the skill files.'
    Assert-True $disabled.module_registry_retained 'Disable did not retain Module Registry state.'
    $disableManifest = Get-Content -LiteralPath (Join-Path $disabled.backup_dir 'manifest.json') -Raw | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace($disableManifest.registry_sha256)) 'Backup did not record Thread Registry SHA256.'
    Assert-True (-not [string]::IsNullOrWhiteSpace($disableManifest.module_registry_sha256)) 'Backup did not record Module Registry SHA256.'
    Assert-True (Test-Path -LiteralPath (Join-Path $disabled.backup_dir 'state\thread-registry.json')) 'Backup did not copy Thread Registry state.'
    Assert-True (Test-Path -LiteralPath (Join-Path $disabled.backup_dir 'state\module-registry.json')) 'Backup did not copy Module Registry state.'
    $afterDisable = [System.IO.File]::ReadAllText($agentsPath, $utf8NoBom)
    Assert-True ($afterDisable -ceq $original) 'Disable did not restore original AGENTS bytes exactly.'

    $enabled = Invoke-JsonScript $installedManager @{ Action='Enable' }
    Assert-True $enabled.managed_rule_enabled 'Enable did not restore the global rule.'
    $afterEnable = [System.IO.File]::ReadAllText($agentsPath, $utf8NoBom)
    Assert-True $afterEnable.StartsWith($original, [System.StringComparison]::Ordinal) 'Enable changed original AGENTS bytes.'

    $uninstalled = Invoke-JsonScript $installedManager @{ Action='Uninstall'; ConfirmUninstall=$true }
    Assert-True $uninstalled.skill_removed 'Uninstall did not remove the exact skill directory.'
    Assert-True (-not (Test-Path -LiteralPath $installedRoot)) 'Skill directory still exists after uninstall.'
    Assert-True (([System.IO.File]::ReadAllText($agentsPath, $utf8NoBom)) -ceq $original) 'Uninstall did not restore original AGENTS bytes.'
    Assert-True (Test-Path -LiteralPath $registryPath) 'Uninstall must retain the user Thread Registry.'
    Assert-True (Test-Path -LiteralPath $moduleRegistryPath) 'Uninstall must retain the user Module Registry.'
    Assert-True (Test-Path -LiteralPath $uninstalled.backup_dir) 'Uninstall backup is missing.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{
    suite = 'Global management lifecycle and byte preservation'
    passed = ($failures.Count -eq 0)
    failures = $failures
} | ConvertTo-Json -Depth 6
if ($failures.Count -gt 0) { exit 1 }
