param(
    [string]$Configuration = "release",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Set-Location $root

Write-Host "== Cat Eye After release check =="

Write-Host "1/4 Project audit"
python tools/audit_project.py

Write-Host "2/4 Backend smoke"
python -m backend.smoke_test
if (Test-Path "backend/game_state.sqlite3") {
    Remove-Item -LiteralPath "backend/game_state.sqlite3" -Force
}
if (Test-Path "backend/__pycache__") {
    Remove-Item -LiteralPath "backend/__pycache__" -Recurse -Force
}

Write-Host "3/4 Godot smoke"
godot --headless --path "$root" --quit-after 1
godot --headless --path "$root" --script "res://scripts/SmokeTest.gd"
godot --headless --path "$root" --script "res://scripts/FullRunAudit.gd"

if ($SkipExport) {
    Write-Host "4/4 Export skipped"
    exit 0
}

Write-Host "4/4 Export Windows Desktop"
New-Item -ItemType Directory -Force -Path "build/windows" | Out-Null
$exportArg = "--export-release"
if ($Configuration -eq "debug") {
    $exportArg = "--export-debug"
}

try {
    godot --headless --path "$root" $exportArg "Windows Desktop" "build/windows/猫眼之后.exe"
}
catch {
    Write-Host ""
    Write-Host "Export failed. If the smoke checks above passed, install Godot export templates for 4.6.3 and rerun:" -ForegroundColor Yellow
    Write-Host "  Godot Editor -> Editor -> Manage Export Templates"
    throw
}

Write-Host "Release build ready: build/windows/猫眼之后.exe"
