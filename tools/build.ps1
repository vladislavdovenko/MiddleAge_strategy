param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"
Push-Location "$PSScriptRoot/.."
try {
    $version = & $Godot --version
    if ($version -notmatch '^4\.7\.2\.stable\.') { throw "Expected Godot 4.7.2 stable, got $version" }
    & $Godot --headless --editor --import
    if ($LASTEXITCODE -ne 0) { throw "Project import failed" }
    & $Godot --headless --script res://tests/run.gd
    if ($LASTEXITCODE -ne 0) { throw "Simulation checks failed" }
    New-Item -ItemType Directory -Force build | Out-Null
    & $Godot --headless --export-release "Windows Desktop" build/MiddleAge.exe
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed" }
} finally { Pop-Location }
