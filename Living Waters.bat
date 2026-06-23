@echo off
setlocal
cd /d "%~dp0"
set "LIVING_WATERS_ROOT=%~dp0"
if exist "LivingWatersBackground.exe" (
  start "" "LivingWatersBackground.exe" --background
) else (
  start "" pyw -3 "%~dp0background\living_waters_daemon.py" --background
)
timeout /t 2 /nobreak >nul
if exist "Living Waters.exe" (
  start "" "Living Waters.exe"
) else (
  start "" "%~dp0tools\godot\Godot_v4.7-stable_win64.exe" --path "%~dp0"
)
