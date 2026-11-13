@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\publish-dev.ps1"
if errorlevel 1 (
  echo.
  echo Publish FAILED. Copy the error above and send it to ChatGPT.
)
pause
