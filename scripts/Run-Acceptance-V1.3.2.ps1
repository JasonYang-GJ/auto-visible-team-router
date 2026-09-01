[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('Package','Installed')]
    [string]$Mode = 'Package',
    [string]$AgentsPath,
    [string]$PythonPath,
    [string]$OfficialValidatorScript,
    [string]$HistoricalV131Root,
    [string]$HistoricalV12Root,
    [string]$HistoricalV111Root,
    [string]$RealAppEvidencePath
)

$ErrorActionPreference = 'Stop'
$SkillRoot = [System.IO.Path]::GetFullPath($SkillRoot)
$hostExe = (Get-Process -Id $PID).Path
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Category,[string]$Name,[string]$Status,[object]$Evidence) {
    $results.Add([pscustomobject]@{category=$Category;name=$Name;status=$Status;evidence=$Evidence})
}

function Invoke-PowerShellCheck([string]$Category,[string]$Name,[string]$Script,[string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $Script)) { Add-Result $Category $Name 'BLOCKED' "Missing script: $Script"; return }
    $output = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Add-Result $Category $Name $(if($code -eq 0){'PASS'}else{'FAIL'}) ([pscustomobject]@{exitCode=$code;output=$output.Trim()})
}

function Invoke-HistoricalCheck([string]$Name,[string]$Root,[string]$ValidatorName) {
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        Add-Result 'HistoricalSnapshot' $Name 'NOT_AVAILABLE' 'Frozen snapshot path was not supplied or does not exist.'
        return
    }
    $resolved = [System.IO.Path]::GetFullPath($Root)
    if ($resolved.Equals($SkillRoot,[System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Result 'HistoricalSnapshot' $Name 'FAIL' 'Historical validator refused the current V1.3.2 root.'
        return
    }
    $validator = Join-Path $resolved ('scripts\' + $ValidatorName)
    $manager = Join-Path $resolved 'scripts\Manage-Global.ps1'
    if (-not (Test-Path -LiteralPath $validator) -or -not (Test-Path -LiteralPath $manager)) {
        Add-Result 'HistoricalSnapshot' $Name 'NOT_AVAILABLE' 'Frozen snapshot lacks its validator or manager.'
        return
    }
    $tempProfile = Join-Path ([System.IO.Path]::GetTempPath()) ('router-historical-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tempProfile | Out-Null
        $installOutput = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $manager -Action Install -SourceRoot $resolved -UserProfileRoot $tempProfile 2>&1 | Out-String
        $installCode = $LASTEXITCODE
        if ($installCode -ne 0) {
            Add-Result 'HistoricalSnapshot' $Name 'FAIL' ([pscustomobject]@{stage='InstallFrozenSnapshot';exitCode=$installCode;output=$installOutput.Trim()})
            return
        }
        $agents = Join-Path $tempProfile '.codex\AGENTS.md'
        $validationOutput = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $validator -SkillRoot $resolved -AgentsPath $agents 2>&1 | Out-String
        $validationCode = $LASTEXITCODE
        Add-Result 'HistoricalSnapshot' $Name $(if($validationCode -eq 0){'PASS'}else{'FAIL'}) ([pscustomobject]@{snapshot=$resolved;exitCode=$validationCode;output=$validationOutput.Trim()})
    } finally {
        if (Test-Path -LiteralPath $tempProfile) { Remove-Item -LiteralPath $tempProfile -Recurse -Force }
    }
}

$staticArgs = @('-SkillRoot',$SkillRoot,'-Mode',$Mode)
if ($AgentsPath) { $staticArgs += @('-AgentsPath',[System.IO.Path]::GetFullPath($AgentsPath)) }
Invoke-PowerShellCheck 'Static' 'Current V1.3.2 validator' (Join-Path $SkillRoot 'scripts\Validate-V1.3.2.ps1') $staticArgs

if ($PythonPath -and $OfficialValidatorScript -and (Test-Path -LiteralPath $PythonPath) -and (Test-Path -LiteralPath $OfficialValidatorScript)) {
    $previousPythonUtf8 = $env:PYTHONUTF8
    try {
        $env:PYTHONUTF8 = '1'
        $officialOutput = & $PythonPath $OfficialValidatorScript $SkillRoot 2>&1 | Out-String
        $officialCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousPythonUtf8) { Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue }
        else { $env:PYTHONUTF8 = $previousPythonUtf8 }
    }
    Add-Result 'OfficialValidator' 'Official quick_validate' $(if($officialCode -eq 0){'PASS'}else{'FAIL'}) ([pscustomobject]@{exitCode=$officialCode;output=$officialOutput.Trim()})
} else {
    Add-Result 'OfficialValidator' 'Official quick_validate' 'BLOCKED' 'PythonPath and OfficialValidatorScript are required for official validation evidence.'
}

$behaviorTests = @(
    'Test-ThreadRegistry.ps1','Test-LifecycleRegistry.ps1','Test-ReadOnlyGuard.ps1',
    'Test-ManagementLifecycle.ps1','Test-RegistryScale.ps1','Test-ContextDelegation.ps1',
    'Test-ModuleRegistry.ps1','Test-ModuleGovernance.ps1','Test-TokenEfficiency.ps1',
    'Test-RegistryLockRecovery.ps1','Test-MigrationSafety.ps1',
    'Test-VisibleThreadDeliveryRecovery.ps1'
)
foreach($test in $behaviorTests){ Invoke-PowerShellCheck 'AutomatedBehavior' $test (Join-Path $SkillRoot ('tests\'+$test)) @('-SkillRoot',$SkillRoot) }
Invoke-PowerShellCheck 'RealTemporaryGit' 'Test-RealGitLifecycle.ps1' (Join-Path $SkillRoot 'tests\Test-RealGitLifecycle.ps1') @('-SkillRoot',$SkillRoot)

Invoke-HistoricalCheck 'V1.3.1 frozen validator' $HistoricalV131Root 'Validate-V1.3.1.ps1'
Invoke-HistoricalCheck 'V1.2.0 frozen validator' $HistoricalV12Root 'Validate-V1.2.ps1'
Invoke-HistoricalCheck 'V1.1.1 frozen validator' $HistoricalV111Root 'Validate-V1.1.1.ps1'

if ($RealAppEvidencePath -and (Test-Path -LiteralPath $RealAppEvidencePath)) {
    try {
        $appEvidence = Get-Content -LiteralPath $RealAppEvidencePath -Raw | ConvertFrom-Json
        $requiredFields = @('visibleThreadIds','adoptionEvidence','exactQaSha','integrationEvidence')
        $missing = @($requiredFields | Where-Object { $appEvidence.PSObject.Properties.Name -notcontains $_ -or $null -eq $appEvidence.$_ })
        Add-Result 'RealCodexApp' 'Visible Thread/Adoption/QA evidence' $(if($missing.Count -eq 0){'PASS'}else{'PENDING_REAL_EVIDENCE'}) ([pscustomobject]@{path=[System.IO.Path]::GetFullPath($RealAppEvidencePath);missing=$missing})
    } catch {
        Add-Result 'RealCodexApp' 'Visible Thread/Adoption/QA evidence' 'FAIL' $_.Exception.Message
    }
} else {
    Add-Result 'RealCodexApp' 'Visible Thread/Adoption/QA evidence' 'PENDING_REAL_EVIDENCE' 'No real-app evidence file was supplied; no visible task was created for this package-only upgrade.'
}

$blocking = @($results | Where-Object { $_.category -in @('Static','OfficialValidator','AutomatedBehavior','RealTemporaryGit') -and $_.status -ne 'PASS' })
$automatedPass = $blocking.Count -eq 0
$realAppPass = @($results | Where-Object { $_.category -eq 'RealCodexApp' -and $_.status -eq 'PASS' }).Count -eq 1
$overall = if (-not $automatedPass) { 'AUTOMATED_ACCEPTANCE_FAILED' } elseif ($realAppPass) { 'FULL_ACCEPTANCE_PASS' } else { 'AUTOMATED_ACCEPTANCE_PASS_REAL_APP_EVIDENCE_PENDING' }

[pscustomobject]@{
    suite='V1.3.2 acceptance truthfulness'; mode=$Mode; skillRoot=$SkillRoot; overall=$overall
    automatedAcceptancePassed=$automatedPass; fullAcceptancePassed=($automatedPass -and $realAppPass)
    counts=[pscustomobject]@{
        pass=@($results|Where-Object status -eq 'PASS').Count; fail=@($results|Where-Object status -eq 'FAIL').Count
        blocked=@($results|Where-Object status -eq 'BLOCKED').Count
        pendingRealEvidence=@($results|Where-Object status -eq 'PENDING_REAL_EVIDENCE').Count
        notAvailable=@($results|Where-Object status -eq 'NOT_AVAILABLE').Count
    }
    results=$results
} | ConvertTo-Json -Depth 12
if (-not $automatedPass) { exit 1 }
