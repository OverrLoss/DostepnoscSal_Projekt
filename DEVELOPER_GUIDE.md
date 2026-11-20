# Instrukcja Uruchomienia i Rozwoju Projektu (Developer Guide)

Niniejszy przewodnik opisuje krok po kroku jak uruchomić, skompilować i rozwijać system **Dostępność Sal** na nowym urządzeniu (Windows, macOS lub Linux).

---

## 1. Wymagania Wstępne (Prerequisites)

Przed przystąpieniem do pracy upewnij się, że masz zainstalowane:
1. **Flutter SDK** (zalecana wersja 3.24.x lub nowsza):
   - Sprawdź instalację: `flutter doctor`
2. **Python 3.10+**:
   - Sprawdź instalację: `python --version`
   - Wykorzystuje wyłącznie standardowe biblioteki Pythona (`sqlite3`, `http.server`, `socket`, `threading`, `json`). Nie wymaga `pip install`!
3. **Android Studio / Android SDK** (wymagane tylko jeśli kompilujesz aplikację mobilną `.apk`):
   - Wymagane Java JDK 17+ oraz Android SDK Command-line Tools.
4. **Cloudflared CLI** (wymagane tylko dla wystawienia tunelu HTTPS do Internetu):
   - [Pobierz Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
5. **Arduino IDE 2.x** (wymagane tylko dla programowania ESP8266):
   - Zainstaluj pakiet płytek ESP8266 (`http://arduino.esp8266.com/stable/package_esp8266com_index.json`).

---

## 2. Pierwsze Uruchomienie Krok po Kroku

### Krok 1: Pobranie zależności Flutter
W głównym katalogu projektu uruchom:
```bash
flutter pub get
```

### Krok 2: Uruchomienie Serwera Backendowego (Python)
W nowym oknie terminala uruchom:
```bash
python server/sync_server.py
```
Serwer:
- Inicjalizuje bazę danych `server/rooms_backend.db` (jeśli nie istnieje, automatycznie uzupełnia sale Politechniki Rzeszowskiej).
- Uruchamia serwer HTTP REST na porcie `8081`.
- Uruchamia beacon rozgłoszeniowy UDP na porcie `8082`.
- Wypisuje w konsoli lokalne adresy IP w sieci Wi-Fi.

> [!TIP]
> **Na systemie Windows**: Wystarczy dwukrotnie kliknąć plik [run_server_and_tunnel.bat](run_server_and_tunnel.bat). Skrypt automatycznie uruchomi serwer i tunel w tle, otworzy przeglądarkę i udostępni interaktywne menu zarządzania.

### Krok 3: Uruchomienie Aplikacji Flutter w Trybie Deweloperskim
Aby uruchomić aplikację w przeglądarce Chrome:
```bash
flutter run -d chrome
```

Aby uruchomić aplikację na podłączonym telefonie Android:
```bash
flutter run -d <id-urządzenia>
```

---

## 3. Kompilacja Wersji Produkcyjnych

### 3.1. Kompilacja Aplikacji Web
```bash
flutter build web --release
```
Skompilowane pliki trafią do katalogu `build/web`. Serwer Pythona (`server/sync_server.py`) automatycznie serwuje zawartość tego katalogu pod adresem głównym `http://localhost:8081/`.

### 3.2. Kompilacja Aplikacji Android APK
```bash
flutter build apk --release
```
Gotowy plik APK znajduje się w:
```
build/app/outputs/flutter-apk/app-release.apk
```

Aby aplikacja mogła być automatycznie pobierana przez użytkowników w ramach aktualizacji (OTA update), skopiuj plik `.apk` do katalogu `build/web/DostepnoscSal.apk` oraz `server/DostepnoscSal.apk`.

### 3.3. Zwiększanie Wersji (Version Bump)
Przed publikacją nowej wersji zwiększ numer w:
- [pubspec.yaml](pubspec.yaml) — np. `version: 1.3.12+17`,
- `lib/services/app_update_service.dart` (lokalna wersja Web),
- `lib/services/diagnostics_service.dart`,
- `server/sync_server.py` (awaryjne metadane `/api/app-version`),
- `server/deploy_apk.py` (domyślne wartości przy wdrożeniu).

Następnie uruchom `python build_and_deploy.py`, który wygeneruje `server/app_version.json` z nowym numerem i rozmiarem APK. Dzięki temu zainstalowane aplikacje automatycznie wykryją aktualizację.

---

## 4. Tunel Cloudflare na Nowym Urządzeniu

Projekt używa jednego tunelu `victus` i nie wymaga plików poza folderem projektu.

1. Umieść otrzymany plik `victus.token` w `.cloudflared/` (jest objęty `.gitignore`).
2. Upewnij się, że w `.cloudflared/` jest `cloudflared.exe`. Jeśli go nie ma, zainstaluj cloudflared poleceniem `winget install --id Cloudflare.cloudflared`.
3. Uruchom `run_server_and_tunnel.bat` — skrypt sam odpali serwer i tunel z tokenu (chyba że na komputerze działa już usługa `Cloudflared`).

Trasy publiczne (`sale`, `gra`, `plan`) są ustawione w panelu Cloudflare Zero Trust. Szczegóły przekazania tokenu znajdują się w [TUNNEL_TOKEN.md](TUNNEL_TOKEN.md).

---

## 5. Programowanie Mikrokontrolera ESP8266 (Wemos D1 mini)

Kod źródłowy znajduje się w [esp8266_d1mini/esp8266_d1mini.ino](esp8266_d1mini/esp8266_d1mini.ino).

### Schemat Połączeń Sprzętowych:
- **Dioda ZIELONA (Sala Wolna)**:
  - Anoda (+) diody zielonej -> Rezystor 220Ω -> Pin **D1** (GPIO 5)
  - Katoda (-) diody -> Masa (GND)
- **Dioda CZERWONA (Sala Zajęta)**:
  - Anoda (+) diody czerwonej -> Rezystor 220Ω -> Pin **D2** (GPIO 4)
  - Katoda (-) diody -> Masa (GND)

### Konfiguracja w kodzie `.ino`:
1. Ustaw dane sieci Wi-Fi w sekcji konfiguracji:
   ```cpp
   const char* ssid = "NAZWA_SIECI_WIFI";
   const char* password = "HASLO_WIFI";
   ```
2. Ustaw numer sali przypisanej do tego urządzenia:
   ```cpp
   const char* targetRoomNumber = "104";
   ```
3. W Arduino IDE wybierz:
   - Płytka: **LOLIN(WEMOS) D1 R2 & mini**
   - Port COM urządzenia
   - Kliknij **Wgraj (Upload)**.

---

## 6. Ważne Zasady Architektoniczne dla Deweloperów

1. **Wielkość liter w języku polskim**:
   Polskie znaki diakrytyczne (np. `ż` / `Ż`) w standardowym `toUpperCase()` mogą zachowywać się niejednolicie w starszych silnikach JS. Wyszukiwanie sal w [interactive_floor_map.dart](lib/widgets/interactive_floor_map.dart) zawiera bezpieczne dopasowania z obsługą wielkich i małych liter oraz wariantów bez polskich znaków (`GARAZ` / `GARAŻ`).
2. **Kompilacja wieloplatformowa Web vs Mobile**:
   W kodzie unika się importowania `dart:io` bezpośrednio w plikach współdzielonych z Webem. Zamiast tego zastosowano wzorzec Conditional Exports (np. `network_discovery_io.dart` vs `network_discovery_web.dart`), aby zapobiec błędom kompilacji WebAssembly/JS.
3. **Płynność skalowania**:
   Podczas modyfikacji planu pięter należy zachować proporcje bazowego płótna `360.0 x 520.0` px. Wszystkie współrzędne sal są relatywne do tego układu odniesienia i skalują się automatycznie na dowolnym urządzeniu.
