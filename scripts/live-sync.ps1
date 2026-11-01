param([int]$IntervalSeconds = 3)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
while ($true) {
    try {
        $Branch = (& git branch --show-current 2>$null).Trim()
        if ($Branch -and @(& git status --porcelain 2>$null).Count -eq 0) {
            & git fetch --quiet origin $Branch 2>$null
            if ($LASTEXITCODE -eq 0) {
                $Ahead = [int]((& git rev-list "origin/$Branch..HEAD" --count).Trim())
                $Behind = [int]((& git rev-list "HEAD..origin/$Branch" --count).Trim())
                if ($Ahead -eq 0 -and $Behind -gt 0) {
                    & git pull --ff-only origin $Branch
                    if ($LASTEXITCODE -eq 0) { Write-Host "[OPENWORKS] Pulled $Behind commit(s) on $Branch." }
                }
            }
        }
    } catch { Write-Host "[OPENWORKS] Live sync: $($_.Exception.Message)" }
    Start-Sleep -Seconds $IntervalSeconds
}
