# Historia zmian

Wpisy w sekcji bieżącej wersji opisują zmiany wprowadzone bez podnoszenia numeru wersji. Dopisuj nowe pozycje, nigdy nie usuwaj ani nie nadpisuj istniejących. Przed commitem i przed wydaniem sprawdź `git log <ostatni tag>..HEAD` i uzupełnij brakujące wpisy — także zmiany innych kontrybutorów. Notatki Release powstają z tej sekcji.

## 1.3.28

- Przywrócenie wszystkich zmian układu sal i interfejsu (mapy parteru i piętra, edycja linii sal, nowe ikony PWA) przy numerze wersji 1.3.28.
- Infrastruktura wydawania: GitHub jako źródło kodu, automatyczne wdrożenie na prywatnym serwerze po nowym Release, tunel Cloudflare poza repozytorium.
- Self-update: pobieranie APK przy każdej różnicy wersji między telefonem a serwerem, także przy wersji starszej.
- Usunięcie wewnętrznej ściany w sali 7 na parterze (`room-0-12`).
- Dokumentacja: opis infrastruktury uogólniony do prywatnego serwera z tunelem Cloudflare, bez szczegółów hostingu.
- Mapa wypełnia całą dostępną przestrzeń karty (skala wg większego wymiaru, proporcje przez FittedBox); górny limit skali podniesiony do 6.0.
- Usunięto puste marginesy płótna mapy (wysokość 520→340, przesunięcie planu 118→8); etykieta piętra przeniesiona w prawy górny róg z tłem.
- Powrót do dopasowania całego planu do okna (skala wg mniejszego wymiaru) — cała mapa jest widoczna naraz, bez przewijania.
- Identyfikacja urządzeń krótkim kodem: nowe pola `device_type`/`pair_code_hash`/`pair_code_hint`, endpointy `resolve`/`get`/`audit`/rotacji kodu i tokenu, kod w widoku TV i panelu sterowników, dashboard administratora z zakładkami (status, limity, blokady, przypisanie, token i operator, audyt). Bez kamery i nowych zależności.
- Testy kontraktu API: izolacja bazy przez `DB_PATH`, aktualizacja numerów sal po migracjach (`Aula 103_104`), zgodność oczekiwań dla gościa (`403 FORBIDDEN`) oraz nowe przypadki identyfikacji i rotacji urządzenia.
- Automatyczne przypisywanie kodu TV/kiosk przez serwer (`POST /api/v1/public/devices/claim`, `GET /public/devices/{client_id}/code`), odświeżanie kodu na wyświetlaczu po rotacji oraz wydzielony terminal administratora w nagłówku i menu; usunięto ręczne ustawianie kodu na TV.
