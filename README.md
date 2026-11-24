# Dostępność Sal

[![Flutter](https://img.shields.io/badge/Flutter-3.24%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115%2B-009485?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![SQLite](https://img.shields.io/badge/SQLite-3-003B57?logo=sqlite&logoColor=white)](https://sqlite.org)
[![Wersja](https://img.shields.io/badge/Wersja-1.3.28%20%2B33-brightgreen)](#wersjonowanie-i-powrót)

System monitorowania i zarządzania dostępnością sal wykładowych, laboratoriów oraz stref specjalnych budynku Politechniki Rzeszowskiej. Łączy plan piętra w przeglądarce i aplikacji mobilnej, backend HTTP/WebSocket, bazę SQLite oraz kontrolery ESP32 CYD i ESP8266 przy salach.

**Publiczny adres:** [https://sale.pwojtaszek.5g.in](https://sale.pwojtaszek.5g.in)

## Funkcjonalności
 
- **Plan budynku z rzeczywistych rzutów SVG** — parter i piętro, autoskalowanie, zoom, przypisanie sal do konkretnych pomieszczeń i swobodne przesuwanie układu w trybie edycji.
- **Statusy sal** — `free` (wolna), `occupied` (zajęta) oraz przerwa (`occupied` z `is_break=1`), która nie tworzy sesji, timera ani alertu. Zajęcie sali uruchamia sesję z limitem czasu i alertem po jego przekroczeniu.
- **Aktualizacje na żywo** — WebSocket `/api/v1/ws` rozsyła zdarzenie `room.updated` po każdej zmianie, z fallbackiem pollingowym i ze zegarem serwera dla ukrytych kart przeglądarki.
- **Uprawnienia** — logowanie tokenem, role administratora (pełny dostęp), operatora (tylko status i limit czasu przypisanej sali) i gościa (podgląd). Zmiany są zapisywane w logu audytowym.
- **Blokady opcji sali** — niezależne flagi `lock_status`, `lock_info` i `lock_layout`. Administrator zawsze ma dostęp.
- **Zarządzanie z poziomu API** — CRUD sal, pozycje i kolejność na planie, konta użytkowników, reset haseł, rejestracja i konfiguracja urządzeń. Dokumentacja Swagger pod `/docs`.
- **Tryb TV / kiosk** — pełnoekranowy widok obu kondygnacji ze zegarem i statystykami.
- **Węzły IoT** — ESP32 CYD z ekranem dotykowym (firmware `1.3.8`) i ESP8266 Wemos D1 mini (`1.3.10`), automatyczne OTA z serwera.
- **Aktualizacje aplikacji Android** — sprawdzanie wersji, pobieranie APK i instalacja z poziomu aplikacji na podstawie `server/app_version.json`.

## Architektura

| Warstwa | Technologia | Lokalizacja |
|---|---|---|
| Aplikacja | Flutter / Dart (Android, Web) | `lib/` |
| Backend | Python 3.10+, FastAPI, uvicorn, WebSocket | `server/sync_server.py` |
| Baza danych | SQLite | `server/rooms_backend.db` |
| Web SPA | zbudowana aplikacja Flutter | `build/web/` |
| IoT | ESP32 CYD, ESP8266 (Arduino C++) | `esp32_cyd/`, `esp8266_d1mini/` |
| Produkcja | Proxmox LXC 102, autodeploy po nowym tagu | poza repozytorium |
| Wdrożenie | Python + Flutter + arduino-cli | `build_and_deploy.py` |
| Zależności Pythona | FastAPI, uvicorn, pydantic, httpx | `requirements.txt` |

Serwer nasłuchuje na porcie **8081** (HTTP, WebSocket i Swagger) oraz **8082** (UDP discovery w sieci lokalnej).

## Szybki start

### Wymagania

- Python 3.10+ w `PATH` (Windows do prac deweloperskich, Linux/Proxmox jako produkcja).
- Zależności backendu z `requirements.txt`: `python -m pip install -r requirements.txt`.
- Flutter SDK — tylko do przebudowy aplikacji.
- `arduino-cli` i odpowiednie rdzenie — tylko do kompilacji firmware.

### Uruchomienie

Po sklonowaniu repozytorium zainstaluj zależności Pythona (`python -m pip install -r requirements.txt`) i uruchom backend poleceniem `python server/sync_server.py` (lub `server_control.ps1 -Action start` na Windowsie). Tunel i domena są obsługiwane poza repozytorium.

Ręczne uruchomienie backendu bez skryptów:

```bash
python -m pip install -r requirements.txt
python server/sync_server.py
```

Dostępne adresy:

- lokalnie: `http://localhost:8081` oraz dokumentacja `http://localhost:8081/docs`
- w sieci LAN: `http://<adres-ip>:8081`
- publicznie: `https://sale.pwojtaszek.5g.in`

## Konfiguracja i bezpieczeństwo

- Domena `sale.pwojtaszek.5g.in` jest obsługiwana przez tunel w Home Assistant; konfiguracja tunelu nie jest częścią repozytorium.
- Zmienne środowiskowe backendu: `PORT` (domyślnie `8081`) i `SERVER_SECRET_KEY` (domyślnie losowy klucz przy każdym starcie). Ścieżka bazy jest stała: `server/rooms_backend.db`.
- Konfiguracja serwera jest względna względem katalogu projektu; skrypty używają `%~dp0`, `$PSScriptRoot` i `__file__`.
- Pliki `*.apk`, `*.bin`, `*.db` oraz konfiguracja tunelu są wykluczone z Git — nie trafiają do repozytorium.
- Hasła kont demo (`admin`, operatorzy) i tokeny urządzeń przed wdrożeniem produkcyjnym należy zmienić.

## Kompilacja i wdrożenie

```bash
python -m pip install -r requirements.txt
flutter analyze
flutter test
python -m py_compile server/sync_server.py build_and_deploy.py
python build_and_deploy.py
```

Skrypt `build_and_deploy.py` buduje Web i APK, kopiuje pliki do katalogów serwera oraz aktualizuje `server/app_version.json`. Po wdrożeniu zrestartuj serwer.

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

Bieżąca wersja: **1.3.28 (build 33)**, firmware CYD **1.3.8**, ESP8266 **1.3.10**.

## Dokumentacja

| Plik | Zawartość |
|---|---|
| [`DEVELOPER_GUIDE.md`](DEVELOPER_GUIDE.md) | Uruchomienie, zależności, kompilacja i konfiguracja środowiska |
| [`API_REFERENCE.md`](API_REFERENCE.md) | Aktualne endpointy REST, WebSocket i protokół UDP |
| [`TEST_PLAN.md`](TEST_PLAN.md) | Scenariusze do weryfikacji manualnej przed wydaniem |
| [`ROADMAP.md`](ROADMAP.md) | Stan obecny i plan rozwoju |
| [`AGENTS.md`](AGENTS.md) | Zasady pracy w repozytorium |
| [`requirements.txt`](requirements.txt) | Zależności backendu i testów kontraktu |

## Produkcja — Proxmox i automatyczna aktualizacja

Kod źródłowy jest wyłącznie na GitHub (`main`). Stały serwer działa na Proxmox w kontenerze LXC 102 i obsługuje `https://sale.pwojtaszek.5g.in` przez tunel skonfigurowany w Home Assistant. Repozytorium nie zawiera tokenów ani konfiguracji tunelu.

Po opublikowaniu nowego tagu `vX.Y.Z` i Release z APK, kontener sam pobiera nową wersję z GitHub i restartuje backend. Baza danych, firmware'y i APK zostają lokalnie na Proxmox. Aby sprawdzić wdrożoną wersję:

```bash
curl https://sale.pwojtaszek.5g.in/api/v1/app-version
```

Lokalny `server_control.ps1` służy tylko do uruchamiania backendu podczas rozwoju na Windowsie — nie zarządza tunelem ani produkcją.
