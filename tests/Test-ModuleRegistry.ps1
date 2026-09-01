[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$moduleScript = Join-Path $SkillRoot 'scripts\Module-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('router-module-registry-' + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'module-registry.json'
$failures = [System.Collections.Generic.List[string]]::new()
$project = @{ ProjectId='project-yuanshu'; ProjectName='元枢'; ProjectPath='C:\safe\yuanshu' }
$base = '1111111111111111111111111111111111111111'

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }
function Invoke-ModuleRegistry([hashtable]$Parameters) { (((& $moduleScript @Parameters) | Out-String) | ConvertFrom-Json) }
function Test-Blocked([scriptblock]$Operation) { try { & $Operation | Out-Null; return $false } catch { return $true } }

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    $status = Invoke-ModuleRegistry @{ Action='Status'; RegistryPath=$registryPath }
    Assert-True (-not $status.exists -and -not (Test-Path -LiteralPath $registryPath)) 'Status must not create Shadow state.'

    $preview = Invoke-ModuleRegistry (@{ Action='PreviewModule'; RegistryPath=$registryPath; ModuleId='Voice'; ModuleName='Voice'; Responsibilities=@('VAD'); Paths=@('src/Voice'); Confidence='Inferred'; Sources=@('src/Voice/VoiceService.cs') } + $project)
    Assert-True ($preview.mode -eq 'Shadow' -and -not $preview.persisted -and -not (Test-Path -LiteralPath $registryPath)) 'Preview must stay non-persistent.'

    $missingAuthorization = Test-Blocked { Invoke-ModuleRegistry (@{ Action='SetProjectMode'; RegistryPath=$registryPath; Mode='Active' } + $project) }
    Assert-True $missingAuthorization 'Active mode accepted a command without authorization evidence.'
    $wrongProjectAuthorization = Test-Blocked {
        Invoke-ModuleRegistry (@{ Action='SetProjectMode'; RegistryPath=$registryPath; Mode='Active'; AuthorizedAt='2026-08-26T10:00:00+08:00'; AuthorizationEvidence='user approved exact project'; AuthorizedProjectKey='id:other-project'; AuthorizationBaselineCommit=$base } + $project)
    }
    Assert-True $wrongProjectAuthorization 'Active authorization leaked across project identity.'

    $mode = Invoke-ModuleRegistry (@{
        Action='SetProjectMode'; RegistryPath=$registryPath; Mode='Active'
        AuthorizedAt='2026-08-26T10:00:00+08:00'; AuthorizationEvidence='user approved exact project-yuanshu'
        AuthorizedProjectKey='id:project-yuanshu'; AuthorizationBaselineCommit=$base
    } + $project)
    Assert-True ($mode.project.mode -eq 'Active' -and $mode.project.modeAuthorization.authorizedProjectKey -eq 'id:project-yuanshu') 'Exact Active authorization was not recorded.'

    $missingConfirmedFields = Test-Blocked {
        Invoke-ModuleRegistry @{ Action='UpsertModule'; RegistryPath=$registryPath; ProjectId='project-yuanshu'; ModuleId='Voice'; ModuleName='Voice'; Confidence='Confirmed'; Sources=@('src/Voice/VoiceService.cs'); VerifiedAt='2026-08-26T10:01:00+08:00'; VerifiedAgainstCommit=$base }
    }
    Assert-True $missingConfirmedFields 'Confirmed module accepted missing responsibility/path/owner/state fields.'

    $voice = Invoke-ModuleRegistry (@{
        Action='UpsertModule'; RegistryPath=$registryPath; ModuleId='Voice'; ModuleName='Voice'
        Responsibilities=@('Voice input','VAD','ASR'); Paths=@('src/Voice','src/Audio')
        OwnerRole='Voice'; OwnerThreadId='thread-voice'; Dependencies=@('Session'); Dependents=@('UI')
        ModuleState='ACTIVE'; Confidence='Confirmed'; Sources=@('src/Voice/VoiceService.cs','tests/VoiceTests.cs')
        VerifiedAt='2026-08-26T10:02:00+08:00'; VerifiedAgainstCommit=$base
    } + $project)
    Assert-True ($voice.created -and $voice.module.ownerRole -eq 'Voice') 'Confirmed module was not stored.'

    $patched = Invoke-ModuleRegistry @{ Action='UpsertModule'; RegistryPath=$registryPath; ProjectId='project-yuanshu'; ModuleId='Voice'; ModuleState='MIGRATING' }
    Assert-True ($patched.module.name -eq 'Voice' -and $patched.module.ownerRole -eq 'Voice') 'Patch-safe upsert erased authoritative fields.'
    Assert-True (($patched.module.dependencies -contains 'Session') -and ($patched.module.paths -contains 'src/Voice')) 'Patch-safe upsert lost arrays.'

    $ai = Invoke-ModuleRegistry (@{
        Action='UpsertModule'; RegistryPath=$registryPath; ModuleId='AI'; ModuleName='AI'
        Responsibilities=@('Intent'); Paths=@('src/AI'); OwnerRole='AI'; Dependencies=@(); Dependents=@()
        ModuleState='ACTIVE'; Confidence='Confirmed'; Sources=@('src/AI/Intent.cs')
        VerifiedAt='2026-08-26T10:03:00+08:00'; VerifiedAgainstCommit=$base
    } + $project)
    Assert-True ($ai.module.dependencies.Count -eq 0 -and $ai.module.dependents.Count -eq 0) 'Empty dependency fields were not preserved.'

    $leaseArgs = @{
        Action='AcquireLease'; RegistryPath=$registryPath; ProjectId='project-yuanshu'; ModuleId='Voice'
        WriterThreadId='thread-voice'; TaskId='task-voice-01'; PacketId='packet-voice-01'; PacketVersion=1
        Worktree='C:\safe\wt-voice'; Branch='codex/voice-stop'; AllowedPaths=@('src/Voice','tests/VoiceTests.cs')
        BaseCommit=$base; AcquiredAt='2026-08-26T10:10:00+08:00'; LastVerifiedAt='2026-08-26T10:10:00+08:00'
        VerificationEvidence='thread and git baseline verified'
    }
    $lease = Invoke-ModuleRegistry $leaseArgs
    Assert-True ($lease.lease.state -eq 'Active' -and $lease.lease.packetVersion -eq 1) 'Versioned Active lease was not stored.'
    $same = Invoke-ModuleRegistry $leaseArgs
    Assert-True ($same.reused -and $same.lease.id -eq $lease.lease.id) 'Exact lease request was not idempotent.'

    $changedScope = $leaseArgs.Clone(); $changedScope.AllowedPaths = @('src/Voice')
    Assert-True (Test-Blocked { Invoke-ModuleRegistry $changedScope }) 'Changed AllowedPaths incorrectly reused an Active lease.'
    $changedBaseline = $leaseArgs.Clone(); $changedBaseline.BaseCommit = '2222222222222222222222222222222222222222'
    Assert-True (Test-Blocked { Invoke-ModuleRegistry $changedBaseline }) 'Changed baseline incorrectly reused an Active lease.'

    $crossModuleConflict = Test-Blocked {
        Invoke-ModuleRegistry @{
            Action='AcquireLease'; RegistryPath=$registryPath; ProjectId='project-yuanshu'; ModuleId='AI'
            WriterThreadId='thread-ai'; TaskId='task-ai'; PacketId='packet-ai'; PacketVersion=1
            Worktree='C:\safe\wt-ai'; Branch='codex/ai-stop'; AllowedPaths=@('src/Voice/Bridge.cs'); BaseCommit=$base
        }
    }
    Assert-True $crossModuleConflict 'Cross-module parent/child path overlap was not blocked.'

    $downgradeBlocked = Test-Blocked { Invoke-ModuleRegistry (@{ Action='SetProjectMode'; RegistryPath=$registryPath; Mode='Shadow' } + $project) }
    Assert-True $downgradeBlocked 'Active-to-Shadow succeeded while an Active lease remained.'

    $released = Invoke-ModuleRegistry @{ Action='ReleaseLease'; RegistryPath=$registryPath; ProjectId='project-yuanshu'; LeaseId=$lease.lease.id; WriterThreadId='thread-voice'; ReleaseReason='safe checkpoint'; VerificationEvidence='exact thread and Git state verified' }
    Assert-True ($released.lease.state -eq 'Released') 'Exact writer could not release its lease.'
    $shadow = Invoke-ModuleRegistry (@{ Action='SetProjectMode'; RegistryPath=$registryPath; Mode='Shadow' } + $project)
    Assert-True ($shadow.project.mode -eq 'Shadow') 'Active-to-Shadow failed after all leases were released.'

    $document = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    Assert-True ($document.schemaVersion -eq 1 -and $document.projects[0].modules.Count -eq 2) 'Module Registry schema/data was lost.'
    Assert-True (Test-Path -LiteralPath ($registryPath + '.bak')) 'Previous known-good Module Registry backup is missing.'
    Assert-True ($document.PSObject.Properties.Name -notcontains 'entries') 'Module Registry must remain separate from Thread Registry.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{ suite='V1.3.1 Module Registry integrity'; passed=($failures.Count -eq 0); failures=$failures } | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) { exit 1 }
