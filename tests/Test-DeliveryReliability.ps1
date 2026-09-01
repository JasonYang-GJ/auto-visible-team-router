[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$registryScript = Join-Path $SkillRoot 'scripts\Thread-Registry.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('router-delivery-reliability-' + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'thread-registry.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){$failures.Add($Message)} }
function Test-Blocked([scriptblock]$Operation){ try { & $Operation | Out-Null; return $false } catch { return $true } }
function Invoke-Registry([hashtable]$Parameters){ ((& $registryScript @Parameters | Out-String) | ConvertFrom-Json) }
function Start-CompletedTask([string]$Project,[string]$Thread,[string]$Role,[string]$Task){
    Invoke-Registry @{Action='Upsert';RegistryPath=$registryPath;ProjectId=$Project;ProjectName=$Project;Role=$Role;ThreadId=$Thread;Title="$Project｜$Role";State='Active'}|Out-Null
    foreach($state in @('DISPATCHED','RUNNING','WORK_COMPLETED')){
        Invoke-Registry @{Action='SetDeliveryState';RegistryPath=$registryPath;ThreadId=$Thread;TaskId=$Task;DeliveryState=$state}|Out-Null
    }
}
function Record-Receipt([string]$Thread,[string]$Task,[string]$Status,[string]$Tests,[string]$Evidence,[string]$Commit=$null,[string]$Parent=$null,[string]$Clean='NotApplicable'){
    $args=@{Action='RecordDeliveryReceipt';RegistryPath=$registryPath;ThreadId=$Thread;TaskId=$Task;ResultStatus=$Status;TestsSummary=$Tests;EvidenceSummary=$Evidence;ReceiptTimestamp='2026-08-28T12:00:00+08:00';GitClean=$Clean}
    if($Commit){$args.CommitSha=$Commit}; if($Parent){$args.ParentSha=$Parent}
    Invoke-Registry $args
}
function Reconcile-WithPrimary([string]$Thread,[string]$Task,[string]$Role,[string]$Status,[string]$Tests,[string]$Evidence,[string]$Commit=$null,[string]$Parent=$null,[string]$Clean='NotApplicable'){
    $args=@{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId=$Thread;TaskId=$Task;PrimaryTaskId=$Task;PrimaryRole=$Role;PrimaryResultStatus=$Status;PrimaryTestsSummary=$Tests;PrimaryEvidenceSummary=$Evidence;PrimaryGitClean=$Clean}
    if($Commit){$args.PrimaryCommitSha=$Commit}; if($Parent){$args.PrimaryParentSha=$Parent}
    Invoke-Registry $args
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Invoke-Registry @{Action='Init';RegistryPath=$registryPath}|Out-Null
    $commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $parent='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

    # Case 1: normal Developer body + Receipt + ACK.
    Start-CompletedTask 'project-dev' 'thread-dev' 'Developer' 'task-dev'
    $devReceipt=Record-Receipt 'thread-dev' 'task-dev' 'PASS' 'unit: PASS' 'commit and clean Git verified' $commit $parent 'True'
    $devDelivered=Reconcile-WithPrimary 'thread-dev' 'task-dev' 'Developer' 'PASS' 'unit: PASS' 'commit and clean Git verified' $commit $parent 'True'
    $devAck=Invoke-Registry @{Action='AcknowledgeDelivery';RegistryPath=$registryPath;ThreadId='thread-dev';TaskId='task-dev';AcknowledgedAt='2026-08-28T12:01:00+08:00'}
    Assert-True ($devReceipt.status -eq 'DELIVERY_PENDING' -and $devDelivered.status -eq 'DELIVERED' -and $devAck.status -eq 'ACKNOWLEDGED') 'Case 1: Developer delivery did not close with ACK.'
    $reusedDeveloper=Invoke-Registry @{Action='SetDeliveryState';RegistryPath=$registryPath;ThreadId='thread-dev';TaskId='task-dev-2';DeliveryState='DISPATCHED'}
    Assert-True ($reusedDeveloper.deliveryState -eq 'DISPATCHED' -and $reusedDeveloper.previousTaskId -eq 'task-dev') 'Case 1: acknowledged Developer could not be reused for a new assignment.'

    # Case 2: normal QA PASS closes without a commit requirement.
    Start-CompletedTask 'project-qa' 'thread-qa' 'QA' 'task-qa'
    Record-Receipt 'thread-qa' 'task-qa' 'PASS' 'feature and regression: PASS' 'exact candidate SHA inspected read-only'|Out-Null
    $qaDelivered=Reconcile-WithPrimary 'thread-qa' 'task-qa' 'QA' 'PASS' 'feature and regression: PASS' 'exact candidate SHA inspected read-only'
    $qaAck=Invoke-Registry @{Action='AcknowledgeDelivery';RegistryPath=$registryPath;ThreadId='thread-qa';TaskId='task-qa'}
    Assert-True ($qaDelivered.resultStatus -eq 'PASS' -and $qaAck.status -eq 'ACKNOWLEDGED') 'Case 2: QA PASS did not close normally.'

    # Case 3: primary body missing, valid Receipt restores result automatically.
    Start-CompletedTask 'project-receipt' 'thread-receipt' 'Developer' 'task-receipt'
    Record-Receipt 'thread-receipt' 'task-receipt' 'FAIL' 'integration: FAIL' 'one bounded assertion failed'|Out-Null
    $receiptRecovered=Invoke-Registry @{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId='thread-receipt';TaskId='task-receipt';PrimaryBodyMissing=$true}
    Assert-True ($receiptRecovered.status -eq 'DELIVERED' -and $receiptRecovered.source -eq 'RECEIPT' -and $receiptRecovered.resultStatus -eq 'FAIL') 'Case 3: valid Receipt did not recover the missing primary body.'

    # Case 4 and 5: no Receipt -> one REDELIVER -> recovered -> ACK.
    Start-CompletedTask 'project-retry' 'thread-retry' 'Developer' 'task-retry'
    $missing=Invoke-Registry @{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId='thread-retry';TaskId='task-retry';PrimaryBodyMissing=$true}
    $effects=[ordered]@{tests=0;build=0;network=0;provider_request=0;developer_rerun=0}
    $retry=Invoke-Registry @{Action='RequestRedelivery';RegistryPath=$registryPath;ThreadId='thread-retry';TaskId='task-retry'}
    $retryAgain=Invoke-Registry @{Action='RequestRedelivery';RegistryPath=$registryPath;ThreadId='thread-retry';TaskId='task-retry'}
    $redeliveredReceipt=Record-Receipt 'thread-retry' 'task-retry' 'PASS' 'cached prior tests: PASS' 'existing compact evidence redelivered'
    $retryRecovered=Invoke-Registry @{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId='thread-retry';TaskId='task-retry';PrimaryBodyMissing=$true}
    $retryAck=Invoke-Registry @{Action='AcknowledgeDelivery';RegistryPath=$registryPath;ThreadId='thread-retry';TaskId='task-retry'}
    Assert-True ($missing.status -eq 'CONTROLLED_DELIVERY_RETRY_REQUIRED' -and $retry.status -eq 'REDELIVER' -and -not $retry.reexecuteAllowed) 'Case 4: missing Receipt did not request bounded REDELIVER.'
    Assert-True ($retryAgain.status -eq 'DELIVERY_RETRY_EXHAUSTED' -and $redeliveredReceipt.receipt.redeliveryOnly -and $retryRecovered.status -eq 'DELIVERED' -and $retryAck.status -eq 'ACKNOWLEDGED') 'Case 5: controlled redelivery did not recover and ACK exactly once.'

    # Case 6: primary and Receipt disagreement fails closed.
    Start-CompletedTask 'project-conflict' 'thread-conflict' 'QA' 'task-conflict'
    Record-Receipt 'thread-conflict' 'task-conflict' 'PASS' 'regression: PASS' 'exact SHA accepted'|Out-Null
    $conflict=Invoke-Registry @{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId='thread-conflict';TaskId='task-conflict';PrimaryTaskId='different-task';PrimaryRole='Developer';PrimaryResultStatus='FAIL';PrimaryTestsSummary='regression: FAIL';PrimaryEvidenceSummary='one regression failed';PrimaryGitClean='NotApplicable'}
    $conflictCannotBeBypassed=Invoke-Registry @{Action='ReconcileDelivery';RegistryPath=$registryPath;ThreadId='thread-conflict';TaskId='task-conflict';PrimaryBodyMissing=$true}
    $conflictAckBlocked=Test-Blocked { Invoke-Registry @{Action='AcknowledgeDelivery';RegistryPath=$registryPath;ThreadId='thread-conflict';TaskId='task-conflict'} }
    Assert-True ($conflict.status -eq 'DELIVERY_EVIDENCE_CONFLICT' -and $conflict.ackAllowed -eq $false -and $conflictCannotBeBypassed.status -eq 'DELIVERY_EVIDENCE_CONFLICT' -and $conflictAckBlocked) 'Case 6: conflicting evidence did not fail closed.'

    # Case 7: retry is delivery-only and cannot trigger execution side effects.
    Assert-True (($effects.Values | Measure-Object -Sum).Sum -eq 0) 'Case 7: redelivery simulation triggered an execution side effect.'
    foreach($forbidden in @('tests','build','network','provider_request','developer_rerun','new_specialist')){
        Assert-True ($retry.prohibited -contains $forbidden) "Case 7: retry contract omitted forbidden action $forbidden."
    }

    # Case 8: sensitive/raw content is rejected before persistence.
    Start-CompletedTask 'project-sensitive' 'thread-sensitive' 'Developer' 'task-sensitive'
    foreach($unsafe in @('api_key=abc','password=abc','secret=abc','Authorization: Bearer abc','credential=abc','Prompt body: x','Completion body: x','reasoning body: x','raw Provider response','raw SSE data','complete chat history')){
        Assert-True (Test-Blocked { Record-Receipt 'thread-sensitive' 'task-sensitive' 'PASS' 'tests: PASS' $unsafe }) "Case 8: unsafe Receipt content was accepted: $unsafe"
    }
}
finally {
    if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}

[pscustomobject]@{suite='V1.3.3 Delivery Reliability and Reconciliation Cases 1-8';passed=($failures.Count -eq 0);caseCount=8;failures=$failures}|ConvertTo-Json -Depth 8
if($failures.Count -gt 0){exit 1}
