$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not (Test-Path -LiteralPath ".\tools\godot\Godot_v4.7-stable_win64_console.exe")) {
  powershell -ExecutionPolicy Bypass -File ".\setup_godot.ps1"
}

py -3 -m pip install -r ".\background\requirements.txt"

py -3 -m PyInstaller `
  --noconfirm `
  --clean `
  --onefile `
  --windowed `
  --name "LivingWatersBackground" `
  --add-data ".\data\species\freshwater_v1.json;data\species" `
  --add-data ".\data\species\behavior_profiles_v1.json;data\species" `
  ".\background\living_waters_daemon.py"
Copy-Item ".\dist\LivingWatersBackground.exe" ".\LivingWatersBackground.exe" -Force

& ".\tools\godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" ".\build\Living Waters.exe"
Copy-Item ".\build\Living Waters.exe" ".\Living Waters.exe" -Force

Write-Host "Built Living Waters.exe and LivingWatersBackground.exe"
