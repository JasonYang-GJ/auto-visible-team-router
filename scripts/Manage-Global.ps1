[CmdletBinding()]
param(
    [ValidateSet('Install','Status','Disable','Enable','Uninstall')]
    [string]$Action = 'Status',
    [string]$SourceRoot,
    [string]$UserProfileRoot,
    [switch]$ConfirmUninstall
)

$ErrorActionPreference = 'Stop'
if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PSScriptRoot }
$scriptSkillRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$installedSuffix = [System.IO.Path]::Combine('.agents', 'skills', 'auto-visible-team-router')
if ($UserProfileRoot) {
    $routerUserProfile = [System.IO.Path]::GetFullPath($UserProfileRoot)
} elseif ($scriptSkillRoot.EndsWith($installedSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $routerUserProfile = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptSkillRoot))
} else {
    $routerUserProfile = [Environment]::GetFolderPath('UserProfile')
}
$routerCodexHome = if ($env:CODEX_HOME -and -not $UserProfileRoot) {
    [System.IO.Path]::GetFullPath($env:CODEX_HOME)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $routerUserProfile '.codex'))
}
$routerSkillRoot = [System.IO.Path]::GetFullPath((Join-Path $routerUserProfile '.agents\skills\auto-visible-team-router'))
$routerAgentsPath = Join-Path $routerCodexHome 'AGENTS.md'
$routerBackupBase = Join-Path $routerCodexHome 'backups\auto-visible-team-router'
$routerRegistryPath = Join-Path $routerCodexHome 'auto-visible-team-router\thread-registry.json'
$routerModuleRegistryPath = Join-Path $routerCodexHome 'auto-visible-team-router\module-registry.json'
$beginPattern = '<!-- BEGIN auto-visible-team-router:v1(?: separatorChars=(\d+))? -->'
$end = '<!-- END auto-visible-team-router:v1 -->'
$routerUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

$managedBody = @'
## 自动可视化团队路由器 V1.3.3

- 仅对真实软件项目启用 `$auto-visible-team-router`；普通聊天和明显简单的小改动留在当前任务，并始终选择最小必要团队。
- Level 0 是硬性快速路径：不查找/接管/创建专业任务，不建 Worktree、Lease、Packet 或 Module Registry，不做全库扫描；Level 1 默认一个实现者，QA 仅按风险加入。
- Thread、Worktree、Git Branch 与 Module 是四种不同对象。真实文件、Git、测试和 Thread API 是事实真源；两个 Registry 只是索引。
- 先复用：核验 Thread Registry 与真实任务，Team Adoption 接管已有角色；模块不等于任务，不得因模块数量创建同等数量的可见任务，后台 subagent 不得冒充可见角色。
- `completed/idle` 不等于角色交付成功。先精确读取 Thread 并对账现有 Registry 中的精简 Delivery Receipt，结果一致后才 ACK；缺失时只允许一次 `REDELIVER`，不得重新开发/测试/build/联网。冲突必须 `DELIVERY_EVIDENCE_CONFLICT`；仍失败才进入原 Degraded/单次替换/安全 fallback，且保留人工可见任务交接。
- 对现有项目的中等以上改动先做一次有界 Existing Capability Check。Module Registry 独立于 Thread Registry，默认 Shadow；Active 必须记录精确项目、时间、依据和基线，且 Active Lease 未清零时不得退回 Shadow。
- Coordinator 只发送一个版本化 Delegation Packet；模块、影响范围、已有能力、Owner、架构门禁和写入租约并入同一 Packet。日常从 Scope 1 和直接依赖开始，禁止让多个角色重复全库扫描或重复发送完整历史。
- 每个核心模块默认一个主要写代码角色；Lease 仅在模块、写入者、Packet 版本、Worktree、Branch、Base Commit 和允许路径完全一致时复用，跨模块路径重叠也必须阻止。租约过期不代表可自动接管。
- 只有两个以上写代码 Agent 确需并行且范围隔离时才新建 Worktree；每项目 Budget 默认 3。优先复用既有合理 Branch/空闲 Worktree，禁止删除未知对象腾位置。
- QA 验证准确 SHA，区分 Feature 与 Regression；失败返回原 Owner 产生新 SHA。需要架构门禁时，QA PASS 与 Architecture Consistency PASS 后才能集成。
- Router 升级、接管或模式切换不得打断进行中的 Developer/QA；先到安全检查点并保留原 Thread、Worktree、Branch 与 Packet。Coordinator 默认是 Integration Owner，除非明确登记替代负责人。
- 只读守卫必须在空闲的同一检出目录和准确 SHA 上运行；发现变化时报告 `READ_ONLY_STATE_CHANGED` 并关闭放行，但不能在存在并发写入者时直接归咎 QA/Architect。
- 不自动切换模型或推理强度，不改变权限，不自动 Push、发布、部署、重构真实项目或删除 Legacy。Git 清理仍只限已证明由 Router 创建且全部门禁通过的本地临时对象。
- 最终只报告实际复用/创建、模块与 Owner、Thread/Worktree/Branch/Commit、Scope 升级、重复扫描理由、QA/架构/回归和未验证项；不承诺未经测量的 Token 节省比例。
'@

function Get-AgentsBytes {
    if (Test-Path -LiteralPath $routerAgentsPath) { return [System.IO.File]::ReadAllBytes($routerAgentsPath) }
    return [byte[]]@()
}

function Get-AgentsText {
    $bytes = Get-AgentsBytes
    if ($bytes.Length -eq 0) { return '' }
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    return $routerUtf8NoBom.GetString($bytes, $offset, $bytes.Length - $offset)
}

function Write-AgentsText([string]$Text) {
    New-Item -ItemType Directory -Force -Path $routerCodexHome | Out-Null
    $oldBytes = Get-AgentsBytes
    $hadBom = $oldBytes.Length -ge 3 -and $oldBytes[0] -eq 0xEF -and $oldBytes[1] -eq 0xBB -and $oldBytes[2] -eq 0xBF
    $payload = $routerUtf8NoBom.GetBytes($Text)
    if ($hadBom) {
        $next = New-Object byte[] ($payload.Length + 3)
        $next[0] = 0xEF; $next[1] = 0xBB; $next[2] = 0xBF
        [Array]::Copy($payload, 0, $next, 3, $payload.Length)
        [System.IO.File]::WriteAllBytes($routerAgentsPath, $next)
    } else {
        [System.IO.File]::WriteAllBytes($routerAgentsPath, $payload)
    }
}

function Get-MarkerState([string]$Text) {
    $begins = [regex]::Matches($Text, $beginPattern)
    $ends = [regex]::Matches($Text, [regex]::Escape($end))
    [pscustomobject]@{ begins = $begins; ends = $ends }
}

function Get-ManagedBlock([int]$SeparatorChars, [string]$Newline) {
    $begin = "<!-- BEGIN auto-visible-team-router:v1 separatorChars=$SeparatorChars -->"
    return $begin + $Newline + (($managedBody.Trim()) -replace "`r?`n", $Newline) + $Newline + $end
}

function New-Backup([string]$Reason) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupDir = Join-Path $routerBackupBase $stamp
    if (Test-Path -LiteralPath $backupDir) { throw "Backup already exists: $backupDir" }
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    if (Test-Path -LiteralPath $routerAgentsPath) {
        Copy-Item -LiteralPath $routerAgentsPath -Destination (Join-Path $backupDir 'AGENTS.md')
    }
    if (Test-Path -LiteralPath $routerSkillRoot) {
        Copy-Item -LiteralPath $routerSkillRoot -Destination (Join-Path $backupDir 'skill') -Recurse
    }
    $stateDir = Join-Path $backupDir 'state'
    $threadRegistryHash = $null
    $moduleRegistryHash = $null
    if (Test-Path -LiteralPath $routerRegistryPath) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Copy-Item -LiteralPath $routerRegistryPath -Destination (Join-Path $stateDir 'thread-registry.json')
        $threadRegistryHash = (Get-FileHash -LiteralPath $routerRegistryPath -Algorithm SHA256).Hash
    }
    if (Test-Path -LiteralPath $routerModuleRegistryPath) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Copy-Item -LiteralPath $routerModuleRegistryPath -Destination (Join-Path $stateDir 'module-registry.json')
        $moduleRegistryHash = (Get-FileHash -LiteralPath $routerModuleRegistryPath -Algorithm SHA256).Hash
    }
    $manifest = [pscustomobject]@{
        reason = $Reason
        created_at = (Get-Date).ToString('o')
        agents_existed = (Test-Path -LiteralPath $routerAgentsPath)
        skill_existed = (Test-Path -LiteralPath $routerSkillRoot)
        skill_root = $routerSkillRoot
        registry_path = $routerRegistryPath
        registry_sha256 = $threadRegistryHash
        module_registry_path = $routerModuleRegistryPath
        module_registry_sha256 = $moduleRegistryHash
        registry_retained = $true
        module_registry_retained = $true
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $backupDir 'manifest.json'), $manifest + [Environment]::NewLine, $routerUtf8NoBom)
    return $backupDir
}

function Set-ManagedBlock([bool]$Enabled) {
    New-Item -ItemType Directory -Force -Path $routerCodexHome | Out-Null
    $current = Get-AgentsText
    $markers = Get-MarkerState $current
    if ($markers.begins.Count -ne $markers.ends.Count -or $markers.begins.Count -gt 1) {
        throw "Refusing to edit AGENTS.md with invalid managed markers: begin=$($markers.begins.Count) end=$($markers.ends.Count)"
    }
    $newline = if ($current.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($Enabled) {
        if ($markers.begins.Count -eq 1) {
            $beginMatch = $markers.begins[0]
            $endMatch = $markers.ends[0]
            if ($endMatch.Index -lt $beginMatch.Index) { throw 'Managed marker order is invalid.' }
            $separatorChars = if ($beginMatch.Groups[1].Success) { [int]$beginMatch.Groups[1].Value } else { 0 }
            $after = $endMatch.Index + $endMatch.Length
            $next = $current.Substring(0, $beginMatch.Index) + (Get-ManagedBlock $separatorChars $newline) + $current.Substring($after)
            if ($next -cne $current) { Write-AgentsText $next }
            return
        }
        $separator = if ([string]::IsNullOrEmpty($current) -or $current.EndsWith($newline + $newline)) {
            ''
        } elseif ($current.EndsWith($newline)) {
            $newline
        } else {
            $newline + $newline
        }
        $block = Get-ManagedBlock $separator.Length $newline
        Write-AgentsText ($current + $separator + $block + $newline)
        return
    }

    if ($markers.begins.Count -eq 0) { return }
    $beginMatch = $markers.begins[0]
    $endMatch = $markers.ends[0]
    if ($endMatch.Index -lt $beginMatch.Index) { throw 'Managed marker order is invalid.' }
    $after = $endMatch.Index + $endMatch.Length
    if ($after -lt $current.Length -and $current.Substring($after).Trim().Length -gt 0) {
        throw 'Refusing to remove a managed block that is not the final non-whitespace content.'
    }
    $separatorChars = if ($beginMatch.Groups[1].Success) { [int]$beginMatch.Groups[1].Value } else { 0 }
    $prefixEnd = $beginMatch.Index - $separatorChars
    if ($prefixEnd -lt 0) { throw 'Managed separator metadata is invalid.' }
    Write-AgentsText $current.Substring(0, $prefixEnd)
}

function Install-SkillFiles([string]$ResolvedSource) {
    if ($ResolvedSource.Equals($routerSkillRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    $parent = Split-Path -Parent $routerSkillRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $stage = Join-Path $parent ('auto-visible-team-router.install-' + [guid]::NewGuid().ToString('N'))
    $previous = Join-Path $parent ('auto-visible-team-router.previous-' + [guid]::NewGuid().ToString('N'))
    $rootPrefix = [System.IO.Path]::GetFullPath($parent).TrimEnd('\') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($candidate in @($stage, $previous, $routerSkillRoot)) {
        if (-not [System.IO.Path]::GetFullPath($candidate).StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe skill target: $candidate"
        }
    }
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Copy-Item -Path (Join-Path $ResolvedSource '*') -Destination $stage -Recurse -Force
        if (-not (Test-Path -LiteralPath (Join-Path $stage 'SKILL.md'))) { throw 'Staged skill is incomplete.' }
        if (Test-Path -LiteralPath $routerSkillRoot) { Move-Item -LiteralPath $routerSkillRoot -Destination $previous }
        try {
            Move-Item -LiteralPath $stage -Destination $routerSkillRoot
        } catch {
            if ((Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $routerSkillRoot)) {
                Move-Item -LiteralPath $previous -Destination $routerSkillRoot
            }
            throw
        }
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}

function Get-StatusObject {
    $text = Get-AgentsText
    $markers = Get-MarkerState $text
    [pscustomobject]@{
        action = 'Status'
        version = '1.3.3'
        managed_rule_version = $(if ($text.Contains('自动可视化团队路由器 V1.3.3')) { '1.3.3' } elseif ($text.Contains('自动可视化团队路由器 V1.3.2')) { '1.3.2' } elseif ($text.Contains('自动可视化团队路由器 V1.3.1')) { '1.3.1' } elseif ($text.Contains('自动可视化团队路由器 V1.3.0')) { '1.3.0' } elseif ($text.Contains('自动可视化团队路由器 V1.2.0')) { '1.2.0' } elseif ($text.Contains('自动可视化团队路由器 V1.1.1')) { '1.1.1' } elseif ($text.Contains('自动可视化团队路由器 V1.1')) { '1.1' } elseif ($markers.begins.Count -eq 1) { '1.0' } else { $null })
        codex_home = $routerCodexHome
        skill_root = $routerSkillRoot
        skill_installed = (Test-Path -LiteralPath (Join-Path $routerSkillRoot 'SKILL.md'))
        agents_path = $routerAgentsPath
        managed_rule_enabled = ($markers.begins.Count -eq 1 -and $markers.ends.Count -eq 1)
        begin_markers = $markers.begins.Count
        end_markers = $markers.ends.Count
        registry_path = $routerRegistryPath
        registry_exists = (Test-Path -LiteralPath $routerRegistryPath)
        module_registry_path = $routerModuleRegistryPath
        module_registry_exists = (Test-Path -LiteralPath $routerModuleRegistryPath)
    }
}

switch ($Action) {
    'Status' {
        Get-StatusObject | ConvertTo-Json
    }
    'Install' {
        $resolvedSource = [System.IO.Path]::GetFullPath($SourceRoot)
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource 'SKILL.md'))) { throw "SourceRoot is not a skill: $resolvedSource" }
        $backupDir = New-Backup 'Install'
        Install-SkillFiles $resolvedSource
        Set-ManagedBlock $true
        $status = Get-StatusObject
        $status | Add-Member -NotePropertyName action -NotePropertyValue 'Install' -Force
        $status | Add-Member -NotePropertyName backup_dir -NotePropertyValue $backupDir
        $status | ConvertTo-Json
    }
    'Disable' {
        $backupDir = New-Backup 'Disable'
        Set-ManagedBlock $false
        [pscustomobject]@{
            action = 'Disable'; version = '1.3.3'; backup_dir = $backupDir
            skill_retained = (Test-Path -LiteralPath $routerSkillRoot)
            registry_retained = (Test-Path -LiteralPath $routerRegistryPath)
            module_registry_retained = (Test-Path -LiteralPath $routerModuleRegistryPath)
            managed_rule_enabled = $false
        } | ConvertTo-Json
    }
    'Enable' {
        if (-not (Test-Path -LiteralPath (Join-Path $routerSkillRoot 'SKILL.md'))) { throw 'Skill is not installed; run Install first.' }
        $backupDir = New-Backup 'Enable'
        Set-ManagedBlock $true
        [pscustomobject]@{
            action = 'Enable'; version = '1.3.3'; backup_dir = $backupDir
            registry_retained = (Test-Path -LiteralPath $routerRegistryPath)
            module_registry_retained = (Test-Path -LiteralPath $routerModuleRegistryPath)
            managed_rule_enabled = $true
        } | ConvertTo-Json
    }
    'Uninstall' {
        if (-not $ConfirmUninstall) { throw 'Uninstall requires -ConfirmUninstall.' }
        if (-not $scriptSkillRoot.Equals($routerSkillRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing uninstall outside the exact installed skill root: $routerSkillRoot"
        }
        $backupDir = New-Backup 'Uninstall'
        Set-ManagedBlock $false
        $parent = [System.IO.Path]::GetFullPath((Split-Path -Parent $routerSkillRoot)).TrimEnd('\') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $routerSkillRoot.StartsWith($parent, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe uninstall target.' }
        if (Test-Path -LiteralPath $routerSkillRoot) { Remove-Item -LiteralPath $routerSkillRoot -Recurse -Force }
        [pscustomobject]@{
            action = 'Uninstall'; version = '1.3.3'; backup_dir = $backupDir
            skill_removed = (-not (Test-Path -LiteralPath $routerSkillRoot))
            registry_retained = (Test-Path -LiteralPath $routerRegistryPath)
            module_registry_retained = (Test-Path -LiteralPath $routerModuleRegistryPath)
            managed_rule_enabled = $false
        } | ConvertTo-Json
    }
}
