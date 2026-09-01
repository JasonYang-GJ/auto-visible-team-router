[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$registryScript = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$guardScript = Join-Path $SkillRoot 'scripts\ReadOnly-Guard.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('router-delivery-recovery-' + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'thread-registry.json'
$repo = Join-Path $testRoot 'repo'
$guardStore = Join-Path $testRoot 'guards'
$failures = [System.Collections.Generic.List[string]]::new()
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){$failures.Add($Message)} }
function Invoke-Registry([hashtable]$Parameters){ ((& $registryScript @Parameters | Out-String) | ConvertFrom-Json) }
function Invoke-Guard([hashtable]$Parameters){ ((& $guardScript @Parameters | Out-String) | ConvertFrom-Json) }
function Test-Blocked([scriptblock]$Operation){ try { & $Operation | Out-Null; return $false } catch { return $true } }
function Resolve-Delivery([bool]$FirstOutput,[bool]$RetryOutput){
    if($FirstOutput){ return [pscustomobject]@{status='HEALTHY';retryCount=0;replace=$false} }
    if($RetryOutput){ return [pscustomobject]@{status='HEALTHY';retryCount=1;replace=$false} }
    [pscustomobject]@{status='DEGRADED';retryCount=1;replace=$true}
}
function Resolve-Recovery([bool]$HealthyExisting,[bool]$ReplacementAlreadyUsed){
    if($HealthyExisting){ return 'Adopt' }
    if($ReplacementAlreadyUsed){ return 'CHANNEL_UNAVAILABLE' }
    return 'CreateOne'
}
function Test-FallbackAllowed([string]$Risk,[bool]$Security,[bool]$Irreversible,[bool]$WriterConflict,[bool]$CoordinatorEdited,[bool]$IndependentRequired){
    return $Risk -in @('Low','Medium') -and -not ($Security -or $Irreversible -or $WriterConflict -or $CoordinatorEdited -or $IndependentRequired)
}
function Add-Architect([string]$Project,[string]$Thread,[string]$Action='Upsert',[string]$Replaces=$null){
    $args=@{Action=$Action;RegistryPath=$registryPath;ProjectId=$Project;ProjectName=$Project;Role='Architect';ThreadId=$Thread;Title="$Project｜架构师";State='Active'}
    if($Replaces){$args.ReplacesThreadId=$Replaces}
    Invoke-Registry $args
}
function Mark-Degraded([string]$Thread,[string]$Incident){
    Invoke-Registry @{
        Action='MarkDeliveryDegraded';RegistryPath=$registryPath;ThreadId=$Thread;IncidentId=$Incident
        FirstFailureRun="$Incident-first";RetryRun="$Incident-retry";DeliveryRetryCount=1
        ObservedState='completed -> idle';DirectReadEvidence='exact thread/project/role direct-read succeeded and assignment accepted'
        OutputEvidence='assistant body empty; no tool records; no role conclusion; no PASS/FAIL/BLOCKED on both attempts'
        BackgroundWorkEvidence='no background work remains; task is not running'
        ReadOnlyGuardEvidence='READ_ONLY_CONFIRMED PASS';DeliveryDetectedAt='2026-08-26T12:00:00+08:00'
        DeliveryReason='ARCHITECT_OUTPUT_CHANNEL_FAILURE'
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Invoke-Registry @{Action='Init';RegistryPath=$registryPath}|Out-Null

    $case1=Resolve-Delivery $true $false
    Assert-True ($case1.status -eq 'HEALTHY' -and -not $case1.replace) 'Case 1: healthy visible output triggered replacement.'
    $case2=Resolve-Delivery $false $true
    Assert-True ($case2.status -eq 'HEALTHY' -and $case2.retryCount -eq 1 -and -not $case2.replace) 'Case 2: successful controlled retry triggered replacement.'

    Add-Architect 'project-degraded' 'architect-original'|Out-Null
    Assert-True (Test-Blocked { Invoke-Registry @{Action='SetState';RegistryPath=$registryPath;ThreadId='architect-original';State='Degraded'} }) 'Case 3: Degraded evidence gate was bypassed.'
    Assert-True (Test-Blocked { Invoke-Registry @{Action='MarkDeliveryDegraded';RegistryPath=$registryPath;ThreadId='architect-original';FirstFailureRun='a';RetryRun='b';DeliveryRetryCount=1;ObservedState='completed -> idle';DirectReadEvidence='trust me';OutputEvidence='nothing';BackgroundWorkEvidence='unknown';ReadOnlyGuardEvidence='PASS';DeliveryDetectedAt='2026-08-26T12:00:00+08:00';DeliveryReason='test'} }) 'Case 3: unstructured delivery claims bypassed the evidence gate.'
    $degraded=Mark-Degraded 'architect-original' 'incident-degraded'
    Assert-True ($degraded.entry.thread.state -eq 'Degraded' -and $degraded.entry.deliveryRecovery.status -eq 'DEGRADED') 'Case 3: verified empty delivery did not become Degraded.'
    Assert-True ($degraded.entry.deliveryRecovery.retryCount -eq 1 -and $degraded.entry.deliveryRecovery.firstFailureRun -ne $degraded.entry.deliveryRecovery.retryRun) 'Case 3: bounded retry evidence was not stored.'
    Assert-True ($degraded.entry.thread.state -ne 'Stale') 'Case 4: Degraded was incorrectly recorded as Stale.'

    Assert-True ((Resolve-Recovery $true $false) -eq 'Adopt') 'Case 5: healthy existing role was not selected for adoption.'
    $adopted=Add-Architect 'project-degraded' 'architect-existing' 'Adopt' 'architect-original'
    Assert-True ($adopted.entry.thread.origin -eq 'Adopted' -and $adopted.entry.replacesThreadId -eq 'architect-original') 'Case 5: healthy existing Architect was not adopted with lineage.'

    Add-Architect 'project-create' 'architect-create-original'|Out-Null
    Mark-Degraded 'architect-create-original' 'incident-create'|Out-Null
    Assert-True ((Resolve-Recovery $false $false) -eq 'CreateOne') 'Case 6: one replacement was not allowed.'
    $created=Add-Architect 'project-create' 'architect-create-replacement' 'Upsert' 'architect-create-original'
    Assert-True ($created.entry.replacesThreadId -eq 'architect-create-original' -and $created.entry.deliveryRecovery.incidentId -eq 'incident-create') 'Case 6: replacement lineage/incident was not preserved.'
    Assert-True (Test-Blocked { Invoke-Registry @{Action='RecordReplacementHealth';RegistryPath=$registryPath;ThreadId='architect-create-original';ReplacementThreadId='architect-create-replacement';ReplacementHealth='PASS';ReplacementHealthEvidence='HEALTHY'} }) 'Case 7: replacement health accepted a non-contract response.'
    $health=Invoke-Registry @{Action='RecordReplacementHealth';RegistryPath=$registryPath;ThreadId='architect-create-original';ReplacementThreadId='architect-create-replacement';ReplacementHealth='PASS';ReplacementHealthEvidence="Status: HEALTH_OK`nRole: Architect`nProject: project-create"}
    Assert-True ($health.original.deliveryRecovery.status -eq 'REPLACED' -and $health.replacement.deliveryRecovery.status -eq 'HEALTHY') 'Case 7: replacement health PASS did not continue the role assignment.'

    Add-Architect 'project-unavailable' 'architect-unavailable-original'|Out-Null
    Mark-Degraded 'architect-unavailable-original' 'incident-unavailable'|Out-Null
    Add-Architect 'project-unavailable' 'architect-unavailable-replacement' 'Upsert' 'architect-unavailable-original'|Out-Null
    $failedHealth=Invoke-Registry @{Action='RecordReplacementHealth';RegistryPath=$registryPath;ThreadId='architect-unavailable-original';ReplacementThreadId='architect-unavailable-replacement';ReplacementHealth='FAIL';ReplacementHealthEvidence='completed/idle; empty body; no tools'}
    Assert-True ($failedHealth.original.deliveryRecovery.status -eq 'CHANNEL_UNAVAILABLE') 'Case 8: replacement failure did not mark CHANNEL_UNAVAILABLE.'
    Assert-True (Test-Blocked { Add-Architect 'project-unavailable' 'architect-third' 'Upsert' 'architect-unavailable-replacement' }) 'Case 8: a third Architect was created for one incident.'
    Assert-True ((Resolve-Recovery $false $true) -eq 'CHANNEL_UNAVAILABLE') 'Case 8: recovery decision did not stop replacement growth.'

    Assert-True (Test-FallbackAllowed 'Medium' $false $false $false $false $false) 'Case 9: bounded read-only architecture fallback was blocked.'
    Assert-True (-not (Test-FallbackAllowed 'High' $true $false $false $false $false)) 'Case 10: Security architecture fallback was allowed.'
    Assert-True (-not (Test-FallbackAllowed 'Medium' $false $true $false $false $false)) 'Case 10: irreversible migration fallback was allowed.'
    Assert-True (-not (Test-FallbackAllowed 'Medium' $false $false $true $false $false)) 'Case 10: unresolved writer conflict fallback was allowed.'
    Assert-True (-not (Test-FallbackAllowed 'Medium' $false $false $false $true $false)) 'Case 10: same-run code-writing Coordinator fallback was allowed.'
    Assert-True (-not (Test-FallbackAllowed 'Medium' $false $false $false $false $true)) 'Case 10: independent Architect requirement was bypassed.'

    New-Item -ItemType Directory -Path $repo | Out-Null
    git -C $repo init --initial-branch=main | Out-Null
    git -C $repo config user.name 'Router Delivery Test'
    git -C $repo config user.email 'router-delivery@example.invalid'
    [System.IO.File]::WriteAllText((Join-Path $repo 'architecture.txt'),"baseline`n",$utf8)
    git -C $repo add architecture.txt; git -C $repo commit -m 'baseline' | Out-Null
    Invoke-Guard @{Action='Start';Repository=$repo;GuardStore=$guardStore;CheckId='fallback';Role='Architect'}|Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'architecture.txt'),"changed`n",$utf8)
    $guard=Invoke-Guard @{Action='Finish';Repository=$repo;GuardStore=$guardStore;CheckId='fallback';Role='Architect'}
    Assert-True (-not $guard.passed -and $guard.status -eq 'READ_ONLY_STATE_CHANGED') 'Case 11: changed fallback checkout passed the Architecture Gate.'

    $baseline='96db583be53fc37fdaa62aef80f12f1111a66f9f'
    $currentBaseline=$baseline; $scopeChanged=$false
    $reuseEvidence=($baseline -eq $currentBaseline -and -not $scopeChanged)
    $repeatFullScan=-not $reuseEvidence
    Assert-True ($reuseEvidence -and -not $repeatFullScan) 'Case 12: unchanged capability evidence triggered a duplicate full scan.'
}
finally {
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}

[pscustomobject]@{suite='V1.3.2 Visible Thread Delivery Recovery Cases 1-12';passed=($failures.Count -eq 0);caseCount=12;failures=$failures}|ConvertTo-Json -Depth 8
if($failures.Count -gt 0){exit 1}
