$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root "Living Waters.bat"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "Living Waters.lnk"))
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $root
$shortcut.Description = "Open the persistent Living Waters aquarium"
$shortcut.Save()
Write-Host "Created Desktop shortcut."
