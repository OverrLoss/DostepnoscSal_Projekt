#!/usr/bin/env pwsh
# build_and_deploy.ps1
# Jednorazowy skrypt budowania i wdrożenia Dostępność Sal
# Użycie: .\build_and_deploy.ps1
#         .\build_and_deploy.ps1 -ApkOnly
#         .\build_and_deploy.ps1 -WebOnly
#         .\build_and_deploy.ps1 -ApkOnly -SkipBuild

param(
    [switch]$ApkOnly,
    [switch]$WebOnly,
    [switch]$SkipBuild,
    [string]$ReleaseNotes = ""
)

Set-Location $PSScriptRoot
$ErrorActionPreference = "Stop"

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "  Dostępność Sal — Build & Deploy" -ForegroundColor Cyan
Write-Host "======================================================`n" -ForegroundColor Cyan

# Read version from pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match "version:\s*(\d+\.\d+\.\d+)\+(\d+)") {
    $versionName = $Matches[1]
    $versionCode = [int]$Matches[2]
    Write-Host "[build] Wersja z pubspec.yaml: v$versionName (versionCode=$versionCode)" -ForegroundColor Yellow
} else {
    Write-Host "[build] Nie można odczytać wersji z pubspec.yaml!" -ForegroundColor Red
    exit 1
}

if (-not $SkipBuild) {
    if (-not $ApkOnly) {
        Write-Host "`n[build] Flutter Web..." -ForegroundColor Green
        flutter build web --release
        if ($LASTEXITCODE -ne 0) { Write-Host "BŁĄD flutter build web" -ForegroundColor Red; exit 1 }
    }

    if (-not $WebOnly) {
        Write-Host "`n[build] Flutter APK..." -ForegroundColor Green
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { Write-Host "BŁĄD flutter build apk" -ForegroundColor Red; exit 1 }
    }
}

$srcApk = "build\app\outputs\flutter-apk\app-release.apk"
if (-not $WebOnly -and (Test-Path $srcApk)) {
    $apkSize = (Get-Item $srcApk).Length

    Write-Host "`n[deploy] Dystrybucja APK v$versionName ($([Math]::Round($apkSize/1MB, 1)) MB)..." -ForegroundColor Cyan

    # Destinations
    $destinations = @(
        "DostepnoscSal.apk",
        "DostepnoscSal_v$versionName.apk",
        "server\DostepnoscSal.apk",
        "server\DostepnoscSal_v$versionName.apk"
    )
    if (Test-Path "build\web") {
        $destinations += @(
            "build\web\DostepnoscSal.apk",
            "build\web\DostepnoscSal_v$versionName.apk"
        )
    }

    # Remove old versioned APKs
    @(".", "server", "build\web") | ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem "$_\DostepnoscSal_v*.apk" -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -notlike "*v$versionName*"
            } | ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Host "[deploy] Usunięto starą wersję: $($_.Name)" -ForegroundColor DarkGray
            }
        }
    }

    # Copy to all destinations
    foreach ($dest in $destinations) {
        Copy-Item $srcApk $dest -Force
        Write-Host "[deploy] OK: $dest" -ForegroundColor Green
    }

    # Update app_version.json — use Python to avoid BOM (PowerShell UTF-8 adds BOM)
    $appVersionFile = "server\app_version.json"
    if ($ReleaseNotes -eq "") { $ReleaseNotes = "Wersja $versionName" }
    python -c @"
import json, os
path = r'$($PSScriptRoot)\server\app_version.json'
try:
    with open(path, encoding='utf-8-sig') as f:
        data = json.load(f)
except Exception:
    data = {}
data['versionCode'] = $versionCode
data['versionName'] = '$versionName'
data['apkSize'] = $apkSize
data['apkUrl'] = 'https://sale.pwojtaszek.5g.in/DostepnoscSal.apk?v=$versionCode'
if '$ReleaseNotes':
    data['releaseNotes'] = '$ReleaseNotes'
elif 'releaseNotes' not in data:
    data['releaseNotes'] = 'Wersja $versionName'
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('[deploy] app_version.json zaktualizowany bez BOM')
"@
    Write-Host "[deploy] app_version.json zaktualizowany" -ForegroundColor Cyan
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "  ✓ Build & Deploy zakończony!" -ForegroundColor Green
Write-Host "  Wersja: v$versionName (versionCode=$versionCode)" -ForegroundColor Green
if (-not $WebOnly) {
    Write-Host "  APK URL: https://sale.pwojtaszek.5g.in/DostepnoscSal.apk?v=$versionCode" -ForegroundColor Green
}
Write-Host "======================================================`n" -ForegroundColor Green
Write-Host "  WAŻNE: Uruchom ponownie sync_server.py" -ForegroundColor Yellow
Write-Host "  aby serwer wczytał nową wersję z app_version.json`n" -ForegroundColor Yellow
