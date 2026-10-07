@echo off
setlocal
if exist "%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" (
    start "SISYPHUS Debug Course" "%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" --path "%~dp0." -- --debug-course --save-path=user://sisyphus-debug-v02.json
    exit /b 0
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "SISYPHUS Debug Course" godot --path "%~dp0." -- --debug-course --save-path=user://sisyphus-debug-v02.json
    exit /b 0
)
echo Godot 4.5 or newer is required.
echo See README.md for the debug course launch command.
pause
