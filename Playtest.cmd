@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\playtest.ps1" %*
if errorlevel 1 (
    echo.
    echo Playtest launcher stopped. See the message above.
    pause
    exit /b 1
)
if "%~1"=="" pause
