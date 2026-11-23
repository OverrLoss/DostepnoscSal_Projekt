# Instrukcja Uruchomienia i Rozwoju Projektu (Developer Guide)

Niniejszy przewodnik opisuje krok po kroku, jak uruchomić, skompilować i rozwijać system **Dostępność Sal** na nowym urządzeniu (Windows, macOS lub Linux). Aktualny kontrakt API to `v0.1` z prefiksem `/api/v1`; szczegóły znajdują się w [`API_REFERENCE.md`](API_REFERENCE.md).

---

## 1. Wymagania wstępne

1. **Python 3.10+** w `PATH`.
   - Sprawdzenie: `python --version`.
2. **Zależności backendu** z [`requirements.txt`](requirements.txt): FastAPI, uvicorn, pydantic oraz httpx dla testów kontraktu.
   - Instalacja: `python -m pip install -r requirements.txt`.
   - Skrypt `PRZYGOTUJ_KOMPUTER.bat` wykonuje ten krok automatycznie.
3. **Flutter SDK** 3.24 lub nowszy, tylko do przebudowy aplikacji.
   - Sprawdzenie: `flutter doctor`.
4. **Android Studio / Android SDK**, JDK 17+ i Android SDK Command-line Tools — tylko przy kompilacji `.apk`.
5. **Cloudflared CLI** — tylko przy wystawianiu tunelu HTTPS do Internetu.
6. **Arduino IDE 2.x lub `arduino-cli`** — tylko przy kompilacji firmware ESP8266 i ESP32 CYD.

Backend nie wymaga instalacji systemu bazodanowego. SQLite jest w bibliotece standardowej Pythona, a bazę `server/rooms_backend.db` serwer tworzy i migruje przy pierwszym starcie.

---

## 2. Pierwsze uruchomienie krok po kroku

### Krok 1: Zależności Pythona

W głównym katalogu projektu:

```bash
python -m pip install -r requirements.txt
```

Bez tego kroku `python server/sync_server.py` zakończy się błędem `ModuleNotFoundError: No module named 'fastapi'`.

### Krok 2: Zależności Fluttera

```bash
flutter pub get
```

### Krok 3: Uruchomienie backendu

W nowym oknie terminala:

```bash
python server/sync_server.py
```

Serwer:

- inicjalizuje i migruje bazę `server/rooms_backend.db`, w tym sale Politechniki Rzeszowskiej,
- uruchamia REST API i WebSocket na porcie **8081** (domyślnie, nadpisanie przez zmienną `PORT`),
- uruchamia responder UDP na porcie **8082** dla auto-discovery w sieci LAN,
- udostępnia dokumentację Swagger pod `http://localhost:8081/docs` i schemat OpenAPI pod `/api/v1/openapi.json`,
- serwuje zbudowaną aplikację web z `build/web/` pod adresem głównym. Jeśli katalog nie istnieje, zwraca komunikat informacyjny zamiast strony.

> [!TIP]
> Na Windowsie wystarczy dwukrotnie kliknąć [`run_server_and_tunnel.bat`](run_server_and_tunnel.bat). Skrypt uruchamia serwer i tunel w tle, otwiera przeglądarkę i udostępnia menu zarządzania. Stanem procesów zarządza [`server_control.ps1`](server_control.ps1) (`start`, `stop`, `restart`, `status`).

### Krok 4: Uruchomienie aplikacji Flutter w trybie deweloperskim

Przeglądarka:

```bash
flutter run -d chrome
```

Podłączony telefon Android:

```bash
flutter run -d <id-urządzenia>
```

Aplikacja domyślnie łączy się z `https://sale.pwojtaszek.5g.in` (na Webie z origin strony), a w sieci LAN potrafi wykryć serwer przez UDP.

---

## 3. Kontrakt API i dane

Główne grupy endpointów (`/api/v1`):

- `public/rooms` — publiczny odczyt sal dla gości,
- `auth/*` — logowanie, wylogowanie, odświeżanie tokenu, dane użytkownika,
- `rooms/*` — status sali, osoba zajmująca, historia sesji i alertów, limity,
- `admin/*` — sala, układ planu, użytkownicy, urządzenia, ustawienia systemu,
- `device/*` — stan sali dla kontrolera, heartbeat, raport, limit alertu,
- `ws` — aktualizacje `room.updated` i tyknięcia zegara,
- `health`, `app-version`, `cyd-version`, `esp8266-version`, `firmware/*` — informacje systemowe i OTA.

Tabele bazy: `system_settings`, `rooms`, `users`, `devices`, `occupancy_sessions`, `alerts`, `audit_logs`. Status sali to `free` lub `occupied`; przerwa to `occupied` z `is_break=1` i bez aktywnej sesji. Role: `admin`, `operator` i gość. Blokady `lock_status`, `lock_info` i `lock_layout` są sprawdzane przy zapisie po stronie serwera.

Pełna lista endpointów, ciała żądań i odpowiedzi: [`API_REFERENCE.md`](API_REFERENCE.md).

---

## 4. Kompilacja wersji produkcyjnych

### 4.1. Aplikacja Web

```bash
flutter build web --release
```

Pliki trafiają do `build/web/` i są serwowane przez backend pod adresem głównym. Nie usuwaj tego katalogu we wdrożeniu.

### 4.2. Aplikacja Android

```bash
flutter build apk --release
```

Gotowy plik: `build/app/outputs/flutter-apk/app-release.apk`. Skrypt `build_and_deploy.py --apk-only` kopiuje go do `server/`, `build/web/` i katalogu głównego jako `DostepnoscSal.apk` oraz wersjonowaną kopię.

### 4.3. Podniesienie wersji

Przed publikacją zwiększ numer w:

- `pubspec.yaml` (`version: 1.3.21+26`),
- `lib/services/app_update_service.dart` (wersja lokalna Web),
- `lib/services/diagnostics_service.dart`,
- `lib/screens/room_main_screen.dart` (nagłówek),
- `server/sync_server.py` (awaryjne metadane `/api/app-version`),
- `server/deploy_apk.py` (wartości domyślne wdrożenia).

Następnie uruchom `python build_and_deploy.py`, który wygeneruje `server/app_version.json` z nowym numerem i rozmiarem APK. Plik zapisywany jest w UTF-8 bez BOM; modyfikuj go z Pythona lub przez ten skrypt. Po wdrożeniu utwórz annotowany tag `vX.Y.Z`, wypchnij go i opublikuj Release z APK zgodnie z [`AGENTS.md`](AGENTS.md).

---

## 5. Tunel Cloudflare na nowym urządzeniu

Projekt używa jednego tunelu `victus` i nie wymaga plików poza folderem projektu.

1. Umieść otrzymany plik `victus.token` w `.cloudflared/` (jest objęty `.gitignore`).
2. Upewnij się, że w `.cloudflared/` jest `cloudflared.exe`. `PRZYGOTUJ_KOMPUTER.bat` pobierze go automatycznie, alternatywnie: `winget install --id Cloudflare.cloudflared`.
3. Uruchom `run_server_and_tunnel.bat` — skrypt odpali serwer i tunel z tokenu, chyba że działa już usługa `Cloudflared`.

Trasy publiczne (`sale`, `gra`, `plan`) konfiguruje się w panelu Cloudflare Zero Trust, nie w lokalnym `config.yml`. Szczegóły przekazania tokenu: [`TUNNEL_TOKEN.md`](TUNNEL_TOKEN.md).

---

## 6. Mikrokontrolery

### 6.1. ESP8266 Wemos D1 mini

Kod: [`esp8266_d1mini/esp8266_d1mini.ino`](esp8266_d1mini/esp8266_d1mini.ino).

Połączenia:

- dioda zielona (sala wolna): anoda przez rezystor 220 Ω do pinu **D1** (GPIO 5), katoda do GND,
- dioda czerwona (sala zajęta): anoda przez rezystor 220 Ω do pinu **D2** (GPIO 4), katoda do GND.

W kodzie ustaw `ssid`, `password` oraz `targetRoomNumber`, w Arduino IDE wybierz płytkę **LOLIN(WEMOS) D1 R2 & mini** i port urządzenia.

### 6.2. ESP32 CYD

Kod: [`esp32_cyd/esp32_cyd.ino`](esp32_cyd/esp32_cyd.ino), konfiguracja wyświetlacza w `User_Setup.h`, szczegóły w [`esp32_cyd/README_CYD.md`](esp32_cyd/README_CYD.md). Urządzenie czyta stan sali z `/api/v1/device/state`, wysyła heartbeat i wykonuje OTA, gdy wersja serwera różni się od `CYD_FIRMWARE_VERSION`.

Wersje firmware: CYD **1.3.8**, ESP8266 **1.3.8**. Po zmianie firmware zbuduj binarkę `arduino-cli` i podmień plik w `server/`. Rozjazd wersji między urządzeniem a endpointami powoduje pętlę OTA.

---

## 7. Ważne zasady architektoniczne

1. **Polskie znaki w wyszukiwarce sal.** `toUpperCase()` w starszych silnikach JS nie zawsze radzi sobie z diakrytykami. `lib/widgets/interactive_floor_map.dart` zawiera dopasowania bez znaków (`GARAZ` / `GARAŻ`).
2. **Web kontra mobilne.** Nie importuj `dart:io` w plikach współdzielonych z Webem. Używaj conditional exports, np. `network_discovery_io.dart` i `network_discovery_web.dart`.
3. **Skala planu.** Geometria sal jest relatywna do płótna `360.0 x 520.0` px i skaluje się automatycznie. Zmieniając rzuty, zachowaj te proporcje.
4. **Ścieżki.** Używaj `%~dp0`, `$PSScriptRoot`, `os.path.dirname(__file__)` oraz `ANDROID_HOME`/`LOCALAPPDATA`. Zakaz sztywnych `C:\...` i plików poza folderem projektu.
5. **Baza testowa.** `DB_PATH` w `server/sync_server.py` jest obecnie stałą ścieżką `server/rooms_backend.db`. Nie uruchamiaj testów mutujących API na produkcyjnej bazie bez wcześniejszego odizolowania bazy.
6. **Brak modułów pobocznych.** Widok sal jest jedynym ekranem aplikacji; nieużywane moduły pogodowe, kontaktowe i gra w węża zostały usunięte razem z niepotrzebnymi zależnościami i uprawnieniami.

---

## 8. Weryfikacja przed wydaniem

```bash
flutter analyze
flutter test
python -m py_compile server/sync_server.py build_and_deploy.py
```

Testy kontraktu API (`python server/test_contract.py`) wymagają zależności z `requirements.txt`. Korzystają ze ścieżki bazy zapisanej na sztywno w `sync_server.py`, więc przed ich uruchomieniem odizoluj bazę. Testy akceptacyjne wykonuje się manualnie według [`TEST_PLAN.md`](TEST_PLAN.md).
