$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function RunGit([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')"
    }
}

if (-not (Test-Path '.git')) { throw 'Missing .git folder. Extract the complete integrated ZIP first.' }
$Remote = (& git remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or $Remote -notmatch '(?i)(github\.com[:/])ufrh/Openworks(\.git)?$') {
    throw "Expected the ufrh/Openworks GitHub remote, but found '$Remote'. Refusing to publish to the wrong repository."
}
$Branch = (& git branch --show-current).Trim()
if ($Branch -ne 'dev') { throw "Expected the integrated 'dev' branch, but you're on '$Branch'." }

# Do not publish an older dev checkout by mistake.
$IntegratedCommit = 'd3862e50194789aca7e150e0789770c4f4fa11c3'
& git merge-base --is-ancestor $IntegratedCommit HEAD
if ($LASTEXITCODE -ne 0) { throw 'This dev branch does not contain the integrated UI V2 build. Use Openworks_Dev_Integrated.zip.' }

$Local = (& git rev-parse --verify 'refs/heads/dev^{commit}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to read local dev commit.' }
$Dirty = @(& git status --porcelain)
if ($Dirty.Count -gt 0) {
    Write-Warning 'Your working tree has uncommitted changes. Those changes will NOT be pushed; only committed files are included.'
}

Write-Host "Publishing integrated dev commit $($Local.Substring(0,7)) to $Remote ..."
RunGit @('push', '--porcelain', 'origin', 'refs/heads/dev:refs/heads/dev')

$RemoteLine = @(& git ls-remote --heads origin dev)
if ($LASTEXITCODE -ne 0 -or $RemoteLine.Count -ne 1) { throw 'Push completed but could not verify GitHub dev.' }
$RemoteSha = ($RemoteLine[0] -split '\s+')[0]
if ($RemoteSha -ne $Local) {
    throw "GitHub dev still points to $RemoteSha rather than expected $Local."
}
Write-Host "SUCCESS: GitHub dev is now $RemoteSha" -ForegroundColor Green
