@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\pythonw.exe" (
    echo [ember] first run - setting things up
    call install.bat || exit /b 1
)

start "" ".venv\Scripts\pythonw.exe" -m ember
endlocal