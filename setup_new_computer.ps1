# setup_new_computer.ps1 - Automatyczne przygotowanie srodowiska na nowym komputerze
param(
    [switch]$AutoStart = $false
)

$Host.UI.RawUI.WindowTitle = "Dostepnosc Sal - Konfiguracja Nowego Komputera"
$ProjectDir = $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }

Clear-Host
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   DOSTEPNOSC SAL - POLITECHNIKA RZESZOWSKA                          " -ForegroundColor Cyan
Write-Host "   Automatyczne Przygotowanie Nowego Komputera do Pracy (v1.2.0)     " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Katalog projektu: $ProjectDir" -ForegroundColor Gray
Write-Host ""

# -----------------------------------------------------------------------------
# KROK 1: Sprawdzenie i instalacja Pythona
# -----------------------------------------------------------------------------
Write-Host "[1/5] Sprawdzanie srodowiska Python..." -ForegroundColor Yellow
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
$pyInstalled = $false

if ($pyCmd) {
    try {
        $pyVer = & python --version 2>&1
        Write-Host "      [OK] Wykryto: $pyVer ($($pyCmd.Source))" -ForegroundColor Green
        $pyInstalled = $true
    } catch {}
}

if (-not $pyInstalled) {
    Write-Host "      [!] Python nie jest zainstalowany w systemie." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "      -> Pobieranie i instalacja Python przez winget (to moze potrwac chwile)..." -ForegroundColor Cyan
        try {
            & winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            $pyCmd = Get-Command python -ErrorAction SilentlyContinue
            if ($pyCmd) {
                Write-Host "      [OK] Python zostal pomyslnie zainstalowany!" -ForegroundColor Green
                $pyInstalled = $true
            }
        } catch {
            Write-Host "      [!] Instalacja automatyczna zwrocila blad." -ForegroundColor Red
        }
    }
    
    if (-not $pyInstalled) {
        Write-Host "      [Wskazowka] Pobierz i zainstaluj Pythona z: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "                  Pamietaj, aby zaznaczyc opcje 'Add Python to PATH'!" -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# KROK 2: Sprawdzenie programu Cloudflare Tunnel (cloudflared)
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Sprawdzanie narzedzia Cloudflare Tunnel (cloudflared)..." -ForegroundColor Yellow
$localCfDir = Join-Path $ProjectDir ".cloudflared"
if (-not (Test-Path $localCfDir)) {
    New-Item -ItemType Directory -Path $localCfDir -Force | Out-Null
}

$localCfExe = Join-Path $localCfDir "cloudflared.exe"
$cfFound = $false
$cfPath = ""

if (Test-Path $localCfExe) {
    $cfPath = $localCfExe
    $cfFound = $true
    Write-Host "      [OK] Wykryto przenosny plik cloudflared.exe w projekcie." -ForegroundColor Green
} else {
    $systemPaths = @(
        (Join-Path ${env:ProgramFiles(x86)} "cloudflared\cloudflared.exe"),
        (Join-Path $env:ProgramFiles "cloudflared\cloudflared.exe")
    )
    foreach ($p in $systemPaths) {
        if (Test-Path $p) {
            $cfPath = $p
            $cfFound = $true
            break
        }
    }
    if (-not $cfFound) {
        $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
        if ($cmd) {
            $cfPath = $cmd.Source
            $cfFound = $true
        }
    }

    if ($cfFound) {
        Write-Host "      [OK] Wykryto systemowy cloudflared: $cfPath" -ForegroundColor Green
    } else {
        Write-Host "      [!] Cloudflared nie jest obecny w systemie." -ForegroundColor Yellow
        Write-Host "      -> Pobieranie oficjalnego pliku wykonywalnego z GitHub Cloudflare..." -ForegroundColor Cyan
        try {
            $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
            Invoke-WebRequest -Uri $cfUrl -OutFile $localCfExe -UseBasicParsing
            if (Test-Path $localCfExe) {
                Write-Host "      [OK] Cloudflared zostal pobrany do folderu projektu!" -ForegroundColor Green
                $cfPath = $localCfExe
                $cfFound = $true
            }
        } catch {
            Write-Host "      [!] Blad pobierania. Mozesz zainstalowac go poleceniem: winget install --id Cloudflare.cloudflared" -ForegroundColor Red
        }
    }
}

# -----------------------------------------------------------------------------
# KROK 3: Generowanie dynamicznej konfiguracji Cloudflare
# -----------------------------------------------------------------------------
Write-Host "`n[3/5] Tunel Cloudflare..." -ForegroundColor Yellow
$tunnelToken = Join-Path $localCfDir "victus.token"
if (Test-Path $tunnelToken) {
    Write-Host "      [OK] Token tunelu victus znajduje sie w folderze projektu." -ForegroundColor Green
} else {
    Write-Host "      [!] Brak .cloudflared\victus.token - dolacz plik otrzymany od administratora." -ForegroundColor Yellow
}
Write-Host "      Trasy sale/gra/plan sa konfigurowane w panelu Cloudflare Zero Trust," -ForegroundColor Gray
Write-Host "      nie w lokalnym pliku config.yml." -ForegroundColor Gray

# -----------------------------------------------------------------------------
# KROK 4: Sprawdzenie Flutter SDK i pobranie zaleznosci
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Sprawdzanie srodowiska Flutter / Dart..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue

if ($flutterCmd) {
    try {
        $flutterVer = & flutter --version 2>&1 | Select-Object -First 1
        Write-Host "      [OK] Wykryto Flutter SDK: $flutterVer" -ForegroundColor Green
        Write-Host "      -> Pobieranie zaleznosci projektu (flutter pub get)..." -ForegroundColor Cyan
        Push-Location $ProjectDir
        & flutter pub get | Out-Null
        Pop-Location
        Write-Host "      [OK] Zaleznosci Flutter pobrane pomyslnie!" -ForegroundColor Green
    } catch {
        Write-Host "      [!] Ostrzezenie podczas pobierania zaleznosci: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "      [Info] Flutter SDK nie zostal znaleziony w PATH." -ForegroundColor Gray
    Write-Host "             (Serwer bazy danych SQLite, wersja Web i tunel dzialaja bez Fluttera)." -ForegroundColor Gray
    Write-Host "             Jesli chcesz modyfikowac kod aplikacji mobilnej, zainstaluj Flutter SDK:" -ForegroundColor Gray
    Write-Host "             https://docs.flutter.dev/get-started/install/windows" -ForegroundColor White
}

# -----------------------------------------------------------------------------
# KROK 5: Utworzenie skrotu na Pulpicie nowego komputera
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Tworzenie skrotu na Pulpicie..." -ForegroundColor Yellow
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Uruchom Serwer Sal (sale.pwojtaszek.5g.in).lnk"
    $targetBat = Join-Path $ProjectDir "run_server_and_tunnel.bat"

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetBat
    $shortcut.WorkingDirectory = $ProjectDir
    $shortcut.Description = "Uruchamia serwer bazy danych SQLite i tunel Cloudflare dla aplikacji Dostepnosc Sal"
    $shortcut.IconLocation = "shell32.dll,18"
    $shortcut.Save()

    Write-Host "      [OK] Utworzono skrot na Pulpicie: 'Uruchom Serwer Sal (sale.pwojtaszek.5g.in)'" -ForegroundColor Green
} catch {
    Write-Host "      [!] Nie udalo sie utworzyc skrotu na Pulpicie: $_" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# PODSUMOWANIE I URUCHOMIENIE
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   KONFIGURACJA ZAKONCZONA POMYSLNIE!                                " -ForegroundColor Green
Write-Host "   Ten komputer jest w pelni przygotowany do pracy z projektem.      " -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Mozesz uruchamiac calosc za pomoca pliku:" -ForegroundColor White
Write-Host "-> $ProjectDir\run_server_and_tunnel.bat" -ForegroundColor Yellow
Write-Host "-> Lub klikajac skrot 'Uruchom Serwer Sal' bezposrednio na Pulpicie." -ForegroundColor Yellow
Write-Host ""

if ($AutoStart) {
    & (Join-Path $ProjectDir "run_server_and_tunnel.bat")
    exit
}

Write-Host "Wybierz kolejna akcje:" -ForegroundColor Yellow
Write-Host "  [1] Uruchom serwer i tunel od razu"
Write-Host "  [2] Wyjdz (zrobisz to pozniej)"
Write-Host ""

$choice = Read-Host "Twoj wybor (1-2)"
if ($choice -eq "1") {
    Start-Process -FilePath (Join-Path $ProjectDir "run_server_and_tunnel.bat")
}
exit
