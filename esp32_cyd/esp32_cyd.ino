/*
 * ============================================================================
 * Politechnika Rzeszowska - System Dostępności Sal
 * Zaawansowany Sterownik ESP32 Cheap Yellow Display (CYD) / ESP32-2432S028R
 * ============================================================================
 * 
 * FUNKCJE SYSTEMU:
 * 1. POŁĄCZENIE PROPOZYCJI 1 I 2 (Widok Główny):
 *    - Wielki wskaźnik stanu sali (WOLNA / ZAJĘTA / ALERT).
 *    - Licznik czasu sesji na żywo.
 *    - Dotykowe kafelki szybkiego limitu sesji: [15 min], [30 min], [45 min], [60 min] oraz [+10 min].
 *    - Duży dotykowy przycisk zmiany stanu sali.
 * 2. PROPOZYCJA 3 (Widok Wszystkich Wolnych Sal):
 *    - Przycisk [Wolne Sale] w nagłówku.
 *    - Siatka kafelków pokazująca TYLKO aktualnie wolne sale w budynku PRz.
 * 3. DOTYKOWY PANEL KONFIGURACJI WI-FI NA EKRANIE:
 *    - Automatyczny skaner pasma 2.4 GHz z siłą sygnału i kłódkami.
 *    - Pełna klawiatura dotykowa QWERTY na ekranie do wpisania hasła.
 *    - Trwały zapis konfiguracji w pamięci NVS (Preferences) oraz na karcie SD.
 * 4. OBSŁUGA KARTY MICROSD 32GB:
 *    - Rejestracja zdarzeń w /dostepnosc_sal/events.log.
 *    - Odczyt/zapis konfiguracji /dostepnosc_sal/config.json.
 * 5. ZDALNA AKTUALIZACJA (OTA):
 *    - Bezprzewodowe programowanie przez ArduinoOTA z Arduino IDE.
 *    - Automatyczna aktualizacja HTTP OTA z serwera FastAPI (/api/v1/cyd-firmware.bin).
 * ============================================================================
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoOTA.h>
#include <Update.h>
#include <Preferences.h>
#include <SPI.h>
#include <FS.h>
#include <SD.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include <ArduinoJson.h>
#include <time.h>
#include <sys/time.h>
#include <vector>
#include <algorithm>

// --- PINOUT CYD (ESP32-2432S028R) ---
#define XPT2046_IRQ   36
#define XPT2046_MOSI  32
#define XPT2046_MISO  39
#define XPT2046_CLK   25
#define XPT2046_CS    33

#define CYD_LED_RED   4
#define CYD_LED_GREEN 16
#define CYD_LED_BLUE  17
#define TFT_BL_PIN    21

#define SD_CS         5
#define SD_MOSI       23
#define SD_MISO       19
#define SD_SCK        18

// Kalibracja dotyku
#define TS_MINX 250
#define TS_MAXX 3800
#define TS_MINY 300
#define TS_MAXY 3800

// Inicjalizacja magistral SPI
SPIClass touchSPI(VSPI);
SPIClass sdSPI(HSPI);
XPT2046_Touchscreen ts(XPT2046_CS, XPT2046_IRQ);
TFT_eSPI tft = TFT_eSPI();
Preferences prefs;

// Paleta barw UI o wysokim kontraście (RGB565)
#define COLOR_BG          0x0000 // Głęboka czerń / granat (TFT_BLACK)
#define COLOR_PANEL       0x18E7 // Ciemny panel #1E293B
#define COLOR_CARD_FREE   0x03E0 // Ciemnozielony panel #064E3B
#define COLOR_CARD_OCC    0x7800 // Ciemnoczerwony panel #7F1D1D
#define COLOR_CARD_ALERT  0x7A00 // Bordowo-bursztynowy
#define COLOR_FREE_GREEN  0x07E0 // Jaskrawa, soczysta zieleń #10B981
#define COLOR_OCC_RED     0xF800 // Jaskrawa czerwień #EF4444
#define COLOR_ALERT_AMBER 0xFDA0 // Jaskrawy bursztyn / złoty #F59E0B
#define COLOR_TEXT_WHITE  0xFFFF // Czysta biel
#define COLOR_TEXT_MUTED  0xDEFB // Jasnosrebrny o maksymalnym kontraście
#define COLOR_PRZ_ORANGE  0xFD20 // Pomarańcz PRz #FF7A00
#define COLOR_BTN_BG      0x298C

// --- TRYBY EKRANU ---
enum ScreenMode {
  SCREEN_MAIN,        // Połączona tabliczka przydrzwiowa + panel sesji z timerem
  SCREEN_FREE_ROOMS,  // Widok wszystkich wolnych sal w budynku
  SCREEN_WIFI_LIST,   // Lista wykrytych sieci Wi-Fi do wyboru
  SCREEN_WIFI_KEYBOARD, // Klawiatura ekranowa do hasła Wi-Fi
  SCREEN_OTA_PROGRESS // Pasek postępu aktualizacji
};

ScreenMode currentScreen = SCREEN_MAIN;

// --- DANE WERSJI I AKTUALIZACJI OTA ---
const char* CYD_FIRMWARE_VERSION = "1.3.7";
bool isDisplayInverted = true;
unsigned long lastOtaCheck = 0;
const unsigned long OTA_CHECK_INTERVAL = 300000; // Sprawdzaj co 5 minut w tle (300 s)

// --- ZEGAR: czas z serwera (ISO UTC), NTP jako zapas ---
static bool applyServerTime(const String& isoUtc) {
  int y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
  if (sscanf(isoUtc.c_str(), "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &s) != 6) return false;
  if (y < 2000 || mo < 1 || mo > 12 || d < 1 || d > 31) return false;
  struct tm t = {};
  t.tm_year = y - 1900; t.tm_mon = mo - 1; t.tm_mday = d;
  t.tm_hour = h; t.tm_min = mi; t.tm_sec = s;
  setenv("TZ", "UTC0", 1); tzset();
  time_t epoch = mktime(&t);
  setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1); tzset();
  struct timeval tv = { epoch, 0 };
  settimeofday(&tv, NULL);
  return true;
}

static String currentClockText() {
  struct tm ti;
  if (!getLocalTime(&ti)) return "--:--";
  char buf[6];
  snprintf(buf, sizeof(buf), "%02d:%02d", ti.tm_hour, ti.tm_min);
  return String(buf);
}

// --- DANE KONFIGURACYJNE (NVS + SD) ---
String wifiSsid = "TWOJA_NAZWA_WIFI";
String wifiPassword = "TWOJE_HASLO_WIFI";
String serverUrl = "https://sale.pwojtaszek.codes";
String deviceToken = "dev_token_sala104";
String roomNumber = "104";
String roomName = "Gwiezdne Wojny";

// --- STAN SALI ---
bool isAvailable = true;
bool isAlertDue = false;
int durationSeconds = 0;
int selectedAlertLimit = 900; // 15 minut domyślnie
unsigned long lastServerSync = 0;
const unsigned long SYNC_INTERVAL = 3000;
unsigned long lastTimerTick = 0;
unsigned long lastTouchDebounce = 0;
bool sdCardAvailable = false;
const unsigned long FREE_ROOMS_REFRESH_INTERVAL = 5000; // Odświeżanie listy wolnych sal co 5s

// --- DANE DLA EKRANU WOLNYCH SAL ---
struct FreeRoomInfo {
  String number;
  String name;
  String floor;
  int capacity;
};
std::vector<FreeRoomInfo> freeRoomsList;
int freeRoomsPage = 0;
const int ROOMS_PER_PAGE = 6;
int lastFreeRoomsCount = -1;       // -1 = nie pobrano jeszcze
unsigned long lastFreeRoomsSync = 0; // Czas ostatniego pobrania listy wolnych sal

// --- DANE DLA SIECI WI-FI (HISTORIA I SKANER) ---
struct SavedNetwork {
  String ssid;
  String pass;
};
std::vector<SavedNetwork> savedNetworks;

struct WifiNetworkInfo {
  String ssid;
  int rssi;
  bool isEncrypted;
};
std::vector<WifiNetworkInfo> scannedNetworks;
String selectedNetworkSsid = "";
String enteredWifiPassword = "";
int wifiListPage = 0;

// --- DEKLARACJE ---
void loadSettings();
void saveSettings();
void loadSavedNetworks();
void addOrUpdateSavedNetwork(const String& ssid, const String& pass);
bool isNetworkSaved(const String& ssid, String* outPass = nullptr);
void connectWithCredentials(const String& ssid, const String& pass);
void connectToBestSavedWifi();
void logEvent(const String& event);
void setRgbLed(bool r, bool g, bool b);
void updateLeds();
void drawCurrentScreen();
void drawMainScreen();
void drawFreeRoomsScreen();
void drawWifiListScreen();
void drawWifiKeyboardScreen();
void handleTouch();
void syncServerState();
void sendStatusChange(bool makeFree);
void sendAlertLimit(int seconds);
void fetchFreeRooms();
void scanWifiNetworks();
void checkForFirmwareUpdate();
void startOtaUpdate(const String& firmwareUrl);
void drawOtaProgressScreen(int percent, const String& statusText);
String formatDuration(int totalSecs);

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\n[CYD] Start Zaawansowanego Panelu Dostepnosci Sal...");

  // Zegar: NTP uzupelnia czas, gdy serwer jeszcze nie odpowiedzial
  setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);
  tzset();
  configTime(0, 0, "pool.ntp.org", "time.google.com");

  // Podświetlenie i Dioda RGB
  pinMode(TFT_BL_PIN, OUTPUT);
  digitalWrite(TFT_BL_PIN, HIGH);
  pinMode(CYD_LED_RED, OUTPUT);
  pinMode(CYD_LED_GREEN, OUTPUT);
  pinMode(CYD_LED_BLUE, OUTPUT);
  setRgbLed(false, false, true); // Niebieski podczas startu

  // Inicjalizacja magistral i karty SD 32GB
  sdSPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  if (SD.begin(SD_CS, sdSPI)) {
    sdCardAvailable = true;
    Serial.println("[SD] Karta 32GB zamontowana pomyslnie!");
    if (!SD.exists("/dostepnosc_sal")) {
      SD.mkdir("/dostepnosc_sal");
    }
  } else {
    Serial.println("[SD] Karta SD nie wykryta (uzywanie pamieci NVS)");
  }

  // Odczyt ustawień (w tym trybu inwersji ekranu)
  loadSettings();

  // Inicjalizacja ekranu i korekta inwersji kolorów dla matrycy CYD
  tft.init();
  tft.invertDisplay(isDisplayInverted);
  tft.setRotation(1);
  tft.fillScreen(COLOR_BG);

  // Inicjalizacja dotyku
  touchSPI.begin(XPT2046_CLK, XPT2046_MISO, XPT2046_MOSI, XPT2046_CS);
  ts.begin(touchSPI);
  ts.setRotation(1);

  // Ekran startowy
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_BG);
  tft.drawCentreString("POLITECHNIKA RZESZOWSKA", 160, 45, 4);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BG);
  tft.drawCentreString("Terminal CYD Sala " + roomNumber, 160, 85, 4);
  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
  tft.drawCentreString("Wyszukiwanie znanych sieci Wi-Fi...", 160, 140, 2);

  // Wczytanie historii zapamiętanych sieci i połączenie z najlepszą
  loadSavedNetworks();
  connectToBestSavedWifi();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] Polaczono! IP: " + WiFi.localIP().toString());
    logEvent("SYSTEM: Polaczono z Wi-Fi " + wifiSsid + " (IP: " + WiFi.localIP().toString() + ")");

    // Konfiguracja ArduinoOTA do aktualizacji bezprzewodowej
    ArduinoOTA.setHostname(("cyd-sala-" + roomNumber).c_str());
    ArduinoOTA.setPassword("admin123");
    ArduinoOTA.begin();

    // Sprawdzenie i wykonanie automatycznej aktualizacji firmware (Auto-OTA)
    checkForFirmwareUpdate();
  } else {
    Serial.println("\n[WiFi] Brak polaczenia z zadna znana siecia.");
  }

  // Pobranie stanu i narysowanie UI
  syncServerState();
  drawCurrentScreen();
}

// ============================================================================
// PĘTLA GŁÓWNA (LOOP)
// ============================================================================
void loop() {
  // Obsługa ArduinoOTA
  if (WiFi.status() == WL_CONNECTED) {
    ArduinoOTA.handle();
  }

  // Obsługa dotyku
  handleTouch();

  // Licznik sesji w tle (odświeżanie co pełną minutę lub przy zmianie alertu - bez migotania ekranu)
  if (millis() - lastTimerTick >= 1000) {
    lastTimerTick = millis();
    if (!isAvailable) {
      int prevMinutes = durationSeconds / 60;
      bool prevAlert = isAlertDue;
      durationSeconds++;
      if (durationSeconds >= selectedAlertLimit) {
        isAlertDue = true;
      }
      int curMinutes = durationSeconds / 60;
      if (currentScreen == SCREEN_MAIN && (curMinutes != prevMinutes || isAlertDue != prevAlert)) {
        drawMainScreen();
      }
    }
  }

  // Synchronizacja z serwerem co 3 sekundy
  if (millis() - lastServerSync >= SYNC_INTERVAL) {
    lastServerSync = millis();
    syncServerState();
  }

  // Gdy aktywny ekran to WOLNE SALE: odświeżaj listę automatycznie co 5 sekund
  if (currentScreen == SCREEN_FREE_ROOMS &&
      millis() - lastFreeRoomsSync >= FREE_ROOMS_REFRESH_INTERVAL) {
    lastFreeRoomsSync = millis();
    fetchFreeRooms();
    drawFreeRoomsScreen();
  }

  // Sprawdzanie aktualizacji Auto-OTA w tle co 5 minut
  if (millis() - lastOtaCheck >= OTA_CHECK_INTERVAL) {
    lastOtaCheck = millis();
    checkForFirmwareUpdate();
  }
}

// ============================================================================
// OBSŁUGA DOTYKU DLA KAŻDEGO EKRANU
// ============================================================================
void handleTouch() {
  if (!ts.touched()) return;

  TS_Point p = ts.getPoint();
  if (millis() - lastTouchDebounce < 350) return;

  int x = map(p.x, TS_MINX, TS_MAXX, 0, 320);
  int y = map(p.y, TS_MINY, TS_MAXY, 0, 240);
  x = constrain(x, 0, 320);
  y = constrain(y, 0, 240);

  lastTouchDebounce = millis();

  // --- EKRAN 1: WIDOK GŁÓWNY (SALA + TIMER) ---
  if (currentScreen == SCREEN_MAIN) {
    // Dotknięcie logo PRz (x: 0..52, y: 0..34) przełącza inwersję kolorów na żywo
    if (x <= 52 && y <= 34) {
      isDisplayInverted = !isDisplayInverted;
      tft.invertDisplay(isDisplayInverted);
      saveSettings();
      logEvent("INWERSJA: Zmiana trybu na " + String(isDisplayInverted ? "WL" : "WYL"));
      drawCurrentScreen();
      return;
    }

    // Przycisk "Wolne Sale" w nagłówku (x: 170..240, y: 0..40)
    if (x >= 170 && x <= 240 && y <= 40) {
      fetchFreeRooms();
      lastFreeRoomsSync = millis(); // Reset timera — następne auto-odświeżenie za 5s
      currentScreen = SCREEN_FREE_ROOMS;
      drawCurrentScreen();
      return;
    }

    // Przycisk "Wi-Fi" w nagłówku (x: 242..318, y: 0..40)
    if (x >= 242 && x <= 318 && y <= 40) {
      currentScreen = SCREEN_WIFI_LIST;
      drawCurrentScreen();
      // Jeśli brak połączenia z Wi-Fi LUB brak wyników skanowania: od razu skanuj!
      if (WiFi.status() != WL_CONNECTED || scannedNetworks.empty()) {
        scanWifiNetworks();
        drawWifiListScreen();
      }
      return;
    }

    // Kafelki wyboru limitu sesji: [15m], [30m], [45m], [60m], [+10m]
    // Obszar: Y od 130 do 175
    if (y >= 130 && y <= 175) {
      if (x >= 10 && x <= 68) {
        sendAlertLimit(900); // 15 min
      } else if (x >= 70 && x <= 127) {
        sendAlertLimit(1800); // 30 min
      } else if (x >= 129 && x <= 186) {
        sendAlertLimit(2700); // 45 min
      } else if (x >= 188 && x <= 245) {
        sendAlertLimit(3600); // 60 min
      } else if (x >= 248 && x <= 310 && !isAvailable) {
        sendAlertLimit(selectedAlertLimit + 600); // +10 min
      }
      return;
    }

    // Duży dolny przycisk zmiany stanu: ZAJMIJ / ZWOLNIJ (Y: 176..236, X: 10..310)
    if (y >= 176 && y <= 236 && x >= 10 && x <= 310) {
      tft.drawRoundRect(12, 178, 296, 54, 12, COLOR_TEXT_WHITE);
      delay(80);
      sendStatusChange(!isAvailable);
      return;
    }
  }

  // --- EKRAN 2: WIDOK WOLNYCH SAL ---
  else if (currentScreen == SCREEN_FREE_ROOMS) {
    // Przycisk "Powrót" w nagłówku (x: 240..315, y: 0..32)
    if (x >= 240 && y <= 32) {
      currentScreen = SCREEN_MAIN;
      drawCurrentScreen();
      return;
    }

    // Przycisk "Odśwież" (x: 170..235, y: 0..32)
    if (x >= 170 && x <= 235 && y <= 32) {
      fetchFreeRooms();
      lastFreeRoomsSync = millis(); // Reset timera po ręcznym odświeżeniu
      drawFreeRoomsScreen();
      return;
    }

    // Paginacja: Poprzednia strona (x: 20..100, y: 206..236)
    if (y >= 206 && x >= 20 && x <= 100 && freeRoomsPage > 0) {
      freeRoomsPage--;
      drawFreeRoomsScreen();
      return;
    }

    // Paginacja: Następna strona (x: 220..300, y: 206..236)
    int maxPages = (freeRoomsList.size() + ROOMS_PER_PAGE - 1) / ROOMS_PER_PAGE;
    if (y >= 206 && x >= 220 && x <= 300 && (freeRoomsPage + 1) < maxPages) {
      freeRoomsPage++;
      drawFreeRoomsScreen();
      return;
    }
  }

  // --- EKRAN 3: LISTA SIECI WI-FI ---
  else if (currentScreen == SCREEN_WIFI_LIST) {
    // Powrót "< WROC" (x: 236..318, y: 0..42)
    if (x >= 236 && y <= 42) {
      currentScreen = SCREEN_MAIN;
      drawCurrentScreen();
      return;
    }

    // Skanuj ponownie "SKANUJ" (x: 150..235, y: 0..42)
    if (x >= 150 && x < 235 && y <= 42) {
      scanWifiNetworks();
      drawWifiListScreen();
      return;
    }

    // Kliknięcie w jedną z 4 sieci na liście (Y: 40..80, 82..122, 124..164, 166..204)
    int startY = 40;
    int itemH = 38;
    for (int i = 0; i < 4; i++) {
      int itemIndex = wifiListPage * 4 + i;
      if (itemIndex < (int)scannedNetworks.size()) {
        int rowY = startY + i * (itemH + 4);
        if (y >= rowY && y <= (rowY + itemH) && x >= 10 && x <= 310) {
          selectedNetworkSsid = scannedNetworks[itemIndex].ssid;
          String savedPass = "";
          // Jeśli sieć jest już w historii zapamiętanych: łącz od razu!
          if (isNetworkSaved(selectedNetworkSsid, &savedPass)) {
            connectWithCredentials(selectedNetworkSsid, savedPass);
            return;
          } else {
            // Nowa sieć - przejdź do wpisania hasła na klawiaturze
            enteredWifiPassword = "";
            currentScreen = SCREEN_WIFI_KEYBOARD;
            drawCurrentScreen();
            return;
          }
        }
      }
    }

    // Paginacja sieci Wi-Fi (Y: 204..240)
    int maxWifiPages = (scannedNetworks.size() + 3) / 4;
    if (y >= 204 && y <= 240 && maxWifiPages > 1) {
      if (x >= 14 && x <= 95 && wifiListPage > 0) {
        wifiListPage--;
        drawWifiListScreen();
        return;
      }
      if (x >= 225 && x <= 306 && (wifiListPage + 1) < maxWifiPages) {
        wifiListPage++;
        drawWifiListScreen();
        return;
      }
    }
  }

  // --- EKRAN 4: KLAWIATURA DOTYKOWA HASŁA WI-FI ---
  else if (currentScreen == SCREEN_WIFI_KEYBOARD) {
    // Anuluj (x: 240..315, y: 0..30)
    if (x >= 240 && y <= 30) {
      currentScreen = SCREEN_WIFI_LIST;
      drawCurrentScreen();
      return;
    }

    // Dotknięcie klawisza na wirtualnej klawiaturze
    // Klawiatura zaczyna się od Y: 75
    if (y >= 75 && y <= 235) {
      // Wiersz 1: 1 2 3 4 5 6 7 8 9 0 (Y: 75..110)
      if (y >= 75 && y <= 110) {
        int keyIndex = x / 32;
        if (keyIndex < 10) {
          const char digits[] = "1234567890";
          enteredWifiPassword += digits[keyIndex];
          drawWifiKeyboardScreen();
        }
      }
      // Wiersz 2: Q W E R T Y U I O P (Y: 114..148)
      else if (y >= 114 && y <= 148) {
        int keyIndex = x / 32;
        if (keyIndex < 10) {
          const char row2[] = "qwertyuiop";
          enteredWifiPassword += row2[keyIndex];
          drawWifiKeyboardScreen();
        }
      }
      // Wiersz 3: A S D F G H J K L DEL (Y: 152..186)
      else if (y >= 152 && y <= 186) {
        if (x >= 270) {
          // DEL (Backspace)
          if (enteredWifiPassword.length() > 0) {
            enteredWifiPassword.remove(enteredWifiPassword.length() - 1);
            drawWifiKeyboardScreen();
          }
        } else {
          int keyIndex = x / 30;
          if (keyIndex < 9) {
            const char row3[] = "asdfghjkl";
            enteredWifiPassword += row3[keyIndex];
            drawWifiKeyboardScreen();
          }
        }
      }
      // Wiersz 4: Z X C V B N M [ SPACJA ] [ POŁĄCZ ] (Y: 190..235)
      else if (y >= 190 && y <= 235) {
        if (x >= 220) {
          // PRZYCISK POŁĄCZ
          tft.fillRect(20, 20, 280, 200, COLOR_BG);
          tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_BG);
          tft.drawCentreString("Laczenie z siecia...", 160, 90, 4);
          tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BG);
          tft.drawCentreString(selectedNetworkSsid, 160, 130, 2);

          WiFi.disconnect();
          WiFi.begin(selectedNetworkSsid.c_str(), enteredWifiPassword.c_str());
          int tries = 0;
          while (WiFi.status() != WL_CONNECTED && tries < 20) {
            delay(350);
            tries++;
          }

          if (WiFi.status() == WL_CONNECTED) {
            wifiSsid = selectedNetworkSsid;
            wifiPassword = enteredWifiPassword;
            saveSettings();
            addOrUpdateSavedNetwork(selectedNetworkSsid, enteredWifiPassword);
            logEvent("Wi-Fi zmienione i zapamietane: " + wifiSsid);
            currentScreen = SCREEN_MAIN;
            drawCurrentScreen();
            checkForFirmwareUpdate();
          } else {
            tft.setTextColor(COLOR_OCC_RED, COLOR_BG);
            tft.drawCentreString("Nieudane polaczenie!", 160, 160, 2);
            delay(1500);
            drawWifiKeyboardScreen();
          }
        } else if (x >= 140 && x < 215) {
          // SPACJA
          enteredWifiPassword += " ";
          drawWifiKeyboardScreen();
        } else {
          // Z X C V B N M
          int keyIndex = x / 20;
          if (keyIndex < 7) {
            const char row4[] = "zxcvbnm";
            enteredWifiPassword += row4[keyIndex];
            drawWifiKeyboardScreen();
          }
        }
      }
    }
  }
}

// ============================================================================
// RENDEROWANIE EKRANÓW
// ============================================================================
void drawCurrentScreen() {
  tft.fillScreen(COLOR_BG);
  switch (currentScreen) {
    case SCREEN_MAIN:
      drawMainScreen();
      break;
    case SCREEN_FREE_ROOMS:
      drawFreeRoomsScreen();
      break;
    case SCREEN_WIFI_LIST:
      drawWifiListScreen();
      break;
    case SCREEN_WIFI_KEYBOARD:
      drawWifiKeyboardScreen();
      break;
    case SCREEN_OTA_PROGRESS:
      drawOtaProgressScreen(0, "Oczekiwanie na pobieranie...");
      break;
  }
  updateLeds();
}

// ----------------------------------------------------------------------------
// EKRAN 1: WIDOK GŁÓWNY (TABLICZKA + PANEL TIMERÓW)
// ----------------------------------------------------------------------------
void drawMainScreen() {
  // Pasek górny (34px)
  tft.fillRect(0, 0, 320, 34, COLOR_PANEL);
  tft.drawFastHLine(0, 34, 320, COLOR_PRZ_ORANGE);

  // Logo PRz (dotknięcie przełącza inwersję barw ekranu)
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_PANEL);
  tft.drawString("PRz", 8, 6, 4);

  // Sala - duża czcionka Font 4 dla maksymalnej czytelności
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  tft.drawString("SALA " + roomNumber, 54, 6, 4);

  // Przycisk "Wolne Sale"
  tft.fillRoundRect(172, 4, 68, 26, 6, COLOR_PRZ_ORANGE);
  tft.setTextColor(0x0000, COLOR_PRZ_ORANGE);
  tft.drawCentreString("WOLNE", 206, 9, 2);

  // Przycisk Wi-Fi
  uint16_t wifiBg = (WiFi.status() == WL_CONNECTED) ? COLOR_FREE_GREEN : COLOR_OCC_RED;
  tft.fillRoundRect(246, 4, 68, 26, 6, wifiBg);
  tft.setTextColor(0x0000, wifiBg);
  tft.drawCentreString("Wi-Fi", 280, 5, 1);
  tft.drawCentreString(currentClockText(), 280, 14, 2); // kolor tla = stan Wi-Fi

  // KARTA STANU SALI (Y: 40..128, wys: 88px)
  uint16_t cardBg = isAvailable ? COLOR_CARD_FREE : (isAlertDue ? COLOR_CARD_ALERT : COLOR_CARD_OCC);
  uint16_t borderCol = isAvailable ? COLOR_FREE_GREEN : (isAlertDue ? COLOR_ALERT_AMBER : COLOR_OCC_RED);

  tft.fillRoundRect(12, 40, 296, 88, 12, cardBg);
  tft.drawRoundRect(12, 40, 296, 88, 12, borderCol);
  tft.drawRoundRect(13, 41, 294, 86, 11, borderCol);

  if (isAvailable) {
    tft.setTextColor(COLOR_FREE_GREEN, cardBg);
    tft.drawCentreString("SALA WOLNA", 160, 48, 4);
    tft.setTextColor(COLOR_TEXT_WHITE, cardBg);
    tft.drawCentreString("Dostepna do wejscia", 160, 78, 2);
    tft.setTextColor(COLOR_TEXT_MUTED, cardBg);
    tft.drawCentreString("Wybierz limit i dotknij ZAJMIJ", 160, 102, 2);
  } else {
    if (isAlertDue) {
      tft.setTextColor(COLOR_ALERT_AMBER, cardBg);
      tft.drawCentreString("! PRZEKROCZONO LIMIT !", 160, 46, 4);
    } else {
      tft.setTextColor(COLOR_OCC_RED, cardBg);
      tft.drawCentreString("SALA ZAJETA", 160, 46, 4);
    }

    tft.setTextColor(COLOR_TEXT_WHITE, cardBg);
    tft.drawCentreString("SESJA: " + formatDuration(durationSeconds), 160, 76, 4);

    tft.setTextColor(COLOR_TEXT_MUTED, cardBg);
    tft.drawCentreString("Limit sesji: " + String(selectedAlertLimit / 60) + " min", 160, 104, 2);
  }

  // PASEK TIMERÓW SESJI (Y: 134..172)
  int limits[] = {900, 1800, 2700, 3600};
  const char* limitLabels[] = {"15m", "30m", "45m", "60m"};

  for (int i = 0; i < 4; i++) {
    int btnX = 12 + i * 59;
    bool isActive = (selectedAlertLimit == limits[i]);
    uint16_t bg = isActive ? COLOR_PRZ_ORANGE : COLOR_PANEL;
    uint16_t fg = isActive ? 0x0000 : COLOR_TEXT_WHITE;

    tft.fillRoundRect(btnX, 134, 54, 38, 8, bg);
    tft.drawRoundRect(btnX, 134, 54, 38, 8, isActive ? COLOR_TEXT_WHITE : borderCol);
    if (isActive) tft.drawRoundRect(btnX + 1, 135, 52, 36, 7, COLOR_TEXT_WHITE);
    tft.setTextColor(fg, bg);
    tft.drawCentreString(limitLabels[i], btnX + 27, 144, 2);
  }

  // Dodatkowy kafelek [+10m] aktywny gdy sala jest zajęta
  if (!isAvailable) {
    tft.fillRoundRect(250, 134, 58, 38, 8, COLOR_PANEL);
    tft.drawRoundRect(250, 134, 58, 38, 8, COLOR_ALERT_AMBER);
    tft.drawRoundRect(251, 135, 56, 36, 7, COLOR_ALERT_AMBER);
    tft.setTextColor(COLOR_ALERT_AMBER, COLOR_PANEL);
    tft.drawCentreString("+10m", 279, 144, 2);
  } else {
    // Wskaźnik SD / Status
    tft.fillRoundRect(250, 134, 58, 38, 8, COLOR_PANEL);
    tft.drawRoundRect(250, 134, 58, 38, 8, 0x4228);
    tft.setTextColor(sdCardAvailable ? COLOR_FREE_GREEN : COLOR_TEXT_MUTED, COLOR_PANEL);
    tft.drawCentreString("SD:32G", 279, 144, 2);
  }

  // DUŻY DOLNY PRZYCISK (Y: 178..234)
  uint16_t actionBg = isAvailable ? COLOR_FREE_GREEN : COLOR_OCC_RED;
  tft.fillRoundRect(12, 178, 296, 54, 12, actionBg);
  tft.drawRoundRect(12, 178, 296, 54, 12, COLOR_TEXT_WHITE);
  tft.drawRoundRect(13, 179, 294, 52, 11, COLOR_TEXT_WHITE);

  tft.setTextColor(COLOR_TEXT_WHITE, actionBg);
  if (isAvailable) {
    tft.drawCentreString("ZAJMIJ SALE", 160, 185, 4);
    tft.setTextColor(0xD6BA, actionBg);
    tft.drawCentreString("Dotknij, aby rozpoczac sesje (" + String(selectedAlertLimit / 60) + "m)", 160, 212, 2);
  } else {
    tft.drawCentreString("ZWOLNIJ SALE", 160, 185, 4);
    tft.setTextColor(0xD6BA, actionBg);
    tft.drawCentreString("Dotknij, aby zakonczyc sesje", 160, 212, 2);
  }
}

// ----------------------------------------------------------------------------
// EKRAN 2: WIDOK WOLNYCH SAL (PROPOZYCJA 3)
// ----------------------------------------------------------------------------
void drawFreeRoomsScreen() {
  tft.fillRect(0, 0, 320, 34, COLOR_PANEL);
  tft.drawFastHLine(0, 34, 320, COLOR_FREE_GREEN);

  tft.setTextColor(COLOR_FREE_GREEN, COLOR_PANEL);
  tft.drawString("WOLNE SALE PRz (" + String(freeRoomsList.size()) + ")", 8, 8, 2);

  // Odśwież
  tft.fillRoundRect(168, 4, 68, 26, 6, COLOR_PRZ_ORANGE);
  tft.setTextColor(0x0000, COLOR_PRZ_ORANGE);
  tft.drawCentreString("ODSWIEZ", 202, 9, 2);

  // Wróć
  tft.fillRoundRect(242, 4, 72, 26, 6, COLOR_BTN_BG);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BTN_BG);
  tft.drawCentreString("< WROC", 278, 9, 2);

  if (freeRoomsList.empty()) {
    tft.setTextColor(COLOR_ALERT_AMBER, COLOR_BG);
    tft.drawCentreString("Brak wolnych sal!", 160, 95, 4);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BG);
    tft.drawCentreString("Wszystkie sale sa aktualnie zajete.", 160, 130, 2);
    return;
  }

  // Siatka 2 wiersze po 3 kafelki = 6 na stronę
  int startIndex = freeRoomsPage * ROOMS_PER_PAGE;
  for (int i = 0; i < ROOMS_PER_PAGE; i++) {
    int idx = startIndex + i;
    if (idx >= (int)freeRoomsList.size()) break;

    int col = i % 3;
    int row = i / 3;
    int kX = 12 + col * 99;
    int kY = 42 + row * 78;

    FreeRoomInfo r = freeRoomsList[idx];

    tft.fillRoundRect(kX, kY, 94, 72, 8, COLOR_CARD_FREE);
    tft.drawRoundRect(kX, kY, 94, 72, 8, COLOR_FREE_GREEN);
    tft.drawRoundRect(kX + 1, kY + 1, 92, 70, 7, COLOR_FREE_GREEN);

    // Numer sali - duży Font 4
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_CARD_FREE);
    tft.drawCentreString(r.number, kX + 47, kY + 8, 4);

    // Piętro - wyraźny Font 2
    tft.setTextColor(COLOR_FREE_GREEN, COLOR_CARD_FREE);
    tft.drawCentreString(r.floor, kX + 47, kY + 34, 2);

    // Pojemność - czytelny Font 1
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_FREE);
    String capStr = (r.capacity > 0) ? String(r.capacity) + " os." : "Wolna";
    tft.drawCentreString(capStr, kX + 47, kY + 52, 1);
  }

  // Pasek paginacji
  int maxPages = (freeRoomsList.size() + ROOMS_PER_PAGE - 1) / ROOMS_PER_PAGE;
  if (maxPages > 1) {
    if (freeRoomsPage > 0) {
      tft.fillRoundRect(20, 204, 76, 28, 6, COLOR_PANEL);
      tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
      tft.drawCentreString("< Poprz", 58, 210, 2);
    }
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
    tft.drawCentreString(String(freeRoomsPage + 1) + " / " + String(maxPages), 160, 210, 2);

    if ((freeRoomsPage + 1) < maxPages) {
      tft.fillRoundRect(224, 204, 76, 28, 6, COLOR_PANEL);
      tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
      tft.drawCentreString("Nast >", 262, 210, 2);
    }
  }
}

// ----------------------------------------------------------------------------
// EKRAN 3: LISTA SIECI WI-FI (SKANER)
// ----------------------------------------------------------------------------
void drawWifiListScreen() {
  tft.fillRect(0, 0, 320, 34, COLOR_PANEL);
  tft.drawFastHLine(0, 34, 320, COLOR_PRZ_ORANGE);

  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_PANEL);
  tft.drawString("SIECI WI-FI", 8, 8, 2);

  // Skanuj (duży, wyrazisty przycisk w Font 2)
  tft.fillRoundRect(160, 4, 72, 26, 6, COLOR_PRZ_ORANGE);
  tft.setTextColor(0x0000, COLOR_PRZ_ORANGE);
  tft.drawCentreString("SKANUJ", 196, 9, 2);

  // Wróć
  tft.fillRoundRect(240, 4, 72, 26, 6, COLOR_BTN_BG);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BTN_BG);
  tft.drawCentreString("< WROC", 276, 9, 2);

  if (scannedNetworks.empty()) {
    tft.fillRoundRect(20, 70, 280, 85, 10, COLOR_PANEL);
    tft.drawRoundRect(20, 70, 280, 85, 10, COLOR_ALERT_AMBER);
    tft.setTextColor(COLOR_ALERT_AMBER, COLOR_PANEL);
    tft.drawCentreString("Brak wykrytych sieci!", 160, 85, 4);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    tft.drawCentreString("Dotknij SKANUJ, aby wyszukac", 160, 118, 2);
    return;
  }

  int startY = 40;
  int itemH = 38;
  for (int i = 0; i < 4; i++) {
    int idx = wifiListPage * 4 + i;
    if (idx >= (int)scannedNetworks.size()) break;

    WifiNetworkInfo net = scannedNetworks[idx];
    int rowY = startY + i * (itemH + 4);

    bool isSaved = isNetworkSaved(net.ssid);

    uint16_t borderCol = isSaved ? COLOR_FREE_GREEN : COLOR_PRZ_ORANGE;
    tft.fillRoundRect(12, rowY, 296, itemH, 8, COLOR_PANEL);
    tft.drawRoundRect(12, rowY, 296, itemH, 8, borderCol);
    if (isSaved) tft.drawRoundRect(13, rowY + 1, 294, itemH - 2, 7, COLOR_FREE_GREEN);

    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    String displayName = net.ssid;
    if (displayName.length() > 15) displayName = displayName.substring(0, 14) + "..";
    tft.drawString(displayName, 22, rowY + 11, 2);

    if (isSaved) {
      tft.fillRoundRect(172, rowY + 8, 70, 22, 4, COLOR_CARD_FREE);
      tft.setTextColor(COLOR_FREE_GREEN, COLOR_CARD_FREE);
      tft.drawCentreString("ZAPISANA", 207, rowY + 11, 1);
    }

    String meta = String(net.rssi) + "dB";
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_PANEL);
    tft.drawRightString(meta, 298, rowY + 11, 2);
  }

  // Pasek paginacji
  int maxWifiPages = (scannedNetworks.size() + 3) / 4;
  if (maxWifiPages > 1) {
    if (wifiListPage > 0) {
      tft.fillRoundRect(14, 206, 76, 28, 6, COLOR_PANEL);
      tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
      tft.drawCentreString("< Poprz", 52, 212, 2);
    }
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
    tft.drawCentreString(String(wifiListPage + 1) + " / " + String(maxWifiPages), 160, 212, 2);

    if ((wifiListPage + 1) < maxWifiPages) {
      tft.fillRoundRect(228, 206, 76, 28, 6, COLOR_PANEL);
      tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
      tft.drawCentreString("Nast >", 266, 212, 2);
    }
  }
}

// ----------------------------------------------------------------------------
// EKRAN 4: KLAWIATURA DOTYKOWA QWERTY
// ----------------------------------------------------------------------------
void drawWifiKeyboardScreen() {
  tft.fillScreen(COLOR_BG);

  // Pasek górny
  tft.fillRect(0, 0, 320, 28, COLOR_PANEL);
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_PANEL);
  tft.drawString("HASLO: " + selectedNetworkSsid, 8, 6, 2);

  // Anuluj
  tft.fillRoundRect(244, 2, 70, 24, 6, COLOR_OCC_RED);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_OCC_RED);
  tft.drawCentreString("ANULUJ", 279, 6, 1);

  // Pole tekstowe hasła (Y: 34..68)
  tft.fillRoundRect(14, 34, 292, 34, 6, COLOR_PANEL);
  tft.drawRoundRect(14, 34, 292, 34, 6, COLOR_PRZ_ORANGE);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  String passDisplay = enteredWifiPassword.isEmpty() ? "(Dotknij klawiszy, aby wpisac haslo)" : enteredWifiPassword;
  tft.drawString(passDisplay, 24, 42, 2);

  // Klawiatura wiersz 1: Cyfry 1-0 (Y: 74)
  const char r1[] = "1234567890";
  for (int i = 0; i < 10; i++) {
    int kX = i * 32 + 2;
    tft.fillRoundRect(kX, 74, 28, 34, 4, COLOR_PANEL);
    tft.drawRoundRect(kX, 74, 28, 34, 4, 0x4228);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    tft.drawChar(kX + 8, 82, r1[i], COLOR_TEXT_WHITE, COLOR_PANEL, 2);
  }

  // Wiersz 2: QWERTY (Y: 112)
  const char r2[] = "qwertyuiop";
  for (int i = 0; i < 10; i++) {
    int kX = i * 32 + 2;
    tft.fillRoundRect(kX, 112, 28, 34, 4, COLOR_PANEL);
    tft.drawRoundRect(kX, 112, 28, 34, 4, 0x4228);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    tft.drawChar(kX + 8, 120, r2[i], COLOR_TEXT_WHITE, COLOR_PANEL, 2);
  }

  // Wiersz 3: ASDFGHJKL + DEL (Y: 150)
  const char r3[] = "asdfghjkl";
  for (int i = 0; i < 9; i++) {
    int kX = i * 29 + 4;
    tft.fillRoundRect(kX, 150, 26, 34, 4, COLOR_PANEL);
    tft.drawRoundRect(kX, 150, 26, 34, 4, 0x4228);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    tft.drawChar(kX + 7, 158, r3[i], COLOR_TEXT_WHITE, COLOR_PANEL, 2);
  }
  // Klawisz DEL (Backspace)
  tft.fillRoundRect(268, 150, 48, 34, 4, COLOR_OCC_RED);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_OCC_RED);
  tft.drawCentreString("DEL", 292, 158, 2);

  // Wiersz 4: ZXCVBNM + SPACJA + POŁĄCZ (Y: 188)
  const char r4[] = "zxcvbnm";
  for (int i = 0; i < 7; i++) {
    int kX = i * 20 + 2;
    tft.fillRoundRect(kX, 188, 18, 42, 4, COLOR_PANEL);
    tft.drawRoundRect(kX, 188, 18, 42, 4, 0x4228);
    tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
    tft.drawChar(kX + 4, 200, r4[i], COLOR_TEXT_WHITE, COLOR_PANEL, 2);
  }

  // Klawisz SPACJA
  tft.fillRoundRect(144, 188, 70, 42, 6, COLOR_PANEL);
  tft.drawRoundRect(144, 188, 70, 42, 6, COLOR_TEXT_MUTED);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  tft.drawCentreString("SPACJA", 179, 200, 1);

  // Klawisz POŁĄCZ
  tft.fillRoundRect(220, 188, 96, 42, 6, COLOR_FREE_GREEN);
  tft.drawRoundRect(220, 188, 96, 42, 6, COLOR_TEXT_WHITE);
  tft.setTextColor(0x0000, COLOR_FREE_GREEN);
  tft.drawCentreString("POLACZ >", 268, 200, 2);
}

// ============================================================================
// KOMUNIKACJA Z SERWEREM FASTAPI
// ============================================================================
void syncServerState() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  String url = serverUrl + "/api/v1/device/state";
  http.begin(url);
  http.setTimeout(2500);
  http.addHeader("Authorization", "Bearer " + deviceToken);
  http.addHeader("X-Firmware-Version", CYD_FIRMWARE_VERSION);
  http.addHeader("X-Chip-Type", "esp32");

  int httpCode = http.GET();
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    StaticJsonDocument<512> doc;
    DeserializationError err = deserializeJson(doc, payload);
    if (!err) {
      // 1. Sprawdzenie i automatyczna aktualizacja Auto-OTA
      if (doc.containsKey("firmware") && !doc["firmware"].isNull()) {
        JsonObject fw = doc["firmware"];
        const char* srvVer = fw["version"] | "";
        bool hasUpdate = fw["has_update"] | false;
        String fwUrl = fw["url"] | "";
        if (hasUpdate && strlen(srvVer) > 0 && String(srvVer) != String(CYD_FIRMWARE_VERSION) && fwUrl.length() > 0) {
          static unsigned long lastFailedOta = 0;
          if (millis() - lastFailedOta > 60000) {
            Serial.printf("[CYD] Auto-OTA wykrylo nowa wersje: %s (biezaca: %s). Rozpoczynanie!\n", srvVer, CYD_FIRMWARE_VERSION);
            logEvent("AUTO-OTA: Nowa wersja " + String(srvVer) + ". Pobieranie...");
            http.end();
            startOtaUpdate(fwUrl);
            lastFailedOta = millis();
            return;
          }
        }
      }

      // Zegar zsynchronizowany z czasem serwera (NTP dziala jako zapas)
      if (doc.containsKey("server_time")) {
        applyServerTime(doc["server_time"] | "");
      }

      // Dynamiczna zmiana przypisania sali z panelu administracyjnego
      bool roomChanged = false;
      if (doc.containsKey("room_id") && !doc["room_id"].isNull()) {
        String serverRoomId = doc["room_id"].as<String>();
        String serverRoomName = doc.containsKey("room_name") && !doc["room_name"].isNull() ? doc["room_name"].as<String>() : "";
        if (serverRoomId.length() > 0 && (serverRoomId != roomNumber || (serverRoomName.length() > 0 && serverRoomName != roomName))) {
          Serial.printf("[CYD] Przypisano nowa sale z serwera: %s (%s) [poprzednia: %s]\n",
            serverRoomId.c_str(), serverRoomName.c_str(), roomNumber.c_str());
          logEvent("PRZYPISANO SALE: " + serverRoomId + (serverRoomName.length() > 0 ? " (" + serverRoomName + ")" : ""));
          roomNumber = serverRoomId;
          if (serverRoomName.length() > 0) {
            roomName = serverRoomName;
          }
          saveSettings();
          roomChanged = true;
        }
      }

      const char* st = doc["status"] | "free";
      bool serverAvail = (strcmp(st, "free") == 0);

      if (doc.containsKey("active_session") && !doc["active_session"].isNull()) {
        JsonObject s = doc["active_session"];
        durationSeconds = s["duration_seconds"] | 0;
        selectedAlertLimit = s["alert_limit_seconds"] | 900;
        isAlertDue = s["alert_due"] | false;
      } else {
        durationSeconds = 0;
        isAlertDue = false;
      }

      if (serverAvail != isAvailable || roomChanged) {
        isAvailable = serverAvail;
        logEvent("ZMIANA STANU: Sala " + roomNumber + " -> " + (isAvailable ? "WOLNA" : "ZAJETA"));
        if (currentScreen == SCREEN_MAIN) {
          drawMainScreen();
        }
        updateLeds();
      }
    }
  }
  http.end();
}

void sendStatusChange(bool makeFree) {
  if (WiFi.status() != WL_CONNECTED) {
    isAvailable = makeFree;
    durationSeconds = 0;
    isAlertDue = false;
    drawCurrentScreen();
    return;
  }

  HTTPClient http;
  String url = serverUrl + "/api/v1/device/status";
  http.begin(url);
  http.setTimeout(3000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + deviceToken);

  StaticJsonDocument<128> req;
  req["status"] = makeFree ? "free" : "occupied";
  String body;
  serializeJson(req, body);

  int httpCode = http.POST(body);
  if (httpCode == HTTP_CODE_OK || httpCode == 201) {
    isAvailable = makeFree;
    durationSeconds = 0;
    isAlertDue = false;
    logEvent("DOTYK: Sala " + roomNumber + " zmieniona na " + (makeFree ? "WOLNA" : "ZAJETA"));
    drawCurrentScreen();
  }
  http.end();
}

void sendAlertLimit(int seconds) {
  selectedAlertLimit = seconds;
  drawCurrentScreen();

  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  String url = serverUrl + "/api/v1/rooms/" + roomNumber + "/alert-limit";
  http.begin(url);
  http.setTimeout(3000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + deviceToken);

  StaticJsonDocument<128> req;
  req["limit_seconds"] = seconds;
  String body;
  serializeJson(req, body);

  http.POST(body);
  http.end();
  logEvent("LIMIT SESJI: Sala " + roomNumber + " ustawiono limit " + String(seconds / 60) + " min");
}

void fetchFreeRooms() {
  freeRoomsList.clear();
  freeRoomsPage = 0;
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  String url = serverUrl + "/api/v1/public/rooms";
  http.begin(url);
  http.setTimeout(3500);

  int httpCode = http.GET();
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    DynamicJsonDocument doc(4096);
    DeserializationError err = deserializeJson(doc, payload);
    if (!err) {
      JsonArray arr = doc.as<JsonArray>();
      for (JsonObject r : arr) {
        const char* st = r["status"] | "free";
        if (strcmp(st, "free") == 0) {
          FreeRoomInfo info;
          info.number = r["id"].as<String>();
          info.name = r["name"].as<String>();
          info.floor = r["floor"].as<String>();
          info.capacity = r["capacity"] | 0;
          freeRoomsList.push_back(info);
        }
      }
    }
  }
  http.end();
}

void loadSavedNetworks() {
  savedNetworks.clear();

  // 1. Odczyt z pliku na karcie MicroSD 32GB
  if (sdCardAvailable && SD.exists("/dostepnosc_sal/saved_wifi.json")) {
    File f = SD.open("/dostepnosc_sal/saved_wifi.json", FILE_READ);
    if (f) {
      JsonDocument doc;
      DeserializationError err = deserializeJson(doc, f);
      if (!err && doc.is<JsonArray>()) {
        for (JsonObject net : doc.as<JsonArray>()) {
          SavedNetwork sn;
          sn.ssid = net["ssid"].as<String>();
          sn.pass = net["pass"].as<String>();
          if (sn.ssid.length() > 0) {
            savedNetworks.push_back(sn);
          }
        }
      }
      f.close();
    }
  }

  // 2. Jeśli brak na SD lub SD niedostępne - odczytaj z pamięci NVS
  if (savedNetworks.empty()) {
    prefs.begin("cyd_wifi", true);
    int count = prefs.getInt("count", 0);
    for (int i = 0; i < count; i++) {
      String s = prefs.getString(("s" + String(i)).c_str(), "");
      String p = prefs.getString(("p" + String(i)).c_str(), "");
      if (s.length() > 0) {
        SavedNetwork sn;
        sn.ssid = s;
        sn.pass = p;
        savedNetworks.push_back(sn);
      }
    }
    prefs.end();
  }

  // 3. Dodaj bieżącą sieć jeśli nie ma jej jeszcze na liście
  if (wifiSsid.length() > 0 && wifiSsid != "TWOJA_NAZWA_WIFI") {
    if (!isNetworkSaved(wifiSsid)) {
      SavedNetwork sn;
      sn.ssid = wifiSsid;
      sn.pass = wifiPassword;
      savedNetworks.push_back(sn);
    }
  }

  Serial.printf("[WiFi] Wczytano zapamietanych sieci: %d\n", (int)savedNetworks.size());
}

void addOrUpdateSavedNetwork(const String& ssid, const String& pass) {
  if (ssid.length() == 0) return;

  bool found = false;
  for (auto& sn : savedNetworks) {
    if (sn.ssid == ssid) {
      sn.pass = pass;
      found = true;
      break;
    }
  }
  if (!found) {
    SavedNetwork sn;
    sn.ssid = ssid;
    sn.pass = pass;
    savedNetworks.push_back(sn);
  }

  // Zapis do pamięci NVS
  prefs.begin("cyd_wifi", false);
  prefs.putInt("count", (int)savedNetworks.size());
  for (size_t i = 0; i < savedNetworks.size(); i++) {
    prefs.putString(("s" + String(i)).c_str(), savedNetworks[i].ssid);
    prefs.putString(("p" + String(i)).c_str(), savedNetworks[i].pass);
  }
  prefs.end();

  // Zapis do pliku JSON na karcie SD
  if (sdCardAvailable) {
    File f = SD.open("/dostepnosc_sal/saved_wifi.json", FILE_WRITE);
    if (f) {
      JsonDocument doc;
      JsonArray arr = doc.to<JsonArray>();
      for (const auto& sn : savedNetworks) {
        JsonObject obj = arr.createNestedObject();
        obj["ssid"] = sn.ssid;
        obj["pass"] = sn.pass;
      }
      serializeJson(doc, f);
      f.close();
    }
  }

  logEvent("WIFI: Zapisano siec na stale: " + ssid);
}

bool isNetworkSaved(const String& ssid, String* outPass) {
  for (const auto& sn : savedNetworks) {
    if (sn.ssid == ssid) {
      if (outPass) *outPass = sn.pass;
      return true;
    }
  }
  return false;
}

void connectWithCredentials(const String& ssid, const String& pass) {
  tft.fillRect(14, 40, 292, 190, COLOR_BG);
  tft.fillRoundRect(24, 70, 272, 85, 10, COLOR_PANEL);
  tft.drawRoundRect(24, 70, 272, 85, 10, COLOR_FREE_GREEN);

  tft.setTextColor(COLOR_FREE_GREEN, COLOR_PANEL);
  tft.drawCentreString("LACZENIE Z WI-FI...", 160, 85, 4);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  tft.drawCentreString(ssid, 160, 118, 2);

  WiFi.disconnect();
  WiFi.begin(ssid.c_str(), pass.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 25) {
    delay(300);
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    wifiSsid = ssid;
    wifiPassword = pass;
    saveSettings();
    addOrUpdateSavedNetwork(ssid, pass);
    logEvent("WIFI: Polaczono pomyslnie z " + ssid);

    tft.setTextColor(COLOR_FREE_GREEN, COLOR_PANEL);
    tft.drawCentreString("POLACZONO!", 160, 85, 4);
    delay(1000);

    currentScreen = SCREEN_MAIN;
    drawCurrentScreen();
    checkForFirmwareUpdate();
  } else {
    tft.setTextColor(COLOR_OCC_RED, COLOR_PANEL);
    tft.drawCentreString("BLAD POLACZENIA!", 160, 85, 4);
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_PANEL);
    tft.drawCentreString("Wpisz haslo ponownie", 160, 118, 2);
    delay(1800);

    enteredWifiPassword = pass;
    currentScreen = SCREEN_WIFI_KEYBOARD;
    drawCurrentScreen();
  }
}

void connectToBestSavedWifi() {
  if (savedNetworks.empty()) {
    Serial.println("[WiFi] Brak zapisanych sieci.");
    return;
  }

  Serial.println("[WiFi] Skanowanie eteru w poszukiwaniu znanych sieci...");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  int n = WiFi.scanNetworks();
  Serial.printf("[WiFi] Znaleziono %d sieci w eterze\n", n);

  int bestRssi = -1000;
  String bestSsid = "";
  String bestPass = "";

  for (int i = 0; i < n; i++) {
    String curSsid = WiFi.SSID(i);
    int curRssi = WiFi.RSSI(i);
    String curPass = "";
    if (isNetworkSaved(curSsid, &curPass)) {
      if (curRssi > bestRssi) {
        bestRssi = curRssi;
        bestSsid = curSsid;
        bestPass = curPass;
      }
    }
  }

  if (bestSsid.length() > 0) {
    Serial.printf("[WiFi] Laczenie ze znana siecia: %s (RSSI: %d dBm)\n", bestSsid.c_str(), bestRssi);
    wifiSsid = bestSsid;
    wifiPassword = bestPass;
    WiFi.begin(bestSsid.c_str(), bestPass.c_str());

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 25) {
      delay(300);
      Serial.print(".");
      attempts++;
    }
  } else if (wifiSsid.length() > 0 && wifiSsid != "TWOJA_NAZWA_WIFI") {
    Serial.println("[WiFi] Brak znanych sieci w eterze. Proba z " + wifiSsid);
    WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 15) {
      delay(300);
      attempts++;
    }
  }
}

void scanWifiNetworks() {
  scannedNetworks.clear();
  wifiListPage = 0;

  // Natychmiastowy komunikat na ekranie o trwającym skanowaniu
  tft.fillRect(14, 40, 292, 190, COLOR_BG);
  tft.fillRoundRect(24, 70, 272, 80, 10, COLOR_PANEL);
  tft.drawRoundRect(24, 70, 272, 80, 10, COLOR_PRZ_ORANGE);
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_PANEL);
  tft.drawCentreString("SKANOWANIE WI-FI...", 160, 85, 4);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  tft.drawCentreString("Wyszukiwanie sieci 2.4 GHz", 160, 118, 2);

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(150);

  int n = WiFi.scanNetworks();
  Serial.printf("[WiFi] Skanowanie zakonczone. Wykryto: %d sieci\n", n);

  if (n > 0) {
    for (int i = 0; i < n; i++) {
      if (WiFi.SSID(i).length() == 0) continue;

      bool duplicate = false;
      for (const auto& existing : scannedNetworks) {
        if (existing.ssid == WiFi.SSID(i)) {
          duplicate = true;
          break;
        }
      }
      if (duplicate) continue;

      WifiNetworkInfo info;
      info.ssid = WiFi.SSID(i);
      info.rssi = WiFi.RSSI(i);
      info.isEncrypted = (WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
      scannedNetworks.push_back(info);
    }
  }

  // Sortowanie: najpierw zapisane/znane, potem najsilniejszy sygnal
  std::sort(scannedNetworks.begin(), scannedNetworks.end(), [](const WifiNetworkInfo& a, const WifiNetworkInfo& b) {
    bool aSaved = isNetworkSaved(a.ssid);
    bool bSaved = isNetworkSaved(b.ssid);
    if (aSaved != bSaved) return aSaved > bSaved;
    return a.rssi > b.rssi;
  });
}

// ============================================================================
// USTAWIENIA, KARTA SD 32GB I LOGI
// ============================================================================
void loadSettings() {
  // 1. Próba odczytu z karty SD
  if (sdCardAvailable && SD.exists("/dostepnosc_sal/config.json")) {
    File f = SD.open("/dostepnosc_sal/config.json", FILE_READ);
    if (f) {
      StaticJsonDocument<512> doc;
      if (!deserializeJson(doc, f)) {
        if (doc.containsKey("ssid")) wifiSsid = doc["ssid"].as<String>();
        if (doc.containsKey("pass")) wifiPassword = doc["pass"].as<String>();
        if (doc.containsKey("room")) roomNumber = doc["room"].as<String>();
        if (doc.containsKey("name")) roomName = doc["name"].as<String>();
        if (doc.containsKey("server")) serverUrl = doc["server"].as<String>();
        if (doc.containsKey("token")) deviceToken = doc["token"].as<String>();
      }
      f.close();
      return;
    }
  }

  // 2. Odczyt z pamięci NVS (Preferences)
  prefs.begin("cyd_config", true);
  wifiSsid = prefs.getString("ssid", wifiSsid);
  wifiPassword = prefs.getString("pass", wifiPassword);
  roomNumber = prefs.getString("room", roomNumber);
  roomName = prefs.getString("name", roomName);
  serverUrl = prefs.getString("server", serverUrl);
  deviceToken = prefs.getString("token", deviceToken);
  isDisplayInverted = prefs.getBool("disp_inv", true); // Domyślnie włączona inwersja dla CYD!
  prefs.end();
}

void saveSettings() {
  // Zapis do NVS
  prefs.begin("cyd_config", false);
  prefs.putString("ssid", wifiSsid);
  prefs.putString("pass", wifiPassword);
  prefs.putString("room", roomNumber);
  prefs.putString("name", roomName);
  prefs.putString("server", serverUrl);
  prefs.putString("token", deviceToken);
  prefs.putBool("disp_inv", isDisplayInverted);
  prefs.end();

  // Zapis do pliku na karcie SD
  if (sdCardAvailable) {
    File f = SD.open("/dostepnosc_sal/config.json", FILE_WRITE);
    if (f) {
      StaticJsonDocument<512> doc;
      doc["ssid"] = wifiSsid;
      doc["pass"] = wifiPassword;
      doc["room"] = roomNumber;
      doc["name"] = roomName;
      doc["server"] = serverUrl;
      doc["token"] = deviceToken;
      serializeJson(doc, f);
      f.close();
    }
  }
}

void logEvent(const String& event) {
  if (sdCardAvailable) {
    File f = SD.open("/dostepnosc_sal/events.log", FILE_APPEND);
    if (f) {
      f.println("[" + String(millis() / 1000) + "s] " + event);
      f.close();
    }
  }
  Serial.println("[EVENT] " + event);
}

// ============================================================================
// DIODA RGB I FORMATOWANIE
// ============================================================================
void setRgbLed(bool r, bool g, bool b) {
  digitalWrite(CYD_LED_RED, r ? LOW : HIGH);
  digitalWrite(CYD_LED_GREEN, g ? LOW : HIGH);
  digitalWrite(CYD_LED_BLUE, b ? LOW : HIGH);
}

void updateLeds() {
  if (isAvailable) {
    setRgbLed(false, true, false); // Zielony
  } else {
    if (isAlertDue) {
      setRgbLed(true, true, false); // Żółty / Bursztyn
    } else {
      setRgbLed(true, false, false); // Czerwony
    }
  }
}

String formatDuration(int totalSecs) {
  int totalMinutes = totalSecs / 60;
  if (totalMinutes < 1) {
    return "< 1 min";
  }
  if (totalMinutes >= 60) {
    int h = totalMinutes / 60;
    int remM = totalMinutes % 60;
    char buf[16];
    if (remM > 0) {
      snprintf(buf, sizeof(buf), "%dh %d min", h, remM);
    } else {
      snprintf(buf, sizeof(buf), "%d godz.", h);
    }
    return String(buf);
  }
  char buf[16];
  snprintf(buf, sizeof(buf), "%d min", totalMinutes);
  return String(buf);
}

// ============================================================================
// AUTOMATYCZNA AKTUALIZACJA OPROGRAMOWANIA (HTTP AUTO-OTA)
// ============================================================================
void drawOtaProgressScreen(int percent, const String& statusText) {
  tft.fillScreen(COLOR_BG);

  // Górna belka
  tft.fillRect(0, 0, 320, 32, COLOR_PANEL);
  tft.drawFastHLine(0, 32, 320, COLOR_PRZ_ORANGE);
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_PANEL);
  tft.drawString("PRz", 8, 6, 4);
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_PANEL);
  tft.drawString("AKTUALIZACJA OTA", 54, 8, 2);

  // Nagłówek
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BG);
  tft.drawCentreString("Pobieranie nowego oprogramowania...", 160, 48, 2);
  tft.setTextColor(COLOR_PRZ_ORANGE, COLOR_BG);
  tft.drawCentreString("Wersja biezaca: " + String(CYD_FIRMWARE_VERSION), 160, 70, 2);

  // Pasek postępu - obwódka
  tft.drawRoundRect(28, 98, 264, 32, 8, COLOR_TEXT_WHITE);
  tft.fillRoundRect(30, 100, 260, 28, 6, COLOR_PANEL);

  // Wypełnienie paska postępu
  int barWidth = (percent * 256) / 100;
  if (barWidth > 0) {
    if (barWidth > 256) barWidth = 256;
    tft.fillRoundRect(32, 102, barWidth, 24, 4, COLOR_FREE_GREEN);
  }

  // Wartość procentowa
  tft.setTextColor(COLOR_TEXT_WHITE, COLOR_BG);
  tft.drawCentreString(String(percent) + " %", 160, 140, 4);

  // Status tekstowy
  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
  tft.drawCentreString(statusText, 160, 180, 2);

  // Ostrzeżenie
  tft.setTextColor(COLOR_ALERT_AMBER, COLOR_BG);
  tft.drawCentreString("Nie odlaczaj zasilania urzadzenia!", 160, 210, 2);
}

void startOtaUpdate(const String& firmwareUrl) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[OTA] Brak polaczenia z Wi-Fi. Anulowano.");
    return;
  }

  Serial.println("[OTA] Rozpoczynanie pobierania oprogramowania: " + firmwareUrl);
  logEvent("OTA: Rozpoczynanie aktualizacji z " + firmwareUrl);

  currentScreen = SCREEN_OTA_PROGRESS;
  drawOtaProgressScreen(0, "Nawiazywanie polaczenia...");
  setRgbLed(false, false, true); // Niebieska dioda sygnalizuje proces

  HTTPClient http;
  WiFiClient plainClient;
  WiFiClientSecure secureClient;

  if (firmwareUrl.startsWith("https://")) {
    secureClient.setInsecure();
    http.begin(secureClient, firmwareUrl);
  } else {
    http.begin(plainClient, firmwareUrl);
  }

  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  http.setTimeout(15000);

  int httpCode = http.GET();
  if (httpCode != HTTP_CODE_OK) {
    String errStr = "Blad HTTP: " + String(httpCode);
    Serial.println("[OTA] " + errStr);
    logEvent("OTA BLAD: " + errStr);
    drawOtaProgressScreen(0, errStr);
    setRgbLed(true, false, false);
    delay(4000);
    http.end();
    currentScreen = SCREEN_MAIN;
    drawCurrentScreen();
    return;
  }

  int contentLength = http.getSize();
  if (contentLength <= 0) {
    Serial.println("[OTA] Nieprawidlowy rozmiar pliku firmware.");
    drawOtaProgressScreen(0, "Blad: pusty plik firmware");
    setRgbLed(true, false, false);
    delay(4000);
    http.end();
    currentScreen = SCREEN_MAIN;
    drawCurrentScreen();
    return;
  }

  Serial.printf("[OTA] Rozmiar pliku firmware: %d bajtow\n", contentLength);

  bool canBegin = Update.begin(contentLength);
  if (!canBegin) {
    Serial.printf("[OTA] Brak miejsca na partycji OTA (kod: %u)\n", Update.getError());
    drawOtaProgressScreen(0, "Blad: brak miejsca na partycji");
    setRgbLed(true, false, false);
    delay(4000);
    http.end();
    currentScreen = SCREEN_MAIN;
    drawCurrentScreen();
    return;
  }

  WiFiClient* stream = http.getStreamPtr();
  uint8_t buff[1024];
  int written = 0;
  int lastPercent = -1;

  while (http.connected() && (written < contentLength)) {
    size_t availableBytes = stream->available();
    if (availableBytes > 0) {
      int bytesToRead = (availableBytes > sizeof(buff)) ? sizeof(buff) : availableBytes;
      int bytesRead = stream->readBytes(buff, bytesToRead);
      if (bytesRead > 0) {
        Update.write(buff, bytesRead);
        written += bytesRead;

        int percent = (written * 100) / contentLength;
        if (percent != lastPercent && (percent % 5 == 0 || percent == 100)) {
          lastPercent = percent;
          String status = String(written / 1024) + " KB / " + String(contentLength / 1024) + " KB";
          drawOtaProgressScreen(percent, status);
          Serial.printf("[OTA] Postep: %d%% (%d / %d B)\n", percent, written, contentLength);
        }
      }
    } else {
      delay(2);
    }
  }

  if (Update.end()) {
    if (Update.isFinished()) {
      Serial.println("[OTA] Aktualizacja zakonczona pomyslnie! Restartowanie...");
      logEvent("OTA: Aktualizacja zakonczona pelnym sukcesem. Restart!");
      drawOtaProgressScreen(100, "UKONCZONO! Ponowne uruchamianie...");
      setRgbLed(false, true, false); // Zielona dioda
      delay(2000);
      ESP.restart();
    } else {
      Serial.println("[OTA] Blad: Update nieukonczony.");
      drawOtaProgressScreen(0, "Blad zapisu oprogramowania");
      setRgbLed(true, false, false);
      delay(3500);
    }
  } else {
    Serial.printf("[OTA] Blad Update.end: #%u\n", Update.getError());
    drawOtaProgressScreen(0, "Blad aktualizacji kod: " + String(Update.getError()));
    setRgbLed(true, false, false);
    delay(3500);
  }

  http.end();
  currentScreen = SCREEN_MAIN;
  drawCurrentScreen();
}

void checkForFirmwareUpdate() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (currentScreen == SCREEN_OTA_PROGRESS) return;

  Serial.println("[OTA] Sprawdzanie dostepnosci nowej wersji oprogramowania...");

  HTTPClient http;
  WiFiClient plainClient;
  WiFiClientSecure secureClient;
  String url = serverUrl + "/api/v1/cyd-version";

  if (url.startsWith("https://")) {
    secureClient.setInsecure();
    http.begin(secureClient, url);
  } else {
    http.begin(plainClient, url);
  }

  http.setTimeout(5000);
  int httpCode = http.GET();

  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    StaticJsonDocument<512> doc;
    DeserializationError err = deserializeJson(doc, payload);
    if (!err) {
      const char* srvVersion = doc["version"] | "";
      bool hasUpdate = doc["has_update"] | false;
      String fwUrl = doc["firmware_url"].as<String>();

      Serial.println("[OTA] Serwer wersja: " + String(srvVersion) + " | Urzadzenie wersja: " + String(CYD_FIRMWARE_VERSION));

      if (hasUpdate && String(srvVersion) != String(CYD_FIRMWARE_VERSION) && fwUrl.length() > 0) {
        Serial.println("[OTA] Wykryto nowa wersje (" + String(srvVersion) + "). Uruchamianie Auto-OTA!");
        logEvent("OTA: Wykryto nowa wersje: " + String(srvVersion) + ". Rozpoczynanie pobierania.");
        http.end();
        startOtaUpdate(fwUrl);
        return;
      } else {
        Serial.println("[OTA] Oprogramowanie jest aktualne.");
      }
    }
  } else {
    Serial.printf("[OTA] Nie udalo sie pobrac wersji (HTTP: %d)\n", httpCode);
  }

  http.end();
}
