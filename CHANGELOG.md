# Historia zmian

Wpisy w sekcji bieżącej wersji opisują zmiany wprowadzone bez podnoszenia numeru wersji. Dopisuj nowe pozycje, nigdy nie usuwaj ani nie nadpisuj istniejących. Przed commitem i przed wydaniem sprawdź `git log <ostatni tag>..HEAD` i uzupełnij brakujące wpisy — także zmiany innych kontrybutorów. Notatki Release powstają z tej sekcji.

## 1.3.28

- Przywrócenie wszystkich zmian układu sal i interfejsu (mapy parteru i piętra, edycja linii sal, nowe ikony PWA) przy numerze wersji 1.3.28.
- Infrastruktura wydawania: GitHub jako źródło kodu, Proxmox LXC 102 z automatycznym wdrożeniem po nowym Release, tunel HA poza repozytorium.
- Self-update: pobieranie APK przy każdej różnicy wersji między telefonem a serwerem, także przy wersji starszej.
- Usunięcie wewnętrznej ściany w sali 7 na parterze (`room-0-12`).
