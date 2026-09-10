@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [ember] first run - setting things up
    call install.bat || exit /b 1
)

echo [ember] starting in debug console mode...
".venv\Scripts\python.exe" -m ember
endlocal
