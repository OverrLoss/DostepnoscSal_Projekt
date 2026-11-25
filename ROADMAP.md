# Plan Rozwoju Projektu (Roadmap)

Dokument opisuje stan na wersję **1.3.28 (build 33)** oraz kierunki dalszego rozwoju. Szczegóły bieżącego kontraktu API znajdują się w [`API_REFERENCE.md`](API_REFERENCE.md), a scenariusze weryfikacji w [`TEST_PLAN.md`](TEST_PLAN.md).

---

## 1. Aktualny stan (wersja 1.3.28) — zrealizowane

- [x] **Wektorowy plan pięter** z rzeczywistych rzutów SVG (`rzut-parteru-mapa.svg`, `rzut-pietra-mapa.svg`) i autoskalowaniem do ekranu.
- [x] **Garaż podziemny** powiązany z parterem, wspólne zapytania z filtrem `floor=Parter`.
- [x] **Zoom i tryb edycji układu** sal z zapisem `posX`, `posY`, skali i kąta obrotu w bazie SQLite.
- [x] **Statusy sal** `free` / `occupied`, przerwa jako `occupied` + `is_break=1` bez sesji i timera, sesje z limitem i alertem po przekroczeniu.
- [x] **Komunikacja w czasie rzeczywistym** przez WebSocket `/api/v1/ws` (`room.updated`, `alert.created`, `clock.tick`) z fallbackiem pollingowym i reconectem.
- [x] **Autoryzacja i role** (admin, operator sali, gość tylko do odczytu), tokeny, logowanie i odświeżanie.
- [x] **Blokady sali** `lock_status`, `lock_info`, `lock_layout` oraz log audytowy zmian.
- [x] **Zarządzanie z API** salami, użytkownikami, urządzeniami i ustawieniami systemu, dokumentacja Swagger pod `/docs`.
- [x] **Tryb TV / kiosk** z równoległymi rzutami pięter, zegarem i statystykami.
- [x] **Auto-discovery serwera** w LAN przez UDP 8082 z weryfikacją przez `/api/v1/health`.
- [x] **Aktualizacje OTA** aplikacji Android (APK z `app_version.json`) oraz firmware CYD `1.3.8` i ESP8266 `1.3.10`.
- [x] **Węzły IoT** ESP32 CYD z ekranem dotykowym i ESP8266 z dwukolorowymi diodami.
- [x] **Serwer produkcyjny na prywatnym serwerze** z automatyczną aktualizacją po nowym tagu; domena przez tunel Cloudflare.
- [x] **Wersjonowanie** tagami `vX.Y.Z`, wydania GitHub Release z plikiem APK.
- [x] **Dokumentacja zgodna z kodem**: `README.md`, `DEVELOPER_GUIDE.md`, `API_REFERENCE.md`, `TEST_PLAN.md`.

---

## 2. Kierunki rozwoju

### 2.1. Integracja z planem zajęć (USOS / iCal)

Automatyczna zmiana statusu sal na podstawie harmonogramu. Moduł parsujący `.ics` lub API uczelni ustawiałby salę jako zajętą w godzinach zajęć i wolną w przerwach, zamiast ręcznego przełączania. Trzeba zdefiniować reguły pierwszeństwa względem ręcznej zmiany statusu i blokad.

### 2.2. Obsługa kolejnych budynków

Dodanie tabeli `buildings` i mapowania sal do budynków, dynamiczne wczytywanie geometrii z SVG/GeoJSON zamiast stałych ścieżek w kodzie. Wymaga zmiany modelu danych i migracji istniejących sal.

### 2.3. Tabliczki przydrzwiowe z e-paperem

ESP32 z wyświetlaczem e-Ink 2.9" lub 4.2", pokazujący nazwę wydarzenia, prowadzącego, godzinę kolejnych zajęć i kod QR do aplikacji web. Może współdzielić endpoint `/api/v1/device/state` z firmware CYD.

### 2.4. Testy automatyczne i izolacja bazy

- Umożliwić konfigurację `DB_PATH` przez zmienną środowiskową, aby `server/test_contract.py` nie pracował na produkcyjnej bazie (obecnie ścieżka jest na sztywno `server/rooms_backend.db`).
- Rozszerzyć `test/widget_test.dart` o testy widgetów i integrację REST/WS z użyciem `TestClient`.
- Wykonać scenariusze z [`TEST_PLAN.md`](TEST_PLAN.md) przed każdym tagiem wydania.

### 2.5. Twardnienie bezpieczeństwa

- Przechowywać tokeny użytkowników jako hashe, tak jak robi to już `hash_token` dla urządzeń.
- Zmienić hasła kont demo i tokeny urządzeń przed wdrożeniem produkcyjnym.
- Zamknąć luki uprawnień: anonimowy dostęp do `PATCH /api/v1/rooms/{id}/alert-limit`, brak kontroli maksymalnego limitu w `/api/v1/device/alert-limit` oraz nieegzekwowane `lock_layout`.
- Dodać walidację `default_alert_limit <= max_alert_limit` w `PATCH /api/v1/admin/settings`.

### 2.6. Uporządkowanie modułów pobocznych — wykonane

Ekrany pogody, książki adresowej i gry w węża zostały usunięte wraz z nieużywanymi zależnościami (`geolocator`, `flutter_contacts`, `home_widget`, `image_picker`, `flutter_local_notifications`) i niepotrzebnymi uprawnieniami mobilnymi. Aplikacja zawiera wyłącznie widok sal.

### 2.7. Metryki i obserwowalność

`traffic_metrics` w `/api/service-info` są obecnie stałymi wartościami. Warto zastąpić je rzeczywistymi licznikami żądań, pobrań APK i firmware oraz dodać historię alertów do panelu administracyjnego.

---

## 3. Proponowana kolejność

1. Izolacja bazy testowej i uruchomienie testów kontraktu.
2. Zamknięcie luk uprawnień i tokenów użytkowników.
3. Automatyczny plan zajęć jako źródło statusów sal.
4. Obsługa wielu budynków i nowe urządzenia e-paper.
5. Rewitalizacja albo wydzielenie modułów pobocznych.
