$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $root "tools"
$godotDir = Join-Path $tools "godot"
$godotExe = Join-Path $godotDir "Godot_v4.7-stable_win64.exe"
$templates = Join-Path $tools "Godot_v4.7-stable_export_templates.tpz"
$templatesTarget = Join-Path $env:APPDATA "Godot\export_templates\4.7.stable"

New-Item -ItemType Directory -Path $tools,$godotDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $godotExe)) {
    $zip = Join-Path $tools "godot-win64.zip"
    Invoke-WebRequest "https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_win64.exe.zip" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $godotDir -Force
}

if (-not (Test-Path -LiteralPath $templates)) {
    Invoke-WebRequest "https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz" -OutFile $templates
}

$expected = "9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec"
$actual = (Get-FileHash -LiteralPath $templates -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) {
    throw "Godot export template hash mismatch. Delete $templates and rerun this script."
}

if (-not (Test-Path -LiteralPath (Join-Path $templatesTarget "windows_release_x86_64.exe"))) {
    $tmp = Join-Path $env:TEMP ("living-waters-godot-templates-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    tar -xf $templates -C $tmp
    New-Item -ItemType Directory -Path $templatesTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $tmp "templates\*") -Destination $templatesTarget -Recurse -Force
    Remove-Item $tmp -Recurse -Force
}

Write-Host "Godot 4.7 and export templates are ready."
