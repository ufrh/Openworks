param([int]$IntervalSeconds = 3)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Log($Message) {
    Write-Output "[OPENWORKS] $(Get-Date -Format 'HH:mm:ss') $Message"
}

$LastSkip = ''
while ($true) {
    try {
        $Branch = (& git branch --show-current)
        if ($LASTEXITCODE -ne 0) { throw 'Could not determine the active Git branch.' }
        $Branch = ($Branch | Out-String).Trim()

        $Reason = ''
        if (-not $Branch) {
            $Reason = 'Detached HEAD; pull skipped.'
        } else {
            # Untracked screenshots and local scratch files do not modify tracked
            # source. Git itself still refuses to overwrite an untracked
            # path if a remote commit introduces the same filename.
            $Changes = @(git status --porcelain --untracked-files=no)
            if ($LASTEXITCODE -ne 0) { throw 'Could not read Git working tree status.' }

            if ($Changes.Count -gt 0) {
                $Reason = 'Tracked local changes detected; pull skipped to protect your work.'
            } else {
                $FetchOutput = @(git fetch --quiet origin $Branch 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Git fetch failed: $($FetchOutput -join ' ')"
                }

                $Ahead = [int]((& git rev-list "origin/$Branch..HEAD" --count | Out-String).Trim())
                if ($LASTEXITCODE -ne 0) { throw 'Could not determine local commits.' }
                $Behind = [int]((& git rev-list "HEAD..origin/$Branch" --count | Out-String).Trim())
                if ($LASTEXITCODE -ne 0) { throw 'Could not determine remote commits.' }

                if ($Ahead -gt 0) {
                    $Reason = "Local branch is ahead by $Ahead commit(s); automatic pull skipped."
                } elseif ($Behind -gt 0) {
                    Log "Pulling $Behind commit(s) on $Branch..."
                    $PullOutput = @(git merge --ff-only "origin/$Branch" 2>&1)
                    foreach ($Line in $PullOutput) { Log $Line }
                    if ($LASTEXITCODE -ne 0) { throw 'Fast-forward failed; see output above.' }
                    Log "Updated $Branch successfully."
                }
            }
        }

        if ($Reason -ne $LastSkip) {
            if ($Reason) { Log $Reason } elseif ($LastSkip) { Log 'Live sync resumed.' }
            $LastSkip = $Reason
        }
    } catch {
        $Reason = "Sync error: $($_.Exception.Message)"
        if ($Reason -ne $LastSkip) { Log $Reason; $LastSkip = $Reason }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
