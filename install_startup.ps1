$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$daemon = Join-Path $root "LivingWatersBackground.exe"
if (Test-Path -LiteralPath $daemon) {
    $command = "`"$daemon`" --background"
} else {
    $script = Join-Path $root "background\living_waters_daemon.py"
    $pythonw = Join-Path (Split-Path (Get-Command py).Source -Parent) "pythonw.exe"
    $command = "pyw -3 `"$script`" --background"
}
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Living Waters" -Value $command
Write-Host "Living Waters will start with Windows."
