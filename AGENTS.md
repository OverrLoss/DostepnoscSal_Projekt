# AGENTS.md

Język pracy: polski.

## Repozytorium

- Gałąź `main`. Autor commitów: `OverrLoss <119266256+OverrLoss@users.noreply.github.com>`.
- Zakaz dopisków o agentach/AI i znaczników `Co-authored-by` w commitach.
- Po każdym podniesieniu wersji utwórz annotowany tag `vX.Y.Z` na commicie z nową wersją, wypchnij go (`git push origin --tags`) i opublikuj GitHub Release z plikiem APK jako assetem. Tagi są punktami powrotu: `git checkout vX.Y.Z`. Przed wdrożeniem sprawdź, że tag i release dla wersji istnieją.
- Sprawdzaj `git fetch --all --prune`, `git status` i `git pull --ff-only` tylko przed commitami, pushami, merge’ami i wdrożeniami — wtedy, gdy nieaktualne repo mogłoby spowodować konflikt. PR i issue sprawdzaj tylko wtedy, gdy mogą wpłynąć na wykonywaną zmianę.

## Ścieżki i domena

- Ścieżki relatywne/dynamiczne: `%~dp0`, `$PSScriptRoot`, `os.path.dirname(__file__)`, `ANDROID_HOME`/`LOCALAPPDATA`.
- Zakaz sztywnych `C:\...` i plików poza folderem projektu.
- Domena: `https://sale.pwojtaszek.5g.in`. Jeden tunel: `victus`.
- Dane tunelu: `.cloudflared/victus.token` oraz `.cloudflared/cloudflared.exe` w folderze.
- Nigdy nie commituj: `.cloudflared/`, tokenu, `*.apk`, `*.bin`, `*.db`, `__pycache__/`.

## Uruchamianie

- `run_server_and_tunnel.bat` lub `server_control.ps1 {start|stop|restart|status}`.
- Backend: `server/sync_server.py`, port `8081`, UDP `8082`, baza `server/rooms_backend.db`.
- Web SPA: `build/web/` jest serwowana przez backend — nie usuwać tego katalogu.

## Spójność wersji

- Aplikacja: `pubspec.yaml`, `lib/services/app_update_service.dart`, `lib/services/diagnostics_service.dart`, nagłówek w `lib/screens/room_main_screen.dart`, fallback w `server/sync_server.py`, monity w `server/deploy_apk.py`.
- `server/app_version.json` modyfikuj z Pythona lub przez `build_and_deploy.py`; UTF-8 bez BOM.
- Firmware CYD `1.3.8`: `CYD_FIRMWARE_VERSION` w `.ino`, `/api/v1/cyd-version`, `fw_ver` w `/api/v1/device/state`.
- Firmware ESP8266 `1.3.6`: stała w `.ino` i endpointy wersji w serwerze.
- Po zmianie firmware zbuduj `arduino-cli` i podmień binarkę w `server/`; rozjazd wersji powoduje pętlę OTA.

## Modele i uprawnienia

- Status sali: `free` / `occupied`. Przerwa to `occupied` + `is_break=1`, bez sesji i timera.
- Role: admin może wszystko; operator tylko status i czas swojej sali; gość tylko podgląd.
- Blokady sali: `lock_status`, `lock_info`, `lock_layout`. Admin zawsze ma dostęp.
- Trzy sale Aula: `Aula 111`, `Aula 101_102`, `Aula 103_104`. Istniejących numerów sal nie zmieniaj bez migracji.

## Testy

- `flutter analyze`, `flutter test`, `python -m py_compile server/sync_server.py build_and_deploy.py`.
- Testy API wykonuj na tymczasowej bazie przez `DB_PATH`, nigdy na `server/rooms_backend.db`.

## Styl zmian

- Najmniejsza poprawna zmiana; reuse istniejącego kodu; bez nowych zależności.
- Komentarz tylko wtedy, gdy kod sam nie pokazuje dlaczego.
