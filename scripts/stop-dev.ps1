$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PidPath = Join-Path $Root '.rojo-pids.json'
$LivePidPath = Join-Path $Root 'logs\live-sync.pid'
if (Test-Path $PidPath) {
    try {
        $Data = Get-Content $PidPath -Raw | ConvertFrom-Json
        $Process = Get-Process -Id ([int]$Data.rojo) -ErrorAction SilentlyContinue
        if ($Process -and $Process.ProcessName -match '^rojo') {
            Stop-Process -Id $Process.Id -Force
            Write-Host "[OPENWORKS] Stopped Rojo PID $($Process.Id)."
        }
    } finally { Remove-Item $PidPath -Force -ErrorAction SilentlyContinue }
}
if (Test-Path $LivePidPath) {
    $SyncId = 0
    [void][int]::TryParse((Get-Content $LivePidPath -Raw).Trim(), [ref]$SyncId)
    if ($SyncId -gt 0) { Stop-Process -Id $SyncId -Force -ErrorAction SilentlyContinue }
    Remove-Item $LivePidPath -Force -ErrorAction SilentlyContinue
    Write-Host '[OPENWORKS] Stopped live sync.'
}
