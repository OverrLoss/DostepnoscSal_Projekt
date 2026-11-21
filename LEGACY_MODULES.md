# Zachowane moduły poboczne

Dokument opisuje kod, który istnieje w repozytorium, ale nie jest podłączony do głównej aplikacji dostępności sal. Został zachowany świadomie na przyszłość i nie jest przeznaczony do usunięcia bez decyzji właściciela projektu.

## Stan na dziś

Jedynym punktem wejścia jest `lib/main.dart:6`. `runApp()` uruchamia `RoomAvailabilityApp` z ekranem `RoomMainScreen` (`lib/main.dart:21`). Żaden z poniższych ekranów nie jest z niego osiągalny:

| Moduł | Importujący | Dostępny z `main.dart` |
|---|---|---|
| `lib/screens/weather_home_screen.dart` | nikt | Nie |
| `lib/snake_game.dart` | nikt | Nie |
| `lib/screens/main_navigation_screen.dart` | nikt | Nie |
| `lib/screens/address_book_screen.dart` | `main_navigation_screen.dart:4` | Nie |
| `lib/screens/settings_screen.dart` | `main_navigation_screen.dart:5` | Nie |
| `lib/screens/add_edit_contact_screen.dart` | `address_book_screen.dart:8` | Nie |
| serwisy pogody i kontaktów | powyższe ekrany | Nie |

W repozytorium jest tylko jeden `void main()` i jeden `runApp()`, więc nie ma alternatywnego punktu startu. Diagnostyka (`lib/services/diagnostics_service.dart`, `lib/widgets/diagnostics_dialog.dart`) jest odwrotnie: jest osiągalna z menu `room_main_screen.dart:1496` i **nie** jest kodem pobocznym.

---

## 1. Aplikacja pogodowa

**Ekran:** `lib/screens/weather_home_screen.dart` (1080 linii).

Obsługuje:

- wyszukiwanie miasta i wybór z listy wyników, przycisk lokalizacji GPS oraz przełącznik °C / °F,
- zestaw chipów miast domyślnych i ulubionych,
- baner ostrzeżeń o burzy i ulewie,
- kartę główną z temperaturą, odczuwalną wartością, minimum i maksimum oraz ikoną warunku,
- kartę jakości powietrza AQI z PM2.5, PM10, NO2 i zaleceniem zdrowotnym,
- siatkę wilgotności, wiatru, ciśnienia i indeksu UV,
- prognozę godzinową na 24 godziny i dzienną na 7 dni,
- odświeżanie gestem `RefreshIndicator` oraz automatyczne sprawdzanie ulubionych miast w tle.

**Dane i usługi:**

- `lib/services/weather_service.dart` pobiera dane z API Open-Meteo (prognoza i jakość powietrza), wykonuje geokodowanie przez Nominatim z zapasowym BigDataCloud i ma 8 miast domyślnych. Przy błędzie sieci zwraca stałe dane offline. Danych nie cache'uje.
- `lib/models/weather_model.dart` mapuje kody WMO na opisy i ikony oraz definiuje `CityLocation`, `WeatherData`, `AirQualityData`, `HourlyForecast` i `DailyForecast`.
- `lib/services/favorites_service.dart` trzyma ulubione miasta w `SharedPreferences` pod kluczem `favorite_cities`.
- `lib/services/notification_service.dart` wysyła powiadomienia o burzy (kody 95, 96, 99), ulewie (65, 82) i smogu (AQI > 60) na kanale `storm_alerts_channel`, z uwzględnieniem uprawnień Android 13+.
- `lib/services/widget_service.dart` zapisuje `widget_city`, `widget_temp`, `widget_condition` i `widget_aqi` oraz odświeża natywny `WeatherWidgetProvider`.

**Zależności z `pubspec.yaml`:** `geolocator`, `http`, `shared_preferences`, `flutter_local_notifications`, `home_widget`.

**Ograniczenia:** GPS i API wymagają sieci oraz uprawnień lokalizacji. Powiadomienia i widget działają tylko na platformach z natywnym kanałem, na Webie błędy są po cichu ignorowane.

---

## 2. Książka adresowa

**Nawigacja:** `lib/screens/main_navigation_screen.dart` (73 linie) oferuje dwie zakładki w `IndexedStack`: Kontakty i Ustawienia, z przeładowaniem listy przy powrocie do pierwszej zakładki i reakcją na zmianę koloru akcentu.

**Ekran kontaktów:** `lib/screens/address_book_screen.dart` (1201 linii).

Obsługuje:

- wyszukiwanie, licznik i filtr kategorii (Wszystkie, Prywatny, Praca, Rodzina, Inne),
- karty kontaktów z awatarem, telefonem i adresem, odświeżanie gestem,
- dodawanie kontaktu, szczegóły w modalu, edycję awatara, edycję i usuwanie,
- import z systemowej książki adresowej z arkuszem wyboru kontaktów, filtrowaniem i wyborem kategorii.

**Formularz:** `lib/screens/add_edit_contact_screen.dart` (488 linii) zawiera pola imienia, nazwiska, telefonu, e-maila, ulicy, kodu pocztowego, miasta i notatek, wybór kategorii i awatara, walidację co najmniej jednej z nazw, zapis oraz usuwanie z potwierdzeniem.

**Ustawienia:** `lib/screens/settings_screen.dart` (442 linii) obejmują motyw (ciemny, jasny, systemowy), kolor akcentu (szmaragd, biały, fiolet, bursztyn), domyślną kategorię i sortowanie listy, statystyki bazy `address_book.db` z przyciskami „Dodaj przykłady" i „Wyczyść bazę" oraz sekcję informacyjną o aplikacji i bezpieczeństwie danych.

**Dane i usługi:**

- `lib/models/contact_model.dart` definiuje 13 pól kontaktu, getery `fullName`, `initials` i `fullAddress` oraz mapowanie SQLite i `copyWith`.
- `lib/services/database_helper.dart` prowadzi bazę `address_book.db` wersji 2 z migracją kolumny `avatar`, 3 kontaktami startowymi i operacjami CRUD, filtrowaniem po 6 polach, sortowaniem, czyszczeniem i 4 przykładami z awatarami emoji.
- `lib/services/contacts_import_service.dart` mapuje kontakty systemowe na model aplikacji i zapisuje je do SQLite.
- `lib/services/settings_service.dart` przechowuje preferencje w `SharedPreferences` i udostępnia mapowanie sortowania na klauzulę SQL.
- `lib/widgets/contact_avatar.dart` oferuje 24 gotowe awatary emoji, wybór zdjęcia z galerii lub aparatu (800 x 800, jakość 85) oraz usunięcie awatara.

**Zależności z `pubspec.yaml`:** `flutter_contacts`, `sqflite`, `path`, `shared_preferences`, `image_picker`.

**Ograniczenia:** `flutter_contacts` wymaga uprawnień do kontaktów i nie działa na Webie. `sqflite` nie ma implementacji web bez dodatkowego adaptera. `contact_avatar.dart` używa `dart:io` i `FileImage`, co wyklucza kompilację Web przy bezpośrednim imporcie. Aparat wymaga uprawnień.

---

## 3. Gra w węża

**Plik:** `lib/snake_game.dart` (790 linii), klasa `SnakeGamePage`.

Obsługuje:

- planszę 20 x 20 z trzema poziomami trudności (prędkości 220, 140 i 80 ms) i przyspieszeniem co 50 punktów,
- zwykłe jedzenie za 10 punktów oraz specjalne za 35 punktów z 20-procentową szansą i czasem życia 30 kroków,
- kolizję ze ścianą lub tryb przenikania oraz kolizję z własnym ciałem,
- rekord w pamięci procesu,
- sterowanie strzałkami, W/A/S/D i spacją oraz gestami przesuwania,
- nakładki Start, Pauza i Koniec gry, D-pad i przyciski pauzy oraz resetu.

**Dane:** brak trwałego zapisu, cały stan jest w pamięci, rekord znika po restarcie aplikacji.

**Zależności:** wyłącznie Flutter i biblioteki standardowe Dart, bez dodatkowych pakietów z `pubspec.yaml`.

---

## 4. Jeśli moduły mają wrócić do użytku

Minimalna ścieżka to podmiana `home:` w `lib/main.dart` na `MainNavigationScreen` albo dodanie osobnych tras dla pogody i gry. Trzeba jednak uwzględnić:

- ekran ustawień jest powiązany z bazą kontaktów, więc nie nadaje się bez zmian do ustawień całej aplikacji sal,
- moduły pogodowe i kontaktowe zakładają uprawnienia mobilne i natywne kanały, co wymaga osobnej wersji lub warunkowych importów dla Webu,
- diagnostyka już działa w głównej aplikacji i nie wymaga przenoszenia,
- dla kontaktów i pogody nie istnieją testy, więc przed włączeniem warto wykonać scenariusze z [`TEST_PLAN.md`](TEST_PLAN.md) rozszerzone o te moduły.
