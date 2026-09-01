[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

$skillText = Get-Content -LiteralPath (Join-Path $SkillRoot 'SKILL.md') -Raw
$moduleText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\module-governance.md') -Raw
$moduleNormalized = ($moduleText -replace '\s+', ' ')
$deliveryText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\visible-thread-delivery-recovery.md') -Raw
$reliabilityText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\delivery-reliability.md') -Raw
$contextText = Get-Content -LiteralPath (Join-Path $SkillRoot 'references\context-delegation.md') -Raw
$managerText = Get-Content -LiteralPath (Join-Path $SkillRoot 'scripts\Manage-Global.ps1') -Raw
$yamlText = Get-Content -LiteralPath (Join-Path $SkillRoot 'agents\openai.yaml') -Raw

$skillLines = @($skillText -split "`r?`n").Count
$moduleLines = @($moduleText -split "`r?`n").Count
$deliveryLines = @($deliveryText -split "`r?`n").Count
$reliabilityLines = @($reliabilityText -split "`r?`n").Count
$managedMatch = [regex]::Match($managerText, '(?s)\$managedBody\s*=\s*@''\r?\n(.*?)\r?\n''@')
$managedChars = if ($managedMatch.Success) { $managedMatch.Groups[1].Value.Length } else { [int]::MaxValue }

Assert-True ($skillLines -lt 500) "SKILL.md is too large for progressive disclosure: $skillLines lines."
Assert-True ($moduleLines -lt 250) "Module reference is unexpectedly large: $moduleLines lines."
Assert-True ($moduleText.Contains('## Contents')) 'The long module reference needs a compact contents map.'
Assert-True ($deliveryLines -lt 250) "Delivery-recovery reference is unexpectedly large: $deliveryLines lines."
Assert-True ($deliveryText.Contains('## Contents')) 'The delivery-recovery reference needs a compact contents map.'
Assert-True ($reliabilityLines -lt 250) "Delivery-reliability reference is unexpectedly large: $reliabilityLines lines."
Assert-True ($reliabilityText.Contains('## Contents')) 'The delivery-reliability reference needs a compact contents map.'
Assert-True ($managedMatch.Success) 'Managed AGENTS body could not be isolated.'
Assert-True ($managedChars -le 3500) "Always-loaded managed AGENTS body is too large: $managedChars characters."
Assert-True ($managerText.Contains('自动可视化团队路由器 V1.3.3')) 'Managed AGENTS entry is not V1.3.3.'

$frontmatter = [regex]::Match($skillText, '(?s)^---\r?\n(.*?)\r?\n---').Groups[1].Value
$frontmatterKeys = @([regex]::Matches($frontmatter, '(?m)^([a-zA-Z0-9_-]+):') | ForEach-Object { $_.Groups[1].Value })
Assert-True (($frontmatterKeys -join ',') -eq 'name,description') "SKILL frontmatter must contain only name and description: $($frontmatterKeys -join ',')"

foreach ($field in @('primary_module','affected_modules','module_owner','existing_capability_evidence','change_impact','architecture_gate','module_write_lease')) {
    $count = ([regex]::Matches($contextText, [regex]::Escape($field))).Count
    Assert-True ($count -eq 1) "Delegation field must have one canonical definition: $field count=$count"
    Assert-True (-not $moduleText.Contains($field)) "Module reference duplicates the canonical Packet field: $field"
}

Assert-True ($skillText.Contains('medium-or-larger change')) 'Conditional module-reference loading is missing.'
Assert-True ($moduleNormalized.Contains('Normal feature work must not repeat the adoption scan')) 'Normal work is not protected from repeat adoption scans.'
Assert-True ($moduleNormalized.Contains('Start from the primary module and direct dependencies')) 'Existing Capability Check lacks a bounded starting scope.'
Assert-True ($moduleNormalized.Contains('A module is a responsibility boundary') -and $moduleNormalized.Contains('does not justify a new Thread')) 'Module-to-Thread anti-duplication rule is missing.'
Assert-True ($managerText.Contains('禁止让多个角色重复全库扫描或重复发送完整历史')) 'Always-loaded routing contract lacks the duplicate-context guard.'
Assert-True ($skillText -notmatch '(?i)save\s+\d+%|节省\s*\d+%') 'Skill promises an unmeasured Token-saving percentage.'
Assert-True ($yamlText -match '(?m)^\s+default_prompt:\s+"使用 \$auto-visible-team-router') 'Default prompt does not explicitly invoke the Skill.'

[pscustomobject]@{
    suite = 'V1.3.3 progressive disclosure and duplicate-context guard'
    passed = ($failures.Count -eq 0)
    metrics = [pscustomobject]@{
        skillLines = $skillLines
        moduleReferenceLines = $moduleLines
        deliveryRecoveryReferenceLines = $deliveryLines
        deliveryReliabilityReferenceLines = $reliabilityLines
        managedAgentsCharacters = $managedChars
    }
    failures = $failures
} | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) { exit 1 }
