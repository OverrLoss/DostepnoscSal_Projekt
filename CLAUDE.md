# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"Dostępność Sal" – room-availability system for Politechnika Rzeszowska: a Flutter app (Web, Android, TV/kiosk mode), a Python server with SQLite, and ESP8266/ESP32 firmware (`esp8266_d1mini/`, `esp32_cyd/`) that shows room status on LEDs. Docs are in Polish.

## Commands

```bash
flutter pub get
flutter run -d chrome            # or -d <android-device-id>
flutter analyze                  # rules in analysis_options.yaml
flutter test                     # only test/widget_test.dart exists
flutter test test/widget_test.dart

python server/sync_server.py     # API + static web on :8081, UDP beacon on :8082
python server/test_contract.py   # API contract tests (unittest, API-01..API-20); runs against the real init_db() DB

flutter build web --release      # output build/web, served by sync_server.py at /
flutter build apk --release
python build_and_deploy.py [--web-only|--apk-only|--skip-build]  # build + copy APK to server/, build/web/ + update server/app_version.json
```

Windows helpers: `PRZYGOTUJ_KOMPUTER.bat` (one-time setup), `run_server_and_tunnel.bat` (server + Cloudflare tunnel in background).

## Architecture

- **Server** (`server/sync_server.py`, single ~2000-line file): FastAPI + uvicorn (needs `pip install fastapi uvicorn pydantic`; there is no requirements.txt). Handles token auth (`/api/v1/auth/login`, bearer tokens, admin/operator users), the rooms REST API, static serving of `build/web`, `/api/app-version` for OTA, and a UDP beacon thread on 8082. SQLite file `server/rooms_backend.db` is created and seeded by `init_db()`.
- **Client sync**: `lib/services/room_sync_service.dart` polls/syncs with the server and caches; `room_database_helper.dart` is local SQLite on Android with an in-memory fallback on Web. `services/discovery/` uses conditional imports (`_io` vs `_web` stub) – UDP discovery sends `DISCOVER_ROOM_SERVER` broadcast and the server replies with its LAN IP.
- **Floor map**: `widgets/interactive_floor_map.dart` draws the building with `CustomPainter`; room positions are `posX`/`posY` stored per room in the DB (edit mode drags and persists them). Querying `floor=Parter` intentionally also returns the "Garaż" room (underground floor shown in the ground-floor courtyard).
- **TV mode**: `screens/tv_dashboard_screen.dart`, polls every 3 s.
- **Remote access**: Cloudflare tunnel to localhost:8081 (`cloudflare_config_sample.yml`).

## Gotchas

- **Docs are partly stale.** `README.md`, `AI_CODEBASE_SUMMARY.md` and `DEVELOPER_GUIDE.md` say v1.2.0 and "stdlib-only Python, no pip install", but `pubspec.yaml` is `1.3.6+11` and the server uses FastAPI. Trust the code; `API_REFERENCE.md` may also lag the `/api/v1/...` routes.
- **Version bump** must be done in `pubspec.yaml` and the server's app-version data (`server/app_version.json`, also written by `build_and_deploy.py`); OTA works by comparing `versionCode` (`remoteCode > localCode`).
- `test_contract.py` logs in with seeded default credentials (admin / operator_104); those accounts must exist after `init_db()`.

## Sale a rzut z SVG

- Piętro i Parter rysują się z `lib/widgets/floor1_plan.dart` / `floor0_plan.dart` (wielokąty `room-X-YY` z SVG, bez numerów sal). Numery sal są na sztywno przypisane do pokoi w `_buildPietroRooms` / `_buildParterRooms` (`interactive_floor_map.dart`), część orientacyjnie.
- Nowe sale można przylepić do wolnego pokoju z SVG w formularzu dodawania/edycji (pole `svg_id` w modelu, bazie lokalnej i serwerze). Sala z `svg_id` rysuje się jako kształt pokoju; bez niego jako zwykły blok. Pokoje zajęte na stałe są w `_fixedSvgIds`.
- Znane braki: kilka kształtów (aule `room-1-20/24/38`) dzieli jedną salę AULA, bo w bazie nie ma osobnych rekordów; sale przylepione do SVG nie są przeciągane w trybie edycji.
