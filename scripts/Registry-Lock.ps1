$ErrorActionPreference = 'Stop'

function Get-RouterProcessStartUtc([int]$ProcessId) {
    try {
        return (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
    } catch {
        return $null
    }
}

function Test-RouterVerifiedStaleLock([string]$LockPath, [string]$RegistryPath, [int]$StaleMinutes) {
    if (-not (Test-Path -LiteralPath $LockPath)) { return $false }
    try {
        $raw = [System.IO.File]::ReadAllText($LockPath, [System.Text.Encoding]::UTF8)
        $metadata = $raw | ConvertFrom-Json
    } catch {
        return $false
    }

    foreach ($field in @('pid','processStartTimeUtc','createdAt','registryPath','host')) {
        if ($metadata.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$metadata.$field)) {
            return $false
        }
    }

    $expectedRegistry = [System.IO.Path]::GetFullPath($RegistryPath)
    try { $lockedRegistry = [System.IO.Path]::GetFullPath([string]$metadata.registryPath) } catch { return $false }
    if (-not $lockedRegistry.Equals($expectedRegistry, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }

    try { $created = [datetimeoffset]::Parse([string]$metadata.createdAt) } catch { return $false }
    if ([datetimeoffset]::UtcNow.Subtract($created.ToUniversalTime()).TotalMinutes -lt $StaleMinutes) { return $false }

    $currentStart = Get-RouterProcessStartUtc ([int]$metadata.pid)
    if ($null -eq $currentStart) { return $true }
    return -not $currentStart.Equals([string]$metadata.processStartTimeUtc, [System.StringComparison]::OrdinalIgnoreCase)
}

function Enter-RouterRegistryLock(
    [string]$RegistryPath,
    [int]$WaitMilliseconds = 2000,
    [int]$StaleMinutes = 5
) {
    $resolvedRegistry = [System.IO.Path]::GetFullPath($RegistryPath)
    $parent = Split-Path -Parent $resolvedRegistry
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $lockPath = $resolvedRegistry + '.lock'
    $deadline = [datetime]::UtcNow.AddMilliseconds($WaitMilliseconds)

    while ($true) {
        try {
            $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $metadata = [pscustomobject]@{
                pid = $PID
                processStartTimeUtc = Get-RouterProcessStartUtc $PID
                createdAt = [datetimeoffset]::UtcNow.ToString('o')
                registryPath = $resolvedRegistry
                host = [Environment]::MachineName
                sessionId = $(if ($env:CODEX_THREAD_ID) { $env:CODEX_THREAD_ID } else { $null })
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($metadata | ConvertTo-Json -Compress))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
            return [pscustomobject]@{ stream=$stream; path=$lockPath; metadata=$metadata; recoveredStale=$false }
        } catch [System.IO.IOException] {
            if ([datetime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 100
                continue
            }
            if (Test-RouterVerifiedStaleLock $lockPath $resolvedRegistry $StaleMinutes) {
                try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop } catch {
                    throw "Registry lock is stale but could not be safely recovered: $lockPath"
                }
                $deadline = [datetime]::UtcNow.AddMilliseconds($WaitMilliseconds)
                continue
            }
            throw "Registry is busy or lock ownership cannot be proven stale: $resolvedRegistry"
        }
    }
}

function Exit-RouterRegistryLock([object]$Lock) {
    if ($null -eq $Lock) { return }
    if ($null -ne $Lock.stream) { $Lock.stream.Dispose() }
    if (Test-Path -LiteralPath $Lock.path) { Remove-Item -LiteralPath $Lock.path -Force }
}
