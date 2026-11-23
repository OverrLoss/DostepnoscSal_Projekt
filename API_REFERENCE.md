# Specyfikacja API i protokołów (API Reference)

Backend `server/sync_server.py` udostępnia REST API, WebSocket i pliki do pobrania na porcie **8081** (publicznie przez `https://sale.pwojtaszek.5g.in`) oraz responder UDP na porcie **8082**.

- Tytuł aplikacji: `DostępnośćSal API`, wersja `1.0.0`, wersja kontraktu `0.1`.
- Dokumentacja interaktywna: `/docs` (Swagger) i `/redoc`, schemat: `/api/v1/openapi.json`.
- Wszystkie endpointy opisane poniżej dotyczą aktualnego kodu. Starsze ścieżki `/api/rooms`, `/api/rooms/toggle` i `/api/stats` już nie istnieją.

---

## 1. Konwencje wspólne

### Konfiguracja i adresy

| Element | Wartość | Źródło |
|---|---|---|
| Port HTTP/WS | `8081` | zmienna środowiskowa `PORT` |
| Baza danych | `server/rooms_backend.db` | stała ścieżka w kodzie |
| Klucz podpisu | losowy przy starcie | zmienna `SERVER_SECRET_KEY` |
| Katalog Web | `build/web/` | stała ścieżka względem projektu |
| Domena publiczna | `https://sale.pwojtaszek.5g.in` | tunel `victus` |

### Autoryzacja

- Użytkownik: nagłówek `Authorization: Bearer <token>`. Token ważny 7 dni, generowany przy logowaniu i odświeżaniu. Hasła hashowane PBKDF2-HMAC-SHA256 z 100000 iteracji.
- Urządzenie: nagłówek `X-Device-Token <token>` albo `Bearer`. `X-Device-Token` ma priorytet. Tokeny urządzeń są w bazie hashowane SHA-256 i zwracane tylko raz przy rejestracji.
- Role: `admin` ma pełny dostęp i omija blokady, `operator` wyłącznie do przypisanej sali, gość ma tylko odczyt publiczny.

### Błędy i nagłówki

Błędy domenowe mają postać:

```json
{"error": {"code": "FORBIDDEN", "message": "...", "details": {}, "request_id": "..."}}
```

Błędy prostych endpointów (APK, firmware) zwracają `{"detail": "..."}`. Każde żądanie dostaje `X-Request-ID`. Odpowiedzi wersji, APK i firmware mają `Cache-Control: no-cache, no-store, must-revalidate`. CORS jest otwarty dla wszystkich originów z credentials.

---

## 2. Reprezentacje danych

**Sala publiczna** (`GET /api/v1/public/rooms[*]`):

`id`, `name`, `location`, `floor`, `status`, `category`, `description`, `capacity`, `customNote`, `posX`, `posY`, `layout_scale`, `layout_angle`, `svg_id`, `is_break`, `lock_status`, `lock_info`, `lock_layout`, `default_alert_limit_seconds`, `active_session`, `updated_at`.

**Sala szczegółowa** (`GET /api/v1/rooms[*]`, admin/operator): te same pola oraz `operator_id`, `device_id` (widoczne tylko dla admina, inaczej `null`) i `created_at`.

**Aktywna sesja** (`active_session`, `format_active_session`):

```json
{
  "id": "uuid",
  "room_id": "104",
  "started_at": "2026-11-21T09:00:00Z",
  "duration_seconds": 600,
  "alert_limit_seconds": 900,
  "alert_due_at": "2026-11-21T09:15:00Z",
  "alert_triggered_at": null,
  "alert_due": false,
  "occupant_name": "Jan Kowalski"
}
```

**Sesja w historii** (`GET /api/v1/rooms/{room_id}/sessions`): `id`, `room_id`, `started_at`, `ended_at`, `alert_limit_seconds`, `alert_due_at`, `alert_triggered_at`, `started_by`, `ended_by`, `occupant_name`. Maksymalnie 50 rekordów.

**Alert** (`GET /api/v1/rooms/{room_id}/alerts`): `id`, `room_id`, `session_id`, `triggered_at`, `type` (zwykle `occupancy_limit_exceeded`). Maksymalnie 50 rekordów.

---

## 3. Modele żądań

| Model | Pola |
|---|---|
| `LoginRequest` | `username: str`, `password: str` |
| `StatusChangeRequest` | `status: str` (`free` lub `occupied`), `is_break: bool = false`, `occupant_name?: str` (max 40) |
| `OccupantChangeRequest` | `occupant_name?: str` (max 40) |
| `AlertLimitChangeRequest` | `alert_limit_seconds?: int >= 1`, `limit_seconds?: int` (alias) |
| `SystemSettingsUpdateRequest` | `default_alert_limit_seconds?: int >= 1`, `max_alert_limit_seconds?: int >= 1` |
| `CreateRoomRequest` | `id: str`, `name: str`, `location?: str = ""`, `floor: str = "Parter"`, `category: str = "Laboratorium"`, `description?: str = ""`, `capacity: int = 30`, `posX?: float`, `posY?: float`, `svg_id?: str`, `default_alert_limit_seconds?: int` |
| `UpdateRoomRequest` | opcjonalnie `name`, `location`, `floor`, `category`, `description`, `capacity`, `posX`, `posY`, `operator_id`, `svg_id`, `default_alert_limit_seconds` |
| `RoomLocksRequest` | opcjonalnie `lock_status?: bool`, `lock_info?: bool`, `lock_layout?: bool` |
| `RoomPositionRequest` | `posX: float`, `posY: float` |
| `RoomLayoutRequest` | `scale: float = 1.0` (0.4 do 3.0), `angle: float = 0.0` (-360 do 360) |
| `ResetPositionsRequest` | `floor?: str` (`"Wszystkie"` lub brak czyści wszystkie piętra) |
| `ReorderRoomsRequest` | `roomIds: List[str]` |
| `CreateUserRequest` | `username: str`, `password: str`, `display_name: str`, `role: str` (`admin` lub `operator`), `room_id?: str` |
| `UpdateUserRequest` | opcjonalnie `display_name`, `role`, `room_id`, `is_active`, `password` |
| `PasswordResetRequest` | `new_password?: str` (gdy brak, generowane 8 znaków) |
| `RegisterDeviceRequest` | `name: str`, `room_id?: str` |
| `UpdateDeviceRequest` | opcjonalnie `name`, `room_id`, `is_active: bool` |
| `DeviceAlertLimitRequest` | `limit_seconds?: int`, `alert_limit_seconds?: int` |

---

## 4. Endpointy REST

### 4.1. Dane publiczne

| Metoda i ścieżka | Body / parametry | Odpowiedź |
|---|---|---|
| `GET /api/v1/public/rooms` | `floor?: str` | tablica sal publicznych. Dla `floor=Parter` odpowiedź zawiera też garaż, `floor=wszystkie` działa jak brak filtra |
| `GET /api/v1/public/rooms/{room_id}` | `room_id` w ścieżce | jedna sala publiczna, `404 RESOURCE_NOT_FOUND` |

### 4.2. Uwierzytelnianie

| Metoda i ścieżka | Auth | Body | Odpowiedź |
|---|---|---|---|
| `POST /api/v1/auth/login` | publiczny | `LoginRequest` | `access_token`, `token`, `token_type: "Bearer"`, `user{id, username, display_name, role, room_id}`; audyt `user_logged_in` |
| `POST /api/v1/auth/logout` | Bearer opcjonalny | nagłówek `Authorization` | `{"status":"success","message":"Wylogowano pomyślnie."}`, usuwa token |
| `POST /api/v1/auth/refresh` | ważny Bearer | nagłówek `Authorization` | nowy token, stary usuwany, nowy ważny 7 dni |
| `GET /api/v1/auth/me` | user | brak | `id`, `username`, `display_name`, `role`, `room_id`, `is_active` |

### 4.3. Sale, sesje i historia

| Metoda i ścieżka | Auth | Body | Odpowiedź i efekty |
|---|---|---|---|
| `GET /api/v1/rooms` | user | brak | tablica sal szczegółowych. Operator widzi tylko swoją salę |
| `GET /api/v1/rooms/{room_id}` | user | `room_id` | sala szczegółowa; operator innej sali dostaje 403 |
| `PATCH /api/v1/rooms/{room_id}/occupant` | user, blokada `lock_info` | `OccupantChangeRequest` | `{"data":{"room_id","active_session"}}`; aktualizacja `occupant_name`, WS `room.updated` |
| `PATCH` lub `POST /api/v1/rooms/{room_id}/status` | user, blokada `lock_status` | `StatusChangeRequest` | `{"data":{"room_id","status","is_break","changed","active_session"},"meta":{"server_time"}}`; audyt `session_started` / `break_started` / `session_ended`, WS przy zmianie |
| `GET /api/v1/rooms/{room_id}/sessions` | user | brak | historia sesji, max 50 |
| `GET /api/v1/rooms/{room_id}/alerts` | user | brak | historia alertów, max 50 |

Semantyka statusu:

- `occupied` z `is_break=false` ze stanu `free` lub z przerwy rozpoczyna sesję z limitem z sali albo z `system_settings` (domyślnie 900 s).
- `occupied` z `is_break=true` kończy ewentualną sesję, ustawia `is_break=1` i nie tworzy timera ani alertu.
- `free` kończy sesję i zeruje przerwę.
- Na salę przypada najwyżej jedna aktywna sesja (unique index).

### 4.4. Limity alertów

| Metoda i ścieżka | Auth | Body | Odpowiedź i efekty |
|---|---|---|---|
| `PATCH` lub `POST /api/v1/rooms/{room_id}/alert-limit` | opcjonalnie user lub device, blokada `lock_info` dla usera | `AlertLimitChangeRequest` | `status`, `room_id`, `default_alert_limit_seconds`, `active_session`; 400 `ALERT_LIMIT_EXCEEDS_MAXIMUM`; aktualizacja sali i sesji, audyt, WS |
| `PATCH /api/v1/sessions/{session_id}/alert-limit` | admin | `AlertLimitChangeRequest` z wymaganym `alert_limit_seconds` | `status`, `session_id`, `alert_limit_seconds`, `alert_due_at`; audyt `session_limit_changed`, WS |
| `GET /api/v1/admin/settings` | admin | brak | mapa `system_settings` z wartościami liczbowymi jako `int` |
| `PATCH /api/v1/admin/settings` | admin | `SystemSettingsUpdateRequest` | `{"status":"success","settings":{...}}`; audyt `system_settings_updated` |

Domyślny limit: 900 s (15 min), maksymalny: 7200 s (2 h). Monitor sprawdza przekroczenia co 2 s i zapisuje alert `occupancy_limit_exceeded` z unikalnością na sesję.

### 4.5. Administracja salami i kontami

| Metoda i ścieżka | Body | Odpowiedź i efekty |
|---|---|---|
| `POST /api/v1/admin/rooms` | `CreateRoomRequest` | `{"status":"success","id"}`; 409 przy konflikcie przypisania; audyt `room_created` |
| `PATCH /api/v1/admin/rooms/{room_id}` | `UpdateRoomRequest` | aktualizacja tylko podanych pól, audyt `room_updated` |
| `PATCH /api/v1/admin/rooms/{room_id}/locks` | `RoomLocksRequest` | `status`, `room_id`, `lock_status`, `lock_info`, `lock_layout`; audyt `room_locks_changed` |
| `DELETE /api/v1/admin/rooms/{room_id}` | brak | usunięcie sali z kaskadą sesji i alertów, audyt `room_deleted` |
| `POST /api/v1/admin/rooms/{room_id}/position` | `RoomPositionRequest` | `{"status":"success","room":<reprezentacja sali>}`; WS |
| `POST /api/v1/admin/rooms/{room_id}/layout` | `RoomLayoutRequest` | skala zaokrąglona i ograniczona do 0.4 do 3.0, kąt znormalizowany do (-180, 180]; WS |
| `POST /api/v1/admin/rooms/reset-positions` | `ResetPositionsRequest` | czyści `posX`, `posY`, `layout_scale`, `layout_angle` |
| `POST /api/v1/admin/rooms/reorder` | `ReorderRoomsRequest` | nadpisuje `sortOrder` wg kolejności listy |
| `GET /api/v1/admin/users` | brak | `id`, `username`, `display_name`, `role`, `room_id`, `is_active`, `created_at`, `updated_at` |
| `POST /api/v1/admin/users` | `CreateUserRequest` | `{"status":"success","id","username"}`; hash hasła, przypisanie operatora do sali, audyt |
| `PATCH /api/v1/admin/users/{user_id}` | `UpdateUserRequest` | `{"status":"success","user_id"}`, audyt |
| `POST /api/v1/admin/users/{user_id}/password-reset` | `PasswordResetRequest` | `{"status":"success","user_id","new_password"}`; usuwa wszystkie tokeny użytkownika, audyt |

Wszystkie endpointy w tej grupie wymagają roli `admin`.

### 4.6. Urządzenia IoT

| Metoda i ścieżka | Auth | Body / nagłówki | Odpowiedź i efekty |
|---|---|---|---|
| `POST /api/v1/admin/devices` | admin | `RegisterDeviceRequest` | `{"status":"success","device_id","name","token"}`, token tylko raz, audyt |
| `GET /api/v1/admin/devices` | admin | brak | `id`, `name`, `room_id`, `is_active`, `last_seen_at`, `created_at`, `updated_at` |
| `PATCH /api/v1/admin/devices/{device_id}` | admin | `UpdateDeviceRequest` | pełny wiersz urządzenia; audyt |
| `DELETE /api/v1/admin/devices/{device_id}` | admin | brak | usunięcie i wyczyszczenie `rooms.device_id`, audyt |
| `GET /api/v1/device/state` | device | `X-Firmware-Version?`, `X-Chip-Type?` | `device_id`, `room_id`, `room_name`, `status`, `server_time`, `active_session`, `firmware{chip, version, has_update, url}`; aktualizacja `last_seen_at` |
| `POST /api/v1/device/status` | device, blokada `lock_status` | `StatusChangeRequest` | `room_id`, `status`, `is_break`, `changed`, `active_session`; audyt z aktorem `device`, WS |
| `POST /api/v1/device/heartbeat` | device | brak | `{"status":"ok","server_time"}` |
| `POST` lub `PATCH /api/v1/device/alert-limit` | device lub user | `DeviceAlertLimitRequest`, query `room_id?` | `status`, `room_id`, `default_alert_limit_seconds`, `active_session`; WS |

`has_update` w `firmware` oznacza obecność pliku binarnego na serwerze, nie porównanie numerów wersji.

### 4.7. System, wersje i pliki

| Metoda i ścieżka | Odpowiedź |
|---|---|
| `GET /api/v1/health`, `GET /api/health`, `GET /api/server-info` | Trzy aliasy tej samej funkcji: `status: "ok"`, `service: "DostepnoscSal-FastAPI"`, `contract_version: "0.1"`, `time`, `lanIp`, `lanUrl` |
| `GET /api/service-info` | `status`, `service`, `contract_version`, `uptime_human`, `uptime_seconds`, `server_os`, `python_version`, `sqlite_version`, `database{path, size_formatted, total_rooms, free_rooms, occupied_rooms}`, `traffic_metrics` |
| `GET /api/app-version`, `GET /api/v1/app-version` | `versionCode`, `versionName`, `apkUrl`, `apkSize`, `releaseNotes`; dane z `server/app_version.json`, fallback `1.3.23` / 28 |
| `GET /DostepnoscSal.apk`, `GET /dostepnoscsal.apk` | plik APK, typ `application/vnd.android.package-archive` |
| `GET /DostepnoscSal_v{version}.apk` | zawsze najnowszy APK, niezależnie od `{version}` |
| `GET /api/v1/firmware/version?chip=esp32` | `chip`, `version`, `has_update`, `firmware_url`, `firmware_size`, `release_notes` |
| `GET /api/v1/cyd-version` | jw. dla `esp32`, wersja `1.3.8` |
| `GET /api/v1/esp8266-version` | jw. dla `esp8266`, wersja `1.3.6` |
| `GET /api/v1/firmware/download?chip=...`, `GET /api/v1/cyd-firmware.bin`, `GET /api/v1/esp8266-firmware.bin` | plik binarny, `application/octet-stream` |
| `GET /{full_path:path}` | plik z `build/web/`, fallback `index.html`, ostatecznie komunikat informacyjny |

Wersje firmware w kodzie źródłowym: `CYD_FIRMWARE_VERSION = "1.3.8"` w `esp32_cyd/esp32_cyd.ino` oraz stała `1.3.6` w `esp8266_d1mini/esp8266_d1mini.ino`.

---

## 5. WebSocket `/api/v1/ws`

Połączenie jest publiczne, bez autoryzacji. Koperta zdarzenia:

```json
{"type": "room.updated", "occurred_at": "2026-11-21T09:00:00Z", "data": {}}
```

| Typ zdarzenia | `data` |
|---|---|
| `room.updated` | zależnie od nadawcy: `{room_id, status, active_session}`, `{room_id, status, is_break, active_session}`, `{room_id, default_alert_limit_seconds, active_session}`, `{room_id, active_session}` albo pełna reprezentacja sali (zmiana pozycji i układu) |
| `alert.created` | `{id, room_id, session_id, triggered_at, type: "occupancy_limit_exceeded"}` |
| `clock.tick` | `{time: "2026-11-21T09:00:00Z"}`, wysyłane co 1 s tylko gdy są połączenia |
| `pong` | `{type: "pong", time}`, odpowiedź na `{"type":"ping"}` wysłaną przez klienta, bez koperty |

Klient (`lib/services/room_sync_service.dart`) subskrybuje `room.updated` i `clock.tick`, łączy się ponownie z opóźnieniem od 3 s do 60 s i ma polling jako fallback.

---

## 6. Protokół UDP auto-discovery

Serwer nasłuchuje na `0.0.0.0:8082`.

1. Klient wysyła broadcast na `255.255.255.255:8082` treść `DISCOVER_ROOM_SERVER`.
2. Serwer odpowiada unicastem na adres klienta:

```json
{
  "type": "ROOM_SERVER_ANNOUNCEMENT",
  "lanIp": "10.90.250.195",
  "port": 8081,
  "lanUrl": "http://10.90.250.195:8081"
}
```

3. Klient zapisuje `lanUrl` i weryfikuje endpoint `GET /api/v1/health`.

Uwaga: responder UDP startuje tylko przy uruchomieniu `python server/sync_server.py` (blok `__main__`), nie przy imporcie aplikacji przez serwer ASGI.

---

## 7. Znane rozjazdy w kodzie

- `DB_PATH` nie jest konfigurowalny przez zmienną środowiskową, mimo zapisu w `AGENTS.md` o testach na tymczasowej bazie.
- `lock_layout` jest zapisywany i zwracany, ale nie jest egzekwowany przez backend przy zmianie układu.
- `PATCH /api/v1/rooms/{room_id}/alert-limit` jest osiągalny anonimowo, bo `user` i `device` są zależnościami opcjonalnymi bez dalszego warunku.
- `POST /api/v1/device/alert-limit` nie sprawdza `max_alert_limit_seconds`.
- Alias `/api/v1/esp8266-firmware.bin` domyślnie przyjmuje `chip=esp32`, więc bez `?chip=esp8266` zwróci binarkę CYD.
- `traffic_metrics` w `/api/service-info` są stałymi wartościami, nie licznikami.
- Model klienta `Room` akceptuje zarówno nowe `status`, jak i starsze `isAvailable` oraz flagi `0/1/"1"`, co ułatwia migrację starych danych.
