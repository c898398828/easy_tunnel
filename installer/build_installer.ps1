# Easy Tunnel Windows Installer Build Script
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Resolve-Path "$scriptDir\.."
$releaseDir = "$projectDir\app\build\windows\x64\runner\Release"
$distDir = "$projectDir\dist"
$zipPath = "$scriptDir\app_package.zip"
$iconPath = "$projectDir\app\assets\tray_icon.ico"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$outExe = "$distDir\EasyTunnel-Setup-v1.0.1.exe"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Easy Tunnel Setup Installer Builder v1.0.1" -ForegroundColor Cyan
Write-Host "=========================================================="

if (-not (Test-Path "$releaseDir\easy_tunnel.exe")) {
    Write-Error "Release artifact not found at: $releaseDir\easy_tunnel.exe. Please build release first."
    exit 1
}

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

Write-Host "[0/3] Compiling latest Flutter release snapshot..." -ForegroundColor Yellow
$flutterCmd = "flutter"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    if (Test-Path "D:\dev\flutter\bin\flutter.bat") {
        $flutterCmd = "D:\dev\flutter\bin\flutter.bat"
    }
}
Push-Location "$projectDir\app"
try {
    & $flutterCmd assemble --output="build" -dTargetPlatform="windows-x64" -dBuildMode="release" -dTargetFile="lib/main.dart" release_bundle_windows-x64_assets
    if (Test-Path "$projectDir\app\build\windows\app.so") {
        Copy-Item "$projectDir\app\build\windows\app.so" "$releaseDir\data\app.so" -Force
        Copy-Item "$projectDir\app\build\flutter_assets\*" "$releaseDir\data\flutter_assets\" -Recurse -Force
        Write-Host "      Synced: app.so and flutter_assets to release bundle." -ForegroundColor Green
    }
} catch {
    Write-Warning "Flutter assemble failed or skipped, packing existing binaries: $_"
} finally {
    Pop-Location
}

Write-Host "[1/3] Packing core release binaries into archive..." -ForegroundColor Yellow
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath -Force
$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "      Created package: app_package.zip ($([math]::Round($zipSize, 2)) MB)" -ForegroundColor Green

Write-Host "[2/3] Compiling C# Installer Wizard with embedded resources..." -ForegroundColor Yellow
if (Test-Path $outExe) { Remove-Item -Path $outExe -Force }

$setupCs = "$scriptDir\Setup.cs"
$args = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/codepage:65001",
    "/win32icon:$iconPath",
    "/resource:$zipPath,app_package.zip",
    "/r:System.dll",
    "/r:System.Windows.Forms.dll",
    "/r:System.Drawing.dll",
    "/r:System.IO.Compression.dll",
    "/r:System.IO.Compression.FileSystem.dll",
    "/out:$outExe",
    "$setupCs"
)

& $csc $args
if ($LASTEXITCODE -ne 0) {
    Write-Error "C# compilation failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "[3/3] Cleaning up temporary build artifacts..." -ForegroundColor Yellow
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }

$exeSize = (Get-Item $outExe).Length / 1MB
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  [SUCCESS] Windows Installer created successfully!" -ForegroundColor Green
Write-Host "  Output: $outExe ($([math]::Round($exeSize, 2)) MB)" -ForegroundColor White
Write-Host "=========================================================="
