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
    & $Godot --headless --script res://tests/map_checks.gd
    if ($LASTEXITCODE -ne 0) { throw "Map checks failed" }
    & $Godot --headless --script res://tests/navigation_load.gd
    if ($LASTEXITCODE -ne 0) { throw "Navigation load scenario failed" }
    & $Godot --headless --script res://tests/region_checks.gd
    if ($LASTEXITCODE -ne 0) { throw "Region checks failed" }
    New-Item -ItemType Directory -Force build | Out-Null
    & $Godot --headless --export-release "Windows Desktop" build/MiddleAge.exe
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed" }
    Copy-Item region/world.png,region/LEGEND.txt build/ -Force
} finally { Pop-Location }
