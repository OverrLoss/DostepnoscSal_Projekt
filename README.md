# Dostępność Sal

[![Flutter](https://img.shields.io/badge/Flutter-3.24%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.162-009485?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![SQLite](https://img.shields.io/badge/SQLite-3-003B57?logo=sqlite&logoColor=white)](https://sqlite.org)
[![Wersja](https://img.shields.io/badge/Wersja-1.3.12%20%2B17-brightgreen)](#wersjonowanie-i-powrót)

System monitorowania i zarządzania dostępnością sal wykładowych, laboratoriów oraz stref specjalnych budynku Politechniki Rzeszowskiej. Łączy plan piętra w przeglądarce i aplikacji mobilnej, backend HTTP/WebSocket, bazę SQLite oraz kontrolery ESP32 CYD i ESP8266 przy salach.

**Publiczny adres:** [https://sale.pwojtaszek.5g.in](https://sale.pwojtaszek.5g.in)

## Funkcjonalności

- **Plan budynku z rzeczywistych rzutów SVG** — parter i piętro, autoskalowanie, zoom, przypisanie sal do konkretnych pomieszczeń.
- **Statusy sal** — `wolna`, `zajęta` oraz `przerwa` (traktowana jako zajęta, ale bez timera i alertu).
- **Aktualizacje na żywo** — WebSocket `/api/v1/ws` oraz polling zapasowy; zmiana statusu jest widoczna natychmiast na wszystkich urządzeniach.
- **Uprawnienia** — administrator ma pełny dostęp, operator sali zmienia tylko status i limit czasu swojej sali, gość ma wyłącznie podgląd.
- **Blokady opcji sali** — niezależne flagi zablokowania zmiany statusu, edycji informacji i timera oraz przesuwania na planie.
- **Tryb TV / kiosk** — pełnoekranowy widok ze zegarem i statystykami kondygnacji.
- **Węzły IoT** — ESP32 CYD z ekranem dotykowym i ESP8266 Wemos D1 mini, automatyczne OTA z serwera.
- **Aktualizacje aplikacji Android** — sprawdzanie wersji, pobieranie APK i instalacja z poziomu aplikacji.

## Architektura

| Warstwa | Technologia | Lokalizacja |
|---|---|---|
| Aplikacja | Flutter / Dart (Android, Web) | `lib/` |
| Backend | Python 3, FastAPI, uvicorn, WebSocket | `server/sync_server.py` |
| Baza danych | SQLite | `server/rooms_backend.db` |
| Web SPA | zbudowana aplikacja Flutter | `build/web/` |
| IoT | ESP32 CYD, ESP8266 (Arduino C++) | `esp32_cyd/`, `esp8266_d1mini/` |
| Tunel | Cloudflare Tunnel `victus` | `.cloudflared/` |
| Wdrożenie | Python + Flutter + arduino-cli | `build_and_deploy.py` |

Serwer nasłuchuje na porcie **8081** (HTTP i WebSocket) oraz **8082** (UDP discovery w sieci lokalnej).

## Szybki start

### Wymagania

- Windows z Pythonem 3.10+ w `PATH`.
- Flutter SDK — tylko do przebudowy aplikacji.
- Plik `.cloudflared/victus.token` oraz `.cloudflared/cloudflared.exe` w folderze projektu.
- `arduino-cli` i odpowiednie rdzenie — tylko do kompilacji firmware.

### Uruchomienie

Jeśli masz cały folder projektu z plikiem tokenu:

```cmd
run_server_and_tunnel.bat
```

Po sklonowaniu repozytorium:

1. Umieść otrzymany plik `victus.token` w katalogu `.cloudflared/`.
2. Jeśli brakuje `cloudflared.exe`, zainstaluj Cloudflared lub skopiuj plik z przekazanego folderu.
3. Uruchom `PRZYGOTUJ_KOMPUTER.bat`, a potem `run_server_and_tunnel.bat`.

Dostępne adresy:

- lokalnie: `http://localhost:8081`
- w sieci LAN: `http://<adres-ip>:8081`
- publicznie: `https://sale.pwojtaszek.5g.in`

Szczegóły przekazania tokenu znajdują się w [`TUNNEL_TOKEN.md`](TUNNEL_TOKEN.md).

## Konfiguracja i bezpieczeństwo

- Domena i tunel: `sale.pwojtaszek.5g.in`, jeden tunel `victus` z trasami dla sal, gry i planu zajęć.
- Konfiguracja serwera jest względna względem katalogu projektu; skrypty używają `%~dp0`, `$PSScriptRoot` i `__file__`.
- Pliki `.cloudflared/`, `*.apk`, `*.bin`, `*.db` są wykluczone z Git — nie trafiają do repozytorium.
- Token tunelu jest tajnicą. Jeśli wycieknie, wygeneruj nowy w panelu Cloudflare i zastąp plik `.cloudflared/victus.token`.
- Hasła kont demo (`admin`, operatorzy) i tokeny urządzeń przed wdrożeniem produkcyjnym należy zmienić.

## Kompilacja i wdrożenie

```bash
flutter analyze
flutter test
python -m py_compile server/sync_server.py build_and_deploy.py
python build_and_deploy.py
```

Skrypt `build_and_deploy.py` buduje Web i APK, kopiuje pliki do katalogów serwera oraz aktualizuje `server/app_version.json`.

Firmware:

```bash
arduino-cli compile --export-binaries --fqbn "esp32:esp32:esp32:PartitionScheme=min_spiffs" esp32_cyd/esp32_cyd.ino
arduino-cli compile --export-binaries --fqbn "esp8266:esp8266:d1_mini" esp8266_d1mini/esp8266_d1mini.ino
```

Wersje firmware muszą być spójne w kodzie urządzenia i w endpointach serwera — rozjazd powoduje ciągłe restarty OTA.

## Wersjonowanie i powrót

Każda wydana wersja ma annotowany tag `vX.Y.Z` oraz GitHub Release z plikiem APK. Aby wrócić do poprzedniej wersji:

```bash
git tag -l
git checkout v1.3.11
```

Bieżąca wersja: **1.3.12 (build 17)**, firmware CYD **1.3.8**, ESP8266 **1.3.6**.

## Dokumentacja

| Plik | Zawartość |
|---|---|
| [`DEVELOPER_GUIDE.md`](DEVELOPER_GUIDE.md) | Uruchomienie, kompilacja, konfiguracja środowiska |
| [`API_REFERENCE.md`](API_REFERENCE.md) | Endpointy REST, WebSocket i protokół UDP |
| [`ROADMAP.md`](ROADMAP.md) | Plan rozwoju |
| [`TUNNEL_TOKEN.md`](TUNNEL_TOKEN.md) | Przekazanie tunelu innej osobie |
| [`AGENTS.md`](AGENTS.md) | Zasady pracy w repozytorium |
