# AGENTS.md

Język pracy: polski.

## Repozytorium

- Gałąź `main`. Autor commitów: `OverrLoss <119266256+OverrLoss@users.noreply.github.com>` lub inny kontrybutor w zależności od zalowgowanego konta lub pytaj się użytkownika przed commit.
- Zakaz dopisków o agentach/AI i znaczników `Co-authored-by` w commitach.
- Nie commituj i nie podnoś wersji dopóki człowiek nie zatwierdzi zmiany — dotyczy wszystkich zmian, szczególnie geometrii mapy i sal. Najpierw pokaż efekt (dane, API, wizualnie), poczekaj na akceptację, dopiero potem jeden commit i jedna wersja. Nie łącz wielu prób i poprawek w osobne commity/tagi.
- Po każdym podniesieniu wersji utwórz annotowany tag `vX.Y.Z` na commicie z nową wersją, wypchnij go (`git push origin --tags`) i opublikuj GitHub Release z plikiem APK jako assetem. Tagi są punktami powrotu: `git checkout vX.Y.Z`. Przed wdrożeniem sprawdź, że tag i release dla wersji istnieją.
- Wydanie wykonuj przez `release_assets.ps1 -Tag vX.Y.Z` (bez `-Notes`): notatki bierze z sekcji bieżącej wersji w `CHANGELOG.md`, wrzuca APK oraz `web_vX.Y.Z.zip` (SPA). Serwer na Proxmox pobiera oba z Release — bez tego interfejs WWW nie zaktualizuje się przy nowej wersji.
- Zmiany w ramach jednej wersji zapisuj w `CHANGELOG.md` w sekcji bieżącego numeru; przed commitem i przed wydaniem sprawdź `git log <ostatni tag>..HEAD` oraz ten plik i dopisz brakujące pozycje, także zmiany innych kontrybutorów. Nigdy nie nadpisuj istniejących wpisów ani nie zastępuj notatek Release pojedynczym opisem ostatniej zmiany. Numeru wersji nie zmieniaj bez zatwierdzenia przez człowieka.
- Sprawdzaj `git fetch --all --prune`, `git status` i `git pull --ff-only` tylko przed commitami, pushami, merge’ami i wdrożeniami — wtedy, gdy nieaktualne repo mogłoby spowodować konflikt. PR i issue sprawdzaj tylko wtedy, gdy mogą wpłynąć na wykonywaną zmianę.

## Ścieżki i domena

- Ścieżki relatywne/dynamiczne: `%~dp0`, `$PSScriptRoot`, `os.path.dirname(__file__)`, `ANDROID_HOME`/`LOCALAPPDATA`.
- Zakaz sztywnych `C:\...` i plików poza folderem projektu.
- Domena publiczna: `https://sale.pwojtaszek.5g.in` — ruch obsługuje tunel w Home Assistant (Konfiguracja poza repozytorium).
- Serwer produkcyjny działa na Proxmox (LXC 102) i jest aktualizowany automatycznie po nowym tagu/wersji.
- Nigdy nie commituj: `.cloudflared/`, tokenu, `*.apk`, `*.bin`, `*.db`, `__pycache__/`.

## Uruchamianie

- `server_control.ps1 {start|stop|restart|status}` — tylko lokalny serwer deweloperski (bez tunelu).
- Backend: `server/sync_server.py`, port `8081`, UDP `8082`, baza `server/rooms_backend.db`.
- Web SPA: `build/web/` jest serwowana przez backend — nie usuwać tego katalogu.

## Spójność wersji

- Aplikacja: `pubspec.yaml`, `lib/services/app_update_service.dart`, `lib/services/diagnostics_service.dart`, nagłówek w `lib/screens/room_main_screen.dart`, fallback w `server/sync_server.py`, monity w `server/deploy_apk.py`.
- `server/app_version.json` modyfikuj z Pythona lub przez `build_and_deploy.py`; UTF-8 bez BOM.
- Firmware CYD `1.3.8`: `CYD_FIRMWARE_VERSION` w `.ino`, `/api/v1/cyd-version`, `fw_ver` w `/api/v1/device/state`.
- Firmware ESP8266 `1.3.10`: stała w `.ino` i endpointy wersji w serwerze.
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

## Architektura wdrożenia (od 2026-11-24)

- GitHub `main` jest jedynym źródłem kodu. Kontrybutorzy edytują repozytorium; produkcji nie zmienia się ręcznie.
- Serwer produkcyjny działa na Proxmox w LXC 102, jest cały czas włączony i nasłuchuje na `8081/TCP` oraz `8082/UDP` w bridge `vmbr0`.
- Domena `https://sale.pwojtaszek.5g.in` jest obsługiwana przez tunel w Home Assistant — trasa wskazuje na adres IP LXC, port 8081. Konfiguracja tunelu i tokeny żyją poza repozytorium; do Git nie trafiają żadne dane Cloudflare.
- Auto-aktualizacja: skrypt w LXC co kilka minut sprawdza publiczny API GitHub pod kątem nowego Release. Po pojawieniu się nowego tagu pobiera archiwum kodu i APK, wdraża do `/opt/dostepnosc-sal`, restartuje usługę i sprawdza `/api/v1/health`; przy błędzie wraca do poprzedniej wersji. Nie wymaga sekretów w repo ani self-hosted runnera.
- Baza `rooms_backend.db`, pliki `*.bin` i `*.apk` pozostają lokalne na Proxmox i są wykluczone z Git.
- Podnoszenie wersji i wydawanie tagu pozostaje jedynym wyzwalaczem deployu — nie wdrażamy przy każdym commicie.
