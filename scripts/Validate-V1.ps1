[CmdletBinding()]
param(
    [string]$SkillRoot,
    [ValidateSet('Package','Installed')]
    [string]$Mode = 'Package',
    [string]$AgentsPath
)

# Backward-compatible V1 entry point targeting the current policy validator.
$validator = Join-Path $PSScriptRoot 'Validate-V1.3.3.ps1'
& $validator -SkillRoot $SkillRoot -Mode $Mode -AgentsPath $AgentsPath
exit $LASTEXITCODE
