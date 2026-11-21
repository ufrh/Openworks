@echo off
setlocal
cd /d "%~dp0"
where rojo >nul 2>nul
if errorlevel 1 (
    echo [OpenWorks] Rojo not found. Install it or run aftman install.
    pause
    exit /b 1
)
echo [OpenWorks] Serving Rojo on localhost:34872 (Ctrl+C to stop).
rojo serve default.project.json --port 34872
pause
