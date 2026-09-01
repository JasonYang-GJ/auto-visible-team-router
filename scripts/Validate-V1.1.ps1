[CmdletBinding()]
param(
    [string]$SkillRoot,
    [string]$AgentsPath
)

# Backward-compatible entry point retained for V1.1 operator notes.
$validator = Join-Path $PSScriptRoot 'Validate-V1.1.1.ps1'
& $validator -SkillRoot $SkillRoot -AgentsPath $AgentsPath
exit $LASTEXITCODE
