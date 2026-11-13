param([Parameter(Position=0)][string]$Message = 'Update OPENWORKS')
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path '.git')) { throw 'Not a Git repository.' }
$Branch = (& git branch --show-current).Trim()
if (-not $Branch) { throw 'Detached HEAD. Select a branch before pushing.' }
& git add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
$Dirty = @(& git status --porcelain)
if ($Dirty.Count -eq 0) {
    Write-Host 'Working tree clean. Pushing existing commits anyway.'
} else {
    & git commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
}
& git push -u origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
Write-Host "[OPENWORKS] Pushed $Branch."
