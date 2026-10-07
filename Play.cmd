@echo off
setlocal
if exist "%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" (
    start "SISYPHUS" "%~dp0.tools\godot\Godot_v4.5.1-stable_win64.exe" --path "%~dp0."
    exit /b 0
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "SISYPHUS" godot --path "%~dp0."
    exit /b 0
)
echo Godot 4.5 or newer is required.
echo Open project.godot in the Godot editor and press F5.
echo See README.md for details.
pause
