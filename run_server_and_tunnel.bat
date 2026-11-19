@echo off
title Dostepnosc Sal - Serwer i Tunel Cloudflare
cd /d "%~dp0"

echo =====================================================================
echo   DOSTEPNOSC SAL - POLITECHNIKA RZESZOWSKA
echo   Serwer Bazy Danych SQLite i Tunel Cloudflare (v1.2.0)
echo =====================================================================
echo.
echo [1/2] Sprawdzanie i uruchamianie uslug w tle...

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server_control.ps1" -Action start

echo.
echo [2/2] Otwieranie aplikacji w przegladarce...
start https://sale.pwojtaszek.5g.in

:menu
echo.
echo =====================================================================
echo   DOSTEPNE OPCJE:
echo   [1] Otworz aplikacje w przegladarce (https://sale.pwojtaszek.5g.in)
echo   [2] Otworz widok TV Kiosk / Wszystkie pietra
echo   [3] Zrestartuj serwer i tunel
echo   [4] ZATRZYMAJ serwer i tunel (calkowite wylaczenie)
echo   [5] Wyjdz (serwer i tunel dzialaja dalej w tle)
echo =====================================================================
echo.
echo Wybierz opcje [1-5]. Za 10 sekund okno zamknie sie automatycznie (opcja 5).

choice /C 12345 /T 10 /D 5 /N /M "Wybierz opcje (1-5): "
set opt=%errorlevel%

if "%opt%"=="1" (
    start https://sale.pwojtaszek.5g.in
    goto menu
)
if "%opt%"=="2" (
    start https://sale.pwojtaszek.5g.in/#/tv
    goto menu
)
if "%opt%"=="3" (
    echo.
    echo Restartowanie uslug...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server_control.ps1" -Action restart
    goto menu
)
if "%opt%"=="4" (
    echo.
    echo Zatrzymywanie serwera i tunelu...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server_control.ps1" -Action stop
    echo Uslugi zostaly zatrzymane.
    timeout /t 3 >nul
    exit
)
if "%opt%"=="5" (
    echo.
    echo Uslugi dzialaja dalej w tle.
    timeout /t 1 >nul
    exit
)

exit
