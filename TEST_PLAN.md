# Plan testów manualnych

Dokument przeznaczony dla osoby wykonującej testy przed wydaniem nowej wersji. Nie wymaga automatyzacji. Każdy scenariusz należy wykonać na instancji testowej lub na kopii bazy, nie na produkcyjnej `server/rooms_backend.db`.

## 0. Przygotowanie stanowiska

- [ ] Odnotuj wersję aplikacji z ekranu głównego i z `pubspec.yaml` (`1.3.18+23`), wersje firmware (CYD `1.3.8`, ESP8266 `1.3.7`) oraz numer tagu Git.
- [ ] Uruchom backend poleceniem `python server/sync_server.py` i potwierdź dostęp do `http://localhost:8081/docs` oraz `http://localhost:8081/`.
- [ ] Przygotuj konta: `admin`, operator z przypisaną salą i dostęp do widoku gościa (przeglądarka bez tokenu).
- [ ] Zrób kopię bazy przed testami mutującymi. Nie uruchamiaj `python server/test_contract.py` na bazie produkcyjnej: `DB_PATH` jest na sztywno `server/rooms_backend.db`.
- [ ] Przygotuj co najmniej dwa klientów jednocześnie (na przykład dwie karty przeglądarki albo przeglądarka i telefon), aby sprawdzić aktualizacje na żywo.
- [ ] Narzędzia pomocnicze: przeglądarka z konsolą, telefon z APK, opcjonalnie `curl` lub `Invoke-RestMethod` do wywołań API.

Wyniki wpisuj w tabelę na końcu pliku albo w osobny arkusz: identyfikator scenariusza, data, środowisko, wynik (PASS/FAIL), uwagi.

---

## 1. Uruchomienie i infrastruktura

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| INF-01 | `GET /api/v1/health`, `/api/health`, `/api/server-info`, `/api/service-info` | Status `ok`, poprawny `lanUrl`, `contract_version: 0.1`, czas pracy i rozmiar bazy. Pamiętaj, że `traffic_metrics` są wartościami stałymi |
| INF-02 | Otwórz `/docs` i `/api/v1/openapi.json` | Swagger i schemat zawierają grupy Public, Auth, Rooms, Limits, Admin, Devices, System, Firmware |
| INF-03 | Otwórz adres główny serwera | Ładuje się SPA z `build/web/`. Jeśli katalogu brak, widoczny jest komunikat informacyjny zamiast strony |
| INF-04 | Wyślij `DISCOVER_ROOM_SERVER` na `255.255.255.255:8082` z innego urządzenia w LAN | Odpowiedź `ROOM_SERVER_ANNOUNCEMENT` z poprawnym `lanUrl`. Upewnij się, że serwer został uruchomiony jako skrypt, nie tylko zaimportowany |
| INF-05 | Otwórz `https://sale.pwojtaszek.5g.in` | Aplikacja działa przez tunel `victus`, bez błędów mixed content i certyfikatu |
| INF-06 | Zrestartuj serwer w trakcie otwartej aplikacji | Klient WS łączy się ponownie z opóźnieniem 3 s do 60 s, dane wracają bez odświeżania strony |

---

## 2. Logowanie i role

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| AUTH-01 | Zaloguj się jako `admin` | Otrzymujesz token, `/api/v1/auth/me` zwraca `role: admin` i pełną listę sal |
| AUTH-02 | Zaloguj się jako operator | `role: operator`, `GET /api/v1/rooms` zwraca wyłącznie salę przypisaną do konta |
| AUTH-03 | Logowanie z błędnym hasłem | Błąd autoryzacji, brak tokenu |
| AUTH-04 | `POST /api/v1/auth/refresh` ważnym tokenem | Nowy token, stary przestaje działać |
| AUTH-05 | `POST /api/v1/auth/logout`, potem użycie tokenu | Token odrzucony |
| AUTH-06 | Gość próbuje zmienić status sali | `403 FORBIDDEN` z kodem błędu w envelope `error` |
| AUTH-07 | Operator próbuje zmienić status innej sali | `403 FORBIDDEN` |
| AUTH-08 | Operator zmienia status swojej sali | Zmiana zapisana, widoczna u admina i gościa |

---

## 3. Statusy sal, sesje i przerwy

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| ROOM-01 | Z sali wolnej ustaw `occupied` z imieniem zajmującego | Status zajęty, pojawia się licznik czasu i imię w karcie sali, w bazie powstaje aktywna sesja |
| ROOM-02 | Zmień imię zajmującego przez `PATCH /rooms/{id}/occupant` | Nowa nazwa widoczna u wszystkich klientów po WS `room.updated` |
| ROOM-03 | Ustaw `occupied` z `is_break=true` | Sala zajęta, brak licznika i alertu, ewentualna sesja zakończona, w historii widać `ended_at` |
| ROOM-04 | Z przerwy przejdź ponownie na `occupied` bez `is_break` | Tworzy się nowa sesja z czasem liczonym od nowa |
| ROOM-05 | Ustaw `free` | Sesja zamknięta, licznik znika, sala wolna u wszystkich klientów |
| ROOM-06 | Sprawdź `GET /rooms/{id}/sessions` i `/alerts` | Historia zawiera sesje i alerty, maksymalnie 50 wpisów, poprawne znaczniki czasu UTC |
| ROOM-07 | Zmień status tej samej sali z dwóch klientów niemal jednocześnie | Ostatnia zmiana wygrywa, obaj klienci ostatecznie pokazują ten sam stan, nie ma dwóch aktywnych sesji |
| ROOM-08 | Ustaw `occupied` z `occupant_name` dłuższym niż 40 znaków | Walidacja odrzuca żądanie (`422`) |

---

## 4. Blokady opcji sali

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| LOCK-01 | Włącz `lock_status`, spróbuj zmienić status jako operator i jako admin | Operator dostaje błąd blokady, admin przechodzi (administrator omija blokady) |
| LOCK-02 | Włącz `lock_status`, wyślij `POST /api/v1/device/status` tokenem urządzenia | Zmiana odrzucona mimo uprawnień urządzenia |
| LOCK-03 | Włącz `lock_info`, spróbuj zmienić imię zajmującego i limit sali | Zmiana odrzucona dla użytkownika, admin przechodzi |
| LOCK-04 | Włącz `lock_layout`, spróbuj przesunąć salę w trybie edycji | **Znany rozjazd:** frontend może zablokować edycję, ale backend nie egzekwuje `lock_layout`. Sprawdź zachowanie i odnotuj |
| LOCK-05 | Wyłącz blokady przez `PATCH /admin/rooms/{id}/locks` | Pola w odpowiedzi i w reprezentacji sali wracają do `false` |

---

## 5. Limity czasu i alerty

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| LIMIT-01 | Sprawdź domyślne ustawienia: `GET /admin/settings` | `default_alert_limit_seconds = 900`, `max_alert_limit_seconds = 7200` |
| LIMIT-02 | Ustaw limit sali na krótki czas testowy i zajmij salę | Po upływie limitu pojawia się alert `occupancy_limit_exceeded`, zdarzenie WS `alert.created`, licznik pokazuje przekroczenie |
| LIMIT-03 | Zmień limit aktywnej sesji przez `PATCH /sessions/{id}/alert-limit` | `alert_due_at` przesuwa się zgodnie z nowym limitem; limit liczony jest jednak od `started_at`, nie od chwili zmiany |
| LIMIT-04 | Ustaw limit powyżej 7200 s przez `PATCH /rooms/{id}/alert-limit` | Błąd `ALERT_LIMIT_EXCEEDS_MAXIMUM` z `details.maximum_seconds` |
| LIMIT-05 | Wyślij `POST /api/v1/device/alert-limit` z wartością powyżej maksimum | **Znany rozjazd:** endpoint nie sprawdza maksimum. Odnotuj faktyczne zachowanie |
| LIMIT-06 | Wyślij `PATCH /rooms/{id}/alert-limit` bez tokenu | **Znany rozjazd:** endpoint jest osiągalny anonimowo. Odnotuj faktyczne zachowanie |
| LIMIT-07 | Sprawdź alerty dwukrotnie dla tej samej sesji | W bazie jest najwyżej jeden alert danego typu na sesję (unique constraint) |

---

## 6. Administracja

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| ADMIN-01 | Utwórz salę przez `POST /admin/rooms` | Nowa sala pojawia się na liście i na planie po przeliczeniu pozycji |
| ADMIN-02 | Edytuj nazwę, kategorię, pojemność i opis sali | Zmiany widoczne w karcie sali i w API |
| ADMIN-03 | Usuń salę z historią sesji | Sala znika, sesje i alerty są usuwane kaskadowo, brak błędów referencyjnych |
| ADMIN-04 | Zmień kolejność sal i zresetuj pozycje | `sortOrder` i `posX/posY` aktualizują się zgodnie z żądaniem, plan odświeża się |
| ADMIN-05 | Utwórz operatora i przypisz go do sali | Operator loguje się i widzi tylko swoją salę |
| ADMIN-06 | Zresetuj hasło użytkownika | Nowe hasło działa, stare tokeny użytkownika przestają być ważne |
| ADMIN-07 | Zarejestruj urządzenie | Token zwracany tylko raz, w bazie zapisany jako hash SHA-256, urządzenie widoczne na liście |
| ADMIN-08 | Zmień i usuń urządzenie | Przypisanie sali do urządzenia aktualizuje się poprawnie, usunięcie czyści `rooms.device_id` |

---

## 7. Plan pięter i widoki w aplikacji

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| UI-01 | Przełączaj filtry pięter: parter, piętro, wszystkie | Właściwe sale, parter dodatkowo pokazuje garaż |
| UI-02 | Szukaj sali z polskimi znakami i bez nich (`GARAŻ`, `garaz`, `GARAZ`) | Wyszukiwarka znajduje te same pomieszczenia |
| UI-03 | Zoom (`-`, `+`, reset) i przeciąganie planu | Skala mieści się w zakresie 0.25x do 3.5x, plan nie ucieka z ekranu |
| UI-04 | W trybie edycji przesuń salę i zmień skalę oraz kąt | Zapis trafia do bazy, widok odświeża się u innych klientów, skala mieści się w 0.4 do 3.0 |
| UI-05 | Otwórz tryb TV / kiosk | Widoczne są oba rzuty, zegar z serwera i liczniki wolnych/zajętych sal |
| UI-06 | Przełącz widok mapa / lista i filtr statusów | Lista i mapa pokazują ten sam zestaw sal, filtr działa poprawnie |
| UI-07 | Otwórz kartę sali z różnymi statusami | Wolna, zajęta z timerem i przerwa wyświetlają się odmiennie, przerwa nie ma licznika |

---

## 8. Klient Web i Android

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| APP-01 | Otwórz aplikację w Chrome na różnych szerokościach okna | Układ nie łamie się, plan skaluje się do kontenera |
| APP-02 | Uruchom APK na telefonie w sieci LAN i przez Internet | Połączenie ustanowione, auto-discovery działa w LAN, publiczny URL działa poza LAN |
| APP-03 | Sprawdź ekran aktualizacji aplikacji | Informacja o wersji zgodna z `app_version.json`, przy starszej wersji pojawia się powiadomienie o aktualizacji |
| APP-04 | Pobierz i zainstaluj APK z poziomu aplikacji (na urządzeniu testowym) | Pobieranie postępuje, instalacja kończy się sukcesem, wersja po restarcie jest aktualna |
| APP-05 | Wyłącz Wi-Fi i włącz ponownie | Klient przechodzi w stan offline i wraca do synchronizacji bez restartu aplikacji |

---

## 9. Urządzenia IoT i OTA

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| DEV-01 | Wywołaj `GET /api/v1/device/state` tokenem urządzenia z przypisaną salą | Odpowiedź zawiera status sali, aktywną sesję i sekcję `firmware` z `has_update` |
| DEV-02 | Wywołaj `GET /api/v1/device/state` bez przypisanej sali | `400 ROOM_NOT_ASSIGNED` |
| DEV-03 | Wyślij heartbeat i status z urządzenia | `last_seen_at` aktualizuje się, zmiana statusu pojawia się na ekranach jako `room.updated` |
| DEV-04 | Sprawdź `/api/v1/cyd-version` i `/api/v1/esp8266-version` | Wersje `1.3.8` i `1.3.6`, zgodne ze stałymi w plikach `.ino` |
| DEV-05 | Pobierz firmware z `/api/v1/cyd-firmware.bin` i `/api/v1/esp8266-firmware.bin?chip=esp8266` | Pliki binarne pobierają się i odpowiadają właściwym układom |
| DEV-06 | Sprawdź alias `/api/v1/esp8266-firmware.bin` bez parametru `chip` | **Znany rozjazd:** serwer zwraca binarkę CYD, bo domyślnie `chip=esp32`. Odnotuj |
| DEV-07 | Uruchom OTA na obu urządzeniach | Aktualizacja kończy się i nie wchodzi w pętlę restartów; rozjazd wersji jest wykluczony |
| DEV-08 | Wyślij `X-Firmware-Version` i `X-Chip-Type` w żądaniu stanu | Serwer zapisuje te wartości w rekordzie urządzenia |

---

## 10. Diagnostyka, wersje i wydanie

| ID | Scenariusz | Oczekiwany wynik |
|---|---|---|
| REL-01 | Otwórz dialog diagnostyki z menu ekranu sal | Raport zawiera platformę, wersję `1.3.18+23`, ping `/api/v1/health`, liczbę sal i dane `/api/service-info` |
| REL-02 | Skopiuj raport diagnostyczny | Schowek zawiera poprawny JSON |
| REL-03 | Porównaj wersje we wszystkich miejscach z `AGENTS.md` | `pubspec.yaml`, `app_update_service.dart`, `diagnostics_service.dart`, nagłówek `room_main_screen.dart`, fallback w `sync_server.py`, `deploy_apk.py` i `app_version.json` są spójne |
| REL-04 | Sprawdź tag i Release na GitHubie | Dla wersji istnieje annotowany tag `vX.Y.Z` i Release z plikiem APK |
| REL-05 | Sprawdź zawartość repozytorium | Brak `.cloudflared/`, tokenów, `*.apk`, `*.bin`, `*.db` i `__pycache__/` w Git |

---

## 11. Wyniki

| ID | Data | Środowisko | Wynik | Uwagi |
|---|---|---|---|---|
|  |  |  |  |  |
