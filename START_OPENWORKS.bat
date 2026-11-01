@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title OPENWORKS - Development

where git >nul 2>nul
if errorlevel 1 (echo Git not found.& pause& exit /b 1)
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (echo This folder is not a Git repository.& pause& exit /b 1)

git fetch --all --prune >nul 2>nul
if errorlevel 1 echo WARNING: fetch failed, using existing local refs.

:menu
for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"
if not defined CURRENT_BRANCH set "CURRENT_BRANCH=(detached HEAD)"
echo.
echo ===== OPENWORKS =====
echo Current branch: !CURRENT_BRANCH!
echo [1] Start current branch
echo [2] Switch branch
echo [3] Fresh reset to origin/dev (DELETES LOCAL CHANGES)
echo [4] Exit
choice /c 1234 /n /m "Select: "
if errorlevel 4 exit /b 0
if errorlevel 3 goto reset
if errorlevel 2 goto switch
if "!CURRENT_BRANCH!"=="(detached HEAD)" goto switch
goto start

:switch
git branch --format="  %%(refname:short)"
git branch -r --format="  %%(refname:short)"
set "TARGET="
set /p "TARGET=Branch to start: "
if not defined TARGET goto menu
git switch "!TARGET!" 2>nul
if not errorlevel 1 goto start
git show-ref --verify --quiet "refs/remotes/origin/!TARGET!"
if errorlevel 1 (echo Branch not found.& goto menu)
git switch --track -c "!TARGET!" "origin/!TARGET!"
if errorlevel 1 (echo Cannot switch. Check local changes.& goto menu)
goto start

:reset
echo.
echo WARNING: This permanently deletes uncommitted and untracked files.
echo Reset dev to origin/dev ONLY if you intentionally want to discard local work.
choice /c YN /n /m "Confirm reset? [Y/N]: "
if errorlevel 2 goto menu
call "%~dp0STOP_OPENWORKS.bat" >nul 2>nul
git fetch origin dev
if errorlevel 1 goto failure
git reset --hard
if errorlevel 1 goto failure
git clean -fd
if errorlevel 1 goto failure
git switch -C dev origin/dev
if errorlevel 1 goto failure
goto start

:start
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-dev.ps1"
if errorlevel 1 goto failure
echo OPENWORKS running. Connect Rojo plugin to localhost:34872.
echo Live sync output appears below. Press Ctrl+C to stop watching.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\live-sync.ps1"
exit /b 0

:failure
echo Operation failed. Check the output above.
pause
exit /b 1
