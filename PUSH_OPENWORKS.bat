@echo off
setlocal
cd /d "%~dp0"
set /p MSG=Commit message: 
if "%MSG%"=="" set "MSG=Update OPENWORKS"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\push.ps1" "%MSG%"
pause
