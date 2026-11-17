# ESP32 Cheap Yellow Display (CYD) - Zaawansowany Terminal Sal

Program dla modułu **ESP32-2432S028R** (Cheap Yellow Display / CYD) z 2.8-calowym ekranem dotykowym 320x240, kartą MicroSD 32GB, diodą RGB oraz łącznością Wi-Fi z serwerem **FastAPI (Kontrakt v0.1)**.

---

## 🌟 Co zawiera ten program?

1. **Połączona Propozycja 1 i 2 (Widok Główny Terminala)**:
   - Duża, czytelna karta stanu sali: **WOLNA** (szmaragd) / **ZAJĘTA** (czerwień) / **ALERT** (bursztyn/żółty).
   - Licznik czasu trwania sesji na żywo (`mm:ss min`).
   - Dotykowe kafelki szybkiego wyboru limitu sesji: `[ 15m ]`, `[ 30m ]`, `[ 45m ]`, `[ 60m ]` oraz `[ +10m ]` (przedłużenie aktywnej sesji).
   - Duży dotykowy przycisk na dole ekranu: `[ ZAJMIJ SALĘ ]` / `[ ZWOLNIJ SALĘ ]`.
   - Zegar `HH:MM` w prawym górnym rogu (czas serwera, NTP jako zapas). Kolor przycisku Wi-Fi nadal oznacza stan połączenia.

2. **Propozycja 3: Przegląd Wolnych Sal w Budynku**:
   - Kliknięcie przycisku `[ WOLNE ]` na pasku górnym przełącza terminal w widok kiosku.
   - Wyświetla siatkę kafelków pokazującą **wyłącznie aktualnie wolne sale** (pobierane na żywo z serwera).
   - Obsługa paginacji (`< Poprz` / `Nast >`), powrót jednym dotknięciem.

3. **Dotykowy Konfigurator Wi-Fi na Ekranie**:
   - Kliknięcie `[ Wi-Fi ]` uruchamia graficzny skaner sieci 2.4 GHz.
   - Lista wykrytych sieci z siłą sygnału w dBm i oznaczeniem zabezpieczenia (`[Zab.]` / `[Otwarta]`).
   - **Pełna ekranowa klawiatura dotykowa QWERTY**: wpisz hasło palcem na ekranie CYD i połącz się bez potrzeby wgrywania kodu od nowa!
   - Hasło i SSID zapisują się automatycznie w pamięci NVS oraz na karcie SD.

4. **Obsługa Karty MicroSD 32GB**:
   - Płytka automatycznie wykrywa i montuje kartę 32GB na dedykowanej magistrali SPI (piny CS: 5, MOSI: 23, MISO: 19, SCK: 18).
   - Konfiguracja w pliku `/dostepnosc_sal/config.json` (możesz edytować ustawienia także na komputerze).
   - Dziennik zdarzeń w pliku `/dostepnosc_sal/events.log` (historia zajęcia, zwolnienia sal, alertów).

5. **Zdalna Automatyczna Aktualizacja (Auto-OTA over Wi-Fi)**:
   - **Automatyczny Update w Tle**: Za każdym razem po połączeniu z Wi-Fi oraz cyklicznie co 5 minut w tle urządzenie odpytuje endpoint `https://sale.pwojtaszek.codes/api/v1/cyd-version`.
   - **Samoczynne Pobranie i Wgranie**: Jeśli na serwerze pojawi się nowsza wersja firmware (np. po kompilacji nowego pliku `.bin`), CYD przełącza się w widok aktualizacji, wyświetla graficzny pasek postępu (0-100%), wgrywa nowy kod do pamięci Flash i samoczynnie się restartuje.
   - **ArduinoOTA**: Dodatkowo urządzenie rozgłasza się w sieci lokalnej jako `cyd-sala-104` (hasło: `admin123`) dla bezpośredniego flashowania z Arduino IDE bez kabla USB.

---

## 🛠️ Wymagane biblioteki w Arduino IDE

Zainstalowane i skonfigurowane w systemie:
1. **`TFT_eSPI`** (autor: Bodmer, prekonfigurowana pod CYD ILI9341 320x240)
2. **`XPT2046_Touchscreen`** (autor: Paul Stoffregen, obsługa dotyku po SPI)
3. **`ArduinoJson`** (autor: Benoit Blanchon, wersja 7.x)

---

## ⚙️ Konfiguracja pliku `User_Setup.h`

Plik w folderze `Dokumenty/Arduino/libraries/TFT_eSPI/User_Setup.h` został już automatycznie podmieniony i skonfigurowany pod piny CYD:
- ILI9341_2_DRIVER, MOSI: 13, MISO: 12, SCLK: 14, CS: 15, DC: 2, BL: 21, 40 MHz SPI.

---

## 🚀 Ustawienia wgrywania i partycjonowania

- **Płytka**: `ESP32 Dev Module` (`esp32:esp32:esp32`)
- **Port**: `COM4` (USB-SERIAL CH340)
- **Partition Scheme**: `Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)` (`PartitionScheme=min_spiffs`)
- **Upload Speed**: `921600`

### Jak zaktualizować oprogramowanie na serwerze (dla wszystkich urządzeń CYD):
1. Dokonaj zmian w kodzie `esp32_cyd.ino` i zwiększ stałą `CYD_FIRMWARE_VERSION` (np. na `"1.3.7"`).
2. Skompiluj binarkę:
   ```powershell
   arduino-cli compile --export-binaries --fqbn "esp32:esp32:esp32:PartitionScheme=min_spiffs" "esp32_cyd\esp32_cyd.ino"
   ```
3. Skopiuj wygenerowany plik `esp32_cyd\build\esp32.esp32.esp32\esp32_cyd.ino.bin` do `server\cyd_firmware.bin`.
4. Zmień wersję w `sync_server.py` w obu miejscach: `get_firmware_version()` (`version = "1.3.7"`) oraz `get_device_assigned_room_state()` (`fw_ver = "1.3.7"`). Różnica wersji między tymi miejscami a `.ino` powoduje ciągłe restarty OTA.
5. Wszystkie urządzenia CYD w budynku połączone z Wi-Fi w ciągu 5 minut automatycznie pobiorą nowy firmware i zaktualizują się same bez dotykania kabla!
