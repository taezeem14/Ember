@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
    set "PY=py -3"
) else (
    set "PY=python"
)

if not exist ".venv\Scripts\python.exe" (
    echo [ember] creating the local environment
    %PY% -m venv .venv || exit /b 1
)

echo [ember] installing dependencies
call ".venv\Scripts\python.exe" -m pip install --upgrade pip
call ".venv\Scripts\python.exe" -m pip install -r requirements.txt || exit /b 1

echo [ember] ready - run launch.bat
endlocal