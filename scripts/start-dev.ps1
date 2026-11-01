$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Logs = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

$Rojo = Get-Command rojo -ErrorAction SilentlyContinue
if (-not $Rojo) {
    $Aftman = Get-Command aftman -ErrorAction SilentlyContinue
    if ($Aftman) {
        Write-Host '[OPENWORKS] Rojo missing. Run aftman install, then retry.'
    }
    throw 'Rojo not found on PATH.'
}

$Branch = (& git branch --show-current).Trim()
if (-not $Branch) { throw 'Detached HEAD; select a branch first.' }

& git fetch --quiet origin $Branch 2>$null
if ($LASTEXITCODE -eq 0) {
    $Dirty = @(& git status --porcelain)
    $Ahead = [int]((& git rev-list "origin/$Branch..HEAD" --count).Trim())
    $Behind = [int]((& git rev-list "HEAD..origin/$Branch" --count).Trim())
    if ($Dirty.Count -eq 0 -and $Ahead -eq 0 -and $Behind -gt 0) {
        & git pull --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { throw 'Could not fast-forward source.' }
    }
}

$PidPath = Join-Path $Root '.rojo-pids.json'
if (Test-Path $PidPath) {
    $PidData = Get-Content $PidPath -Raw | ConvertFrom-Json
    $Existing = Get-Process -Id ([int]$PidData.rojo) -ErrorAction SilentlyContinue
    if ($Existing -and $Existing.ProcessName -match '^rojo') {
        Write-Host "[OPENWORKS] Rojo already running (PID $($Existing.Id))."
    } else {
        Remove-Item $PidPath -Force
    }
}
if (-not (Test-Path $PidPath)) {
    $Proc = Start-Process -FilePath $Rojo.Source -ArgumentList @('serve','default.project.json','--port','34872') -WorkingDirectory $Root -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Logs 'rojo.log') -RedirectStandardError (Join-Path $Logs 'rojo.error.log')
    @{ rojo = $Proc.Id } | ConvertTo-Json | Set-Content $PidPath
    Start-Sleep -Milliseconds 450
    if ($Proc.HasExited) { throw 'Rojo exited unexpectedly. Check logs/rojo.error.log.' }
    Write-Host "[OPENWORKS] Rojo running on localhost:34872 (PID $($Proc.Id))."
}
