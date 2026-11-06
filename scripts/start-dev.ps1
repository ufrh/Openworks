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


# Report the exact code Rojo will serve. A successful git fetch does NOT
# mean the working tree updated; the auto-pull intentionally skips dirty
# and divergent branches. Make this visible instead of silently serving
# an older FORM/gizmo build.
$LocalSha = (& git rev-parse --short=8 HEAD | Out-String).Trim()
$RemoteSha = (& git rev-parse --short=8 "origin/$Branch" 2>$null | Out-String).Trim()
$DirtyFiles = @(git status --porcelain --untracked-files=normal)
$BehindCount = 0
if ($RemoteSha) {
    $BehindCount = [int]((& git rev-list "HEAD..origin/$Branch" --count | Out-String).Trim())
}
Write-Host "[OPENWORKS] Local source: $Branch @ $LocalSha | origin/$Branch @ $RemoteSha"
if ($Branch -ne 'dev') {
    Write-Warning "[OPENWORKS] You are running '$Branch', not dev. Recent gizmo fixes were pushed to dev."
}
if ($BehindCount -gt 0) {
    Write-Warning "[OPENWORKS] STALE SOURCE: local '$Branch' is $BehindCount commit(s) behind origin/$Branch."
    if ($DirtyFiles.Count -gt 0) {
        Write-Warning "[OPENWORKS] Auto-update skipped because local changes exist. Preserve them before merging; do not use Reset unless you intend to discard them."
    } else {
        Write-Warning "[OPENWORKS] Auto-update was not completed. Check diverged commits or fetch/pull failures."
    }
}
$ClientEntry = Join-Path $Root 'src/client/init.client.lua'
if (Test-Path $ClientEntry) {
    $Stamp = Select-String -Path $ClientEntry -Pattern 'local BUILD = "([^"]+)"' |
        Select-Object -First 1
    if ($Stamp) {
        Write-Host "[OPENWORKS] Local client build marker: $($Stamp.Matches.Groups[1].Value)"
    } else {
        Write-Warning '[OPENWORKS] No client BUILD marker in local init.client.lua. The viewport version badge is not in this working tree.'
    }
}
Write-Host '[OPENWORKS] After Rojo connects, STOP Play and start Play again to reload cached client ModuleScripts.'

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
