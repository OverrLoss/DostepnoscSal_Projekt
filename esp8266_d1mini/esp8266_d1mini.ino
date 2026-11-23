/*
 * ============================================================================
 * Politechnika Rzeszowska - System Dostępności Sal
 * Sterownik ESP8266 / Wemos D1 Mini z aktywnym skanerem WiFi
 * ============================================================================
 * 
 * Konfiguracja sprzętowa (zgodnie ze specyfikacją):
 * Wyjścia:
 *   - D1 (GPIO 5) : Sterowanie Diodą LED 1 (rezystor do anody) -> Sala WOLNA (Zielona)
 *   - D2 (GPIO 4) : Sterowanie Diodą LED 2 (rezystor do anody) -> Sala ZAJĘTA (Czerwona)
 * 
 * Wejścia:
 *   - D5 (GPIO 14): Przycisk 1 (INPUT_PULLUP, zwarty do GND po wciśnięciu) -> WOLNA
 *   - D6 (GPIO 12): Przycisk 2 (INPUT_PULLUP, zwarty do GND po wciśnięciu) -> ZAJĘTA
 * 
 * Zasilanie i masa:
 *   - G (GND)     : Wspólna masa dla obu diod (katod) oraz obu przycisków.
 * 
 * Diody LED:
 *   - Sala WOLNA   -> LED1 (D1 - Zielona) świeci stale, LED2 wyłączona
 *   - Sala ZAJĘTA  -> LED2 (D2 - Czerwona) świeci stale, LED1 wyłączona
 *   - Tryb parowania -> Obie diody migają naprzemiennie
 * ============================================================================
 */

#include <vector>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPClient.h>
#include <ESP8266httpUpdate.h>
#include <WiFiClientSecure.h>
#include <WiFiClient.h>
#include <DNSServer.h>
#include <EEPROM.h>
#include <ArduinoJson.h>

const char* ESP8266_FIRMWARE_VERSION = "1.3.9";

// --- PINOUT ---
const int PIN_LED_FREE = 4;  // D2 (GPIO 4) -> LED Wolna (Zielona)
const int PIN_LED_BUSY = 5;  // D1 (GPIO 5) -> LED Zajęta (Czerwona)
const int PIN_BTN_FREE = 14; // D5 (GPIO 14) -> Przycisk 1 (INPUT_PULLUP)
const int PIN_BTN_BUSY = 12; // D6 (GPIO 12) -> Przycisk 2 (INPUT_PULLUP)

// --- STRUKTURA EEPROM ---
#define EEPROM_MAGIC 0x5C
#define EEPROM_SIZE 512

struct DeviceConfig {
  uint8_t magic;
  char wifiSsid[33];
  char wifiPass[65];
  char serverUrl[97];
  char roomNumber[17];
  char deviceToken[65];
  int32_t roomId;
};

DeviceConfig config;

// --- STRUKTURA ZESKANOWANEJ SIECI ---
struct ScannedNetwork {
  String ssid;
  int32_t rssi;
  bool isEncrypted;
  int32_t channel;
};

std::vector<ScannedNetwork> scannedNetworks;

// --- ZMIENNE STANU ---
String deviceId;
String macAddress;
bool isPairingMode = false;
bool currentAvailability = true; // true = wolna, false = zajęta
bool roomAssigned = false;
unsigned long lastSyncMillis = 0;
const unsigned long SYNC_INTERVAL_MS = 2500;

// Obsługa przycisków i detekcja jednoczesnego wciśnięcia
unsigned long bothPressedStart = 0;
bool bothPressedTriggered = false;
unsigned long lastDebounceFree = 0;
unsigned long lastDebounceBusy = 0;
const unsigned long DEBOUNCE_DELAY = 50;
const unsigned long PAIRING_HOLD_TIME = 1500; // 1.5 sekundy na włączenie trybu parowania

// Serwer WWW i DNS dla Portalu Konfiguracyjnego
ESP8266WebServer webServer(80);
DNSServer dnsServer;
const byte DNS_PORT = 53;

// --- DEKLARACJE FUNKCJI ---
void loadConfig();
void saveConfig();
void scanNearbyNetworks();
void enterPairingMode();
void exitPairingMode();
void updateLeds(bool isFree);
void blinkPairingPattern();
void handleRoot();
void handleSave();
void handleScan();
void syncWithServer();
void performAutoOta(const String& firmwareUrl);
void sendRoomStatus(bool isFree);
void announcePairingMode();

// ============================================================================
// SKANOWANIE SIECI WIFI W OKOLICY
// ============================================================================
void scanNearbyNetworks() {
  Serial.println("\n--------------------------------------------------");
  Serial.println("[WiFi Skaner] Skanowanie sieci WiFi 2.4 GHz...");
  Serial.println("--------------------------------------------------");

  int n = WiFi.scanNetworks(false, true);
  scannedNetworks.clear();

  if (n <= 0) {
    Serial.println("[WiFi Skaner] Nie wykryto sieci WiFi.");
  } else {
    Serial.printf("[WiFi Skaner] Wykryto %d sieci WiFi w okolicy:\n", n);
    for (int i = 0; i < n; ++i) {
      ScannedNetwork net;
      net.ssid = WiFi.SSID(i);
      net.rssi = WiFi.RSSI(i);
      net.isEncrypted = (WiFi.encryptionType(i) != ENC_TYPE_NONE);
      net.channel = WiFi.channel(i);
      scannedNetworks.push_back(net);

      String encStr = net.isEncrypted ? "[Zabezpieczona]" : "[Otwarta]";
      String displaySsid = net.ssid.length() > 0 ? net.ssid : "<Siec ukryta>";
      Serial.printf("  %2d. %-24s | Sygnal: %3d dBm | Kan: %2d | %s\n",
                    i + 1,
                    displaySsid.c_str(),
                    net.rssi,
                    net.channel,
                    encStr.c_str());
    }

    if (strlen(config.wifiSsid) > 0) {
      bool foundTarget = false;
      int targetRssi = 0;
      int targetChannel = 0;
      for (const auto& net : scannedNetworks) {
        if (net.ssid == config.wifiSsid) {
          foundTarget = true;
          targetRssi = net.rssi;
          targetChannel = net.channel;
          break;
        }
      }
      if (foundTarget) {
        Serial.printf("[WiFi Skaner] >>> Skonfigurowana siec '%s' JEST W ZASIEGU! (%d dBm, Kan: %d)\n",
                      config.wifiSsid, targetRssi, targetChannel);
      } else {
        Serial.printf("[WiFi Skaner] >>> UWAGA: Skonfigurowana siec '%s' NIE zostala wykryta w zasiegu!\n",
                      config.wifiSsid);
      }
    }
  }
  Serial.println("--------------------------------------------------\n");
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n\n========================================");
  Serial.println("Politechnika Rzeszowska - Dostepnosc Sal");
  Serial.println("Sterownik Wemos D1 Mini (ESP8266)");
  Serial.println("========================================");

  // Inicjalizacja pinów
  pinMode(PIN_LED_FREE, OUTPUT);
  pinMode(PIN_LED_BUSY, OUTPUT);
  digitalWrite(PIN_LED_FREE, LOW);
  digitalWrite(PIN_LED_BUSY, LOW);

  pinMode(PIN_BTN_FREE, INPUT_PULLUP);
  pinMode(PIN_BTN_BUSY, INPUT_PULLUP);

  // Generowanie unikalnego ID urządzenia z chip ID
  uint32_t chipId = ESP.getChipId();
  char idBuf[20];
  snprintf(idBuf, sizeof(idBuf), "ESP_%06X", chipId);
  deviceId = String(idBuf);
  macAddress = WiFi.macAddress();

  Serial.print("Device ID: ");
  Serial.println(deviceId);
  Serial.print("MAC: ");
  Serial.println(macAddress);

  // Wczytanie konfiguracji z EEPROM
  EEPROM.begin(EEPROM_SIZE);
  loadConfig();

  // Konfiguracja radia WiFi
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);

  // Skanowanie pasma WiFi przed połączeniem
  scanNearbyNetworks();

  // Sprawdzenie czy przyciski nie są wciśnięte przy starcie
  if (digitalRead(PIN_BTN_FREE) == LOW && digitalRead(PIN_BTN_BUSY) == LOW) {
    Serial.println("[STARTUP] Wykryto oba przyciski wcisniete przy starcie -> Tryb parowania!");
    enterPairingMode();
    return;
  }

  // Jeśli brak skonfigurowanego WiFi lub brak sali, wejdź w tryb parowania
  if (strlen(config.wifiSsid) == 0 || strlen(config.roomNumber) == 0) {
    Serial.println("[STARTUP] Brak konfiguracji WiFi lub sali -> Wejscie w tryb parowania!");
    enterPairingMode();
    return;
  }

  // Próba połączenia z WiFi
  Serial.printf("[WiFi] Laczenie ze skonfigurowana siecia: '%s'...\n", config.wifiSsid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(config.wifiSsid, config.wifiPass);

  int wifiAttempts = 0;
  while (WiFi.status() != WL_CONNECTED && wifiAttempts < 35) {
    delay(300);
    Serial.print(".");
    wifiAttempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WiFi] Polaczono pomyslnie! IP: ");
    Serial.println(WiFi.localIP());

    // Pobierz aktualny stan z serwera dla przypisanej sali i ustaw diodę
    syncWithServer();
  } else {
    Serial.println("[WiFi] Nie udalo sie polaczyc ze skonfigurowana siecia -> Przelaczenie w tryb konfiguracji.");
    enterPairingMode();
  }
}

// ============================================================================
// GŁÓWNA PĘTLA (LOOP)
// ============================================================================
void loop() {
  unsigned long now = millis();

  // 1. Odczyt stanów przycisków (aktywne LOW przez INPUT_PULLUP)
  bool btnFreePressed = (digitalRead(PIN_BTN_FREE) == LOW);
  bool btnBusyPressed = (digitalRead(PIN_BTN_BUSY) == LOW);

  // 2. Detekcja JEDNOCZESNEGO wciśnięcia obu przycisków (D5 + D6)
  if (btnFreePressed && btnBusyPressed) {
    if (bothPressedStart == 0) {
      bothPressedStart = now;
      bothPressedTriggered = false;
    } else if (!bothPressedTriggered && (now - bothPressedStart >= PAIRING_HOLD_TIME)) {
      bothPressedTriggered = true;
      Serial.println("\n[PRZYCISKI] Wykryto przytrzymanie OBU przyciskow > 1.5s!");
      if (!isPairingMode) {
        Serial.println("[AKCJA] Uruchamianie trybu parowania...");
        enterPairingMode();
      } else {
        Serial.println("[AKCJA] Ponowne wywolanie rozglaszania parowania...");
        announcePairingMode();
      }
    }
  } else {
    bothPressedStart = 0;
    bothPressedTriggered = false;
  }

  // 3. Obsługa w trybie parowania (PAIRING MODE)
  if (isPairingMode) {
    dnsServer.processNextRequest();
    webServer.handleClient();
    blinkPairingPattern();

    // Jeśli połączony z WiFi, co 2 sekundy sprawdzaj czy serwer przypisał salę
    if (WiFi.status() == WL_CONNECTED && (now - lastSyncMillis >= 2000)) {
      lastSyncMillis = now;
      syncWithServer();
    }
    return;
  }

  // 4. Obsługa pojedynczych przycisków w trybie normalnym
  if (!btnFreePressed || !btnBusyPressed) {
    // Przycisk 1: WOLNA (D5) -> Zapala na stałe zieloną D1, gasi czerwoną D2
    static bool prevFree = false;
    if (btnFreePressed && !prevFree && (now - lastDebounceFree > DEBOUNCE_DELAY)) {
      lastDebounceFree = now;
      prevFree = true;
      Serial.println("\n[KLIK] Przycisk 1 (D5) -> Ustawienie sali jako WOLNA (Green)");
      updateLeds(true);
      sendRoomStatus(true);
    } else if (!btnFreePressed) {
      prevFree = false;
    }

    // Przycisk 2: ZAJĘTA (D6) -> Zapala na stałe czerwoną D2, gasi zieloną D1
    static bool prevBusy = false;
    if (btnBusyPressed && !prevBusy && (now - lastDebounceBusy > DEBOUNCE_DELAY)) {
      lastDebounceBusy = now;
      prevBusy = true;
      Serial.println("\n[KLIK] Przycisk 2 (D6) -> Ustawienie sali jako ZAJETA (Red)");
      updateLeds(false);
      sendRoomStatus(false);
    } else if (!btnBusyPressed) {
      prevBusy = false;
    }
  }

  // 5. Okresowa synchronizacja stanu z serwera (co SYNC_INTERVAL_MS)
  if (WiFi.status() == WL_CONNECTED) {
    if (now - lastSyncMillis >= SYNC_INTERVAL_MS) {
      lastSyncMillis = now;
      syncWithServer();
    }
  } else {
    // Reconnect bez skanowania i bez wyłączania diod
    static unsigned long lastReconnectAttempt = 0;
    if (now - lastReconnectAttempt >= 10000) {
      lastReconnectAttempt = now;
      Serial.printf("[WiFi] Ponowna proba polaczenia z: '%s'...\n", config.wifiSsid);
      WiFi.begin(config.wifiSsid, config.wifiPass);
    }
  }
}

// ============================================================================
// AKTUALIZACJA DIOD LED - ŚWIECĄ STALE
// ============================================================================
void updateLeds(bool isFree) {
  currentAvailability = isFree;
  if (isFree) {
    digitalWrite(PIN_LED_FREE, HIGH); // LED 1 (Zielona) WŁĄCZONA NA STAŁE
    digitalWrite(PIN_LED_BUSY, LOW);  // LED 2 (Czerwona) WYŁĄCZONA
  } else {
    digitalWrite(PIN_LED_FREE, LOW);  // LED 1 (Zielona) WYŁĄCZONA
    digitalWrite(PIN_LED_BUSY, HIGH); // LED 2 (Czerwona) WŁĄCZONA NA STAŁE
  }
}

// Miganie diod TYLKO w trybie parowania (naprzemienne)
void blinkPairingPattern() {
  static unsigned long lastBlink = 0;
  static bool phase = false;
  unsigned long now = millis();
  if (now - lastBlink >= 300) {
    lastBlink = now;
    phase = !phase;
    digitalWrite(PIN_LED_FREE, phase ? HIGH : LOW);
    digitalWrite(PIN_LED_BUSY, phase ? LOW : HIGH);
  }
}

// ============================================================================
// TRYB PAROWANIA / PRZYPISYWANIA SALI
// ============================================================================
void enterPairingMode() {
  isPairingMode = true;
  Serial.println("\n================================================");
  Serial.println(">>> TRYB PRZYPISYWANIA SALI I KONFIGURACJI <<<");
  Serial.println("================================================");

  if (scannedNetworks.empty()) {
    scanNearbyNetworks();
  }

  // Uruchomienie punktu dostępowego Access Point
  String apSsid = "Wemos-Sala-Setup";
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(apSsid.c_str());
  IPAddress apIP = WiFi.softAPIP();

  Serial.print("[AP] Nazwa sieci WiFi (SSID): ");
  Serial.println(apSsid);
  Serial.print("[AP] Adres IP konfiguracji: http://");
  Serial.println(apIP);

  // Captive Portal DNS
  dnsServer.start(DNS_PORT, "*", apIP);

  // Routing serwera WWW
  webServer.on("/", handleRoot);
  webServer.on("/save", HTTP_POST, handleSave);
  webServer.on("/scan", handleScan);
  webServer.onNotFound(handleRoot);
  webServer.begin();

  Serial.println("[AP] Serwer WWW i Portal uruchomiony!");

  // Jeśli połączony z siecią, ogłoś tryb parowania na serwerze API
  if (WiFi.status() == WL_CONNECTED) {
    announcePairingMode();
  }
}

void exitPairingMode() {
  Serial.println("[PAIRING] Zakonczenie trybu parowania.");
  isPairingMode = false;
  dnsServer.stop();
  webServer.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_STA);
  updateLeds(currentAvailability);
}

// ============================================================================
// KOMUNIKACJA Z SERWEREM API (BEARSSL Z OPTYMALIZACJĄ PAMIĘCI RAM)
// ============================================================================

void announcePairingMode() {
  if (WiFi.status() != WL_CONNECTED) return;

  String serverBase = String(config.serverUrl);
  if (serverBase.length() == 0) serverBase = "https://sale.pwojtaszek.5g.in";
  String endpoint = serverBase + "/api/devices/pairing";

  HTTPClient http;
  http.setTimeout(4000);
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);

  bool beginOk = false;
  WiFiClient plainClient;
  WiFiClientSecure secureClient;

  if (endpoint.startsWith("https://")) {
    secureClient.setInsecure();
    secureClient.setBufferSizes(1024, 512); // Zmniejszone bufory TLS (zapobiega crashowi ESP8266)
    beginOk = http.begin(secureClient, endpoint);
  } else {
    beginOk = http.begin(plainClient, endpoint);
  }

  if (beginOk) {
    http.addHeader("Content-Type", "application/json");

    StaticJsonDocument<256> doc;
    doc["deviceId"] = deviceId;
    doc["mac"] = macAddress;
    doc["ip"] = WiFi.localIP().toString();
    doc["isPairing"] = true;

    String jsonStr;
    serializeJson(doc, jsonStr);

    int httpCode = http.POST(jsonStr);
    if (httpCode > 0) {
      Serial.printf("[API] Ogloszenie parowania wyslane (kod %d)\n", httpCode);
    }
    http.end();
  }
}

void sendRoomStatus(bool isFree) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[API] Brak polaczenia WiFi! Nie mozna wyslac stanu.");
    return;
  }

  String serverBase = String(config.serverUrl);
  if (serverBase.length() == 0) serverBase = "https://sale.pwojtaszek.5g.in";
  String endpoint = serverBase + "/api/v1/device/status";

  HTTPClient http;
  http.setTimeout(4000);
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);

  bool beginOk = false;
  WiFiClient plainClient;
  WiFiClientSecure secureClient;

  if (endpoint.startsWith("https://")) {
    secureClient.setInsecure();
    secureClient.setBufferSizes(1024, 512);
    beginOk = http.begin(secureClient, endpoint);
  } else {
    beginOk = http.begin(plainClient, endpoint);
  }

  if (beginOk) {
    http.addHeader("Content-Type", "application/json");
    if (strlen(config.deviceToken) > 0) {
      http.addHeader("Authorization", "Bearer " + String(config.deviceToken));
    }

    StaticJsonDocument<256> doc;
    doc["status"] = isFree ? "free" : "occupied";

    String jsonStr;
    serializeJson(doc, jsonStr);

    int httpCode = http.POST(jsonStr);
    if (httpCode == HTTP_CODE_OK || httpCode == 201) {
      String response = http.getString();
      Serial.println("[API] Sukces aktualizacji stanu sali (/api/v1/device/status): " + response);
    } else {
      Serial.printf("[API] Kod odpowiedzi serwera: %d\n", httpCode);
    }
    http.end();
  }
}

void syncWithServer() {
  if (WiFi.status() != WL_CONNECTED) return;

  String serverBase = String(config.serverUrl);
  if (serverBase.length() == 0) serverBase = "https://sale.pwojtaszek.5g.in";
  String endpoint = serverBase + "/api/v1/device/state";

  HTTPClient http;
  http.setTimeout(4000);
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);

  bool beginOk = false;
  WiFiClient plainClient;
  WiFiClientSecure secureClient;

  if (endpoint.startsWith("https://")) {
    secureClient.setInsecure();
    secureClient.setBufferSizes(1024, 512); // Bezpieczne bufory dla pamieci RAM ESP8266
    beginOk = http.begin(secureClient, endpoint);
  } else {
    beginOk = http.begin(plainClient, endpoint);
  }

  if (beginOk) {
    if (strlen(config.deviceToken) > 0) {
      http.addHeader("Authorization", "Bearer " + String(config.deviceToken));
    }
    http.addHeader("X-Firmware-Version", ESP8266_FIRMWARE_VERSION);
    http.addHeader("X-Chip-Type", "esp8266");

    int httpCode = http.GET();
    if (httpCode == HTTP_CODE_OK) {
      String payload = http.getString();
      StaticJsonDocument<512> doc;
      DeserializationError err = deserializeJson(doc, payload);
      if (!err) {
        // 1. Sprawdzenie i wykonanie automatycznej aktualizacji firmware Auto-OTA
        if (doc.containsKey("firmware") && !doc["firmware"].isNull()) {
          JsonObject fw = doc["firmware"];
          const char* srvVer = fw["version"] | "";
          bool hasUpdate = fw["has_update"] | false;
          String fwUrl = fw["url"] | "";
          if (hasUpdate && strlen(srvVer) > 0 && String(srvVer) != String(ESP8266_FIRMWARE_VERSION) && fwUrl.length() > 0) {
            static unsigned long lastFailedOta = 0;
            if (millis() - lastFailedOta > 60000) {
              Serial.printf("[OTA] Wykryto nowa wersje ESP8266: %s (obecna: %s). Uruchamianie Auto-OTA!\n", srvVer, ESP8266_FIRMWARE_VERSION);
              http.end();
              performAutoOta(fwUrl);
              lastFailedOta = millis();
              return;
            }
          }
        }

        const char* status = doc["status"] | "free";
        const char* roomId = doc["room_id"] | "";
        bool isActive = doc["is_active"] | true;

        if (isActive && strlen(roomId) > 0) {
          roomAssigned = true;
          bool isAvailable = (strcmp(status, "free") == 0);
          if (!isPairingMode) {
            updateLeds(isAvailable);
          }
        }
      }
    } else if (httpCode == 401 || httpCode == 403) {
      Serial.println("[API] Blad autoryzacji tokenu urzadzenia (401/403)!");
    }
    http.end();
  }
}

void performAutoOta(const String& firmwareUrl) {
  if (WiFi.status() != WL_CONNECTED) return;
  Serial.println("[OTA] Rozpoczynanie pobierania Auto-OTA: " + firmwareUrl);

  // Wskazanie rozpoczęcia aktualizacji diodami LED:
  digitalWrite(PIN_LED_FREE, HIGH);
  digitalWrite(PIN_LED_BUSY, HIGH);

  WiFiClientSecure client;
  client.setInsecure();
  client.setBufferSizes(1024, 512);

  ESPhttpUpdate.rebootOnUpdate(true);
  ESPhttpUpdate.setLedPin(PIN_LED_FREE, LOW);

  t_httpUpdate_return ret = ESPhttpUpdate.update(client, firmwareUrl);
  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("[OTA] Blad pobierania (%d): %s\n", ESPhttpUpdate.getLastError(), ESPhttpUpdate.getLastErrorString().c_str());
      digitalWrite(PIN_LED_FREE, LOW);
      digitalWrite(PIN_LED_BUSY, HIGH); // Dioda czerwona sygnalizuje błąd
      break;
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("[OTA] Oprogramowanie jest aktualne.");
      break;
    case HTTP_UPDATE_OK:
      Serial.println("[OTA] Aktualizacja zakonczona pomyslnie! Restartowanie kontrolera...");
      break;
  }
}

// ============================================================================
// STRONA WWW KONFIGURACJI / PORTAL PRZYPISYWANIA SALI
// ============================================================================
void handleRoot() {
  String netChips = "";
  if (scannedNetworks.empty()) {
    netChips = "<p style='color:var(--text-muted);font-size:12px;padding:8px;'>Brak zeskanowanych sieci. Kliknij przycisk poniżej, aby przeskanować.</p>";
  } else {
    for (const auto& net : scannedNetworks) {
      if (net.ssid.length() == 0) continue;
      String lock = net.isEncrypted ? "🔒" : "🔓";
      netChips += "<div class='net-chip' onclick=\"selectSsid('" + net.ssid + "')\">";
      netChips += "<span class='net-name'>📶 " + net.ssid + "</span>";
      netChips += "<span class='net-meta'>" + String(net.rssi) + " dBm " + lock + "</span>";
      netChips += "</div>";
    }
  }

  String html = R"rawliteral(
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sterownik Sali - Politechnika Rzeszowska</title>
  <style>
    :root {
      --bg: #0b132b;
      --card: #1c2541;
      --card-inner: #243054;
      --accent: #ff9f1c;
      --green: #2ec4b6;
      --red: #e71d36;
      --text: #ffffff;
      --text-muted: #9ba1b7;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    body { background: var(--bg); color: var(--text); padding: 16px; display: flex; justify-content: center; }
    .container { width: 100%; max-width: 480px; }
    .header { text-align: center; margin-bottom: 20px; }
    .badge { display: inline-block; background: rgba(255,159,28,0.15); color: var(--accent); padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; text-transform: uppercase; margin-bottom: 8px; border: 1px solid rgba(255,159,28,0.3); }
    h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
    p.sub { color: var(--text-muted); font-size: 13px; }
    .card { background: var(--card); border-radius: 16px; padding: 20px; margin-bottom: 16px; box-shadow: 0 8px 24px rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.06); }
    .card-title { font-size: 15px; font-weight: 600; margin-bottom: 14px; display: flex; align-items: center; gap: 8px; color: var(--accent); }
    .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 10px; }
    .info-item { background: var(--card-inner); padding: 10px; border-radius: 10px; }
    .info-label { font-size: 11px; color: var(--text-muted); text-transform: uppercase; }
    .info-value { font-size: 14px; font-weight: 600; margin-top: 2px; }
    .form-group { margin-bottom: 14px; }
    label { display: block; font-size: 13px; font-weight: 500; margin-bottom: 6px; color: var(--text-muted); }
    input, select { width: 100%; padding: 12px 14px; background: var(--card-inner); border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; color: #fff; font-size: 14px; outline: none; transition: 0.2s; }
    input:focus, select:focus { border-color: var(--accent); box-shadow: 0 0 0 2px rgba(255,159,28,0.2); }
    .quick-rooms { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
    .room-chip { background: var(--card-inner); border: 1px solid rgba(255,255,255,0.12); border-radius: 8px; padding: 6px 10px; font-size: 12px; font-weight: 600; cursor: pointer; transition: 0.15s; }
    .room-chip:hover, .room-chip.active { background: var(--accent); color: #000; border-color: var(--accent); }
    
    .net-list { display: flex; flex-direction: column; gap: 6px; max-height: 180px; overflow-y: auto; margin-bottom: 8px; padding-right: 4px; }
    .net-chip { background: var(--card-inner); border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 8px 12px; font-size: 13px; display: flex; justify-content: space-between; align-items: center; cursor: pointer; transition: 0.15s; }
    .net-chip:hover { border-color: var(--accent); background: rgba(255,159,28,0.1); }
    .net-chip .net-name { font-weight: 600; color: #fff; }
    .net-chip .net-meta { font-size: 11px; color: var(--text-muted); }
    .btn-scan { background: var(--card-inner); color: var(--accent); font-size: 12px; font-weight: 600; padding: 8px 14px; width: 100%; border-radius: 8px; border: 1px solid rgba(255,159,28,0.3); cursor: pointer; transition: 0.2s; }
    .btn-scan:hover { background: rgba(255,159,28,0.15); }

    .btn { width: 100%; padding: 14px; border: none; border-radius: 12px; font-size: 15px; font-weight: 700; cursor: pointer; transition: 0.2s; text-align: center; text-decoration: none; display: block; }
    .btn-primary { background: linear-gradient(135deg, #ff9f1c, #ff6b00); color: #fff; box-shadow: 0 4px 16px rgba(255,159,28,0.4); margin-top: 10px; }
    .btn-primary:active { transform: scale(0.98); }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="badge">Wemos D1 Mini - ESP8266</div>
      <h1>Sterownik Dostępności Sal</h1>
      <p class="sub">Politechnika Rzeszowska - System Sal</p>
    </div>

    <div class="card">
      <div class="card-title">ℹ️ Informacje o urządzeniu</div>
      <div class="info-grid">
        <div class="info-item">
          <div class="info-label">ID Urządzenia</div>
          <div class="info-value">)rawliteral" + deviceId + R"rawliteral(</div>
        </div>
        <div class="info-item">
          <div class="info-label">Adres MAC</div>
          <div class="info-value">)rawliteral" + macAddress + R"rawliteral(</div>
        </div>
      </div>
      <div class="info-item">
        <div class="info-label">Obecnie Przypisana Sala</div>
        <div class="info-value" style="color: var(--accent); font-size: 16px;">
          )rawliteral" + (strlen(config.roomNumber) > 0 ? String(config.roomNumber) : String("Brak - Wymaga przypisania")) + R"rawliteral(
        </div>
      </div>
    </div>

    <form method="POST" action="/save">
      <div class="card">
        <div class="card-title">📍 Przypisanie do Sali</div>
        <div class="form-group">
          <label>Wybierz z listy lub wpisz numer:</label>
          <input type="text" id="roomNumber" name="roomNumber" value=")rawliteral" + String(config.roomNumber) + R"rawliteral(" placeholder="np. 114, 118_119, Aula 111" required>
          <div class="quick-rooms">
            <span class="room-chip" onclick="setRoom('Aula 103_104')">Aula 103_104</span>
            <span class="room-chip" onclick="setRoom('Aula 111')">Aula 111</span>
            <span class="room-chip" onclick="setRoom('105')">105</span>
            <span class="room-chip" onclick="setRoom('106')">106</span>
            <span class="room-chip" onclick="setRoom('107')">107</span>
            <span class="room-chip" onclick="setRoom('108')">108</span>
            <span class="room-chip" onclick="setRoom('109')">109</span>
            <span class="room-chip" onclick="setRoom('112')">112</span>
            <span class="room-chip" onclick="setRoom('113')">113</span>
            <span class="room-chip" onclick="setRoom('114')">114</span>
            <span class="room-chip" onclick="setRoom('115')">115</span>
            <span class="room-chip" onclick="setRoom('116')">116</span>
            <span class="room-chip" onclick="setRoom('117')">117</span>
            <span class="room-chip" onclick="setRoom('118_119')">118_119</span>
            <span class="room-chip" onclick="setRoom('120_121')">120_121</span>
            <span class="room-chip" onclick="setRoom('122')">122</span>
            <span class="room-chip" onclick="setRoom('123')">123</span>
            <span class="room-chip" onclick="setRoom('124')">124</span>
            <span class="room-chip" onclick="setRoom('125')">125</span>
            <span class="room-chip" onclick="setRoom('1')">1</span>
            <span class="room-chip" onclick="setRoom('2')">2</span>
            <span class="room-chip" onclick="setRoom('3')">3</span>
            <span class="room-chip" onclick="setRoom('4')">4</span>
            <span class="room-chip" onclick="setRoom('5')">5</span>
            <span class="room-chip" onclick="setRoom('6')">6</span>
            <span class="room-chip" onclick="setRoom('7')">7</span>
            <span class="room-chip" onclick="setRoom('8')">8</span>
            <span class="room-chip" onclick="setRoom('9')">9</span>
            <span class="room-chip" onclick="setRoom('10')">10</span>
            <span class="room-chip" onclick="setRoom('11')">11</span>
            <span class="room-chip" onclick="setRoom('12_13')">12_13</span>
            <span class="room-chip" onclick="setRoom('14_15')">14_15</span>
            <span class="room-chip" onclick="setRoom('16')">16</span>
            <span class="room-chip" onclick="setRoom('17')">17</span>
            <span class="room-chip" onclick="setRoom('18')">18</span>
            <span class="room-chip" onclick="setRoom('19')">19</span>
            <span class="room-chip" onclick="setRoom('20')">20</span>
            <span class="room-chip" onclick="setRoom('24')">24</span>
            <span class="room-chip" onclick="setRoom('Portiernia')">Portiernia</span>
            <span class="room-chip" onclick="setRoom('Kafeteria')">Kafeteria</span>
            <span class="room-chip" onclick="setRoom('HOL')">HOL</span>
            <span class="room-chip" onclick="setRoom('Garaż')">Garaż</span>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-title">📶 Wykryte Sieci WiFi w Okolicy</div>
        <label>Kliknij sieć, aby automatycznie uzupełnić nazwę:</label>
        <div class="net-list" id="networksList">
          )rawliteral" + netChips + R"rawliteral(
        </div>
        <button type="button" class="btn-scan" onclick="rescanWifi()">🔄 Skanuj ponownie sieci</button>

        <div style="margin-top: 16px;"></div>
        <div class="form-group">
          <label>Nazwa sieci WiFi (SSID):</label>
          <input type="text" id="wifiSsid" name="wifiSsid" value=")rawliteral" + String(config.wifiSsid) + R"rawliteral(" placeholder="Kliknij sieć powyżej lub wpisz" required>
        </div>
        <div class="form-group">
          <label>Hasło WiFi:</label>
          <input type="password" id="wifiPass" name="wifiPass" value=")rawliteral" + String(config.wifiPass) + R"rawliteral(" placeholder="Pozostaw puste jeśli sieć otwarta">
        </div>
      </div>

      <div class="card">
        <div class="card-title">🌐 Serwer API</div>
        <div class="form-group">
          <label>Adres URL serwera:</label>
          <input type="text" id="serverUrl" name="serverUrl" value=")rawliteral" + (strlen(config.serverUrl) > 0 ? String(config.serverUrl) : String("https://sale.pwojtaszek.5g.in")) + R"rawliteral(" required>
        </div>
        <div class="form-group">
          <label>Token autoryzacyjny ESP (z panelu administratora):</label>
          <input type="text" id="deviceToken" name="deviceToken" value=")rawliteral" + String(config.deviceToken) + R"rawliteral(" placeholder="np. dev_token_sala104">
        </div>
        <button type="submit" class="btn btn-primary">💾 Zapisz i Połącz z Salą</button>
      </div>
    </form>
  </div>

  <script>
    function setRoom(num) {
      document.getElementById('roomNumber').value = num;
      document.querySelectorAll('.room-chip').forEach(el => {
        el.classList.toggle('active', el.innerText === num);
      });
    }

    function selectSsid(name) {
      document.getElementById('wifiSsid').value = name;
      document.getElementById('wifiPass').focus();
    }

    function rescanWifi() {
      const btn = document.querySelector('.btn-scan');
      btn.innerText = '⏳ Skanowanie pasma WiFi 2.4 GHz...';
      fetch('/scan')
        .then(r => r.json())
        .then(data => {
          btn.innerText = '🔄 Skanuj ponownie sieci';
          const container = document.getElementById('networksList');
          if (!container) return;
          container.innerHTML = '';
          if (!data.networks || data.networks.length === 0) {
            container.innerHTML = "<p style='color:var(--text-muted);font-size:12px;padding:8px;'>Brak wykrytych sieci.</p>";
            return;
          }
          data.networks.forEach(net => {
            if (!net.ssid) return;
            const div = document.createElement('div');
            div.className = 'net-chip';
            div.onclick = () => selectSsid(net.ssid);
            div.innerHTML = `<span class='net-name'>📶 ${net.ssid}</span><span class='net-meta'>${net.rssi} dBm ${net.secure ? '🔒' : '🔓'}</span>`;
            container.appendChild(div);
          });
        })
        .catch(() => {
          btn.innerText = '🔄 Błąd (kliknij, aby spróbować ponownie)';
        });
    }
  </script>
</body>
</html>
)rawliteral";

  webServer.send(200, "text/html", html);
}

void handleSave() {
  if (webServer.hasArg("roomNumber")) {
    String room = webServer.arg("roomNumber");
    room.trim();
    strncpy(config.roomNumber, room.c_str(), sizeof(config.roomNumber) - 1);
  }
  if (webServer.hasArg("wifiSsid")) {
    String ssid = webServer.arg("wifiSsid");
    ssid.trim();
    strncpy(config.wifiSsid, ssid.c_str(), sizeof(config.wifiSsid) - 1);
  }
  if (webServer.hasArg("wifiPass")) {
    String pass = webServer.arg("wifiPass");
    strncpy(config.wifiPass, pass.c_str(), sizeof(config.wifiPass) - 1);
  }
  if (webServer.hasArg("serverUrl")) {
    String srv = webServer.arg("serverUrl");
    srv.trim();
    if (srv.endsWith("/")) srv.remove(srv.length() - 1);
    strncpy(config.serverUrl, srv.c_str(), sizeof(config.serverUrl) - 1);
  }
  if (webServer.hasArg("deviceToken")) {
    String tok = webServer.arg("deviceToken");
    tok.trim();
    strncpy(config.deviceToken, tok.c_str(), sizeof(config.deviceToken) - 1);
  }

  saveConfig();

  String html = R"rawliteral(
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Zapisano pomyślnie</title>
  <style>
    body { background: #0b132b; color: #fff; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; text-align: center; padding: 20px; }
    .card { background: #1c2541; padding: 30px; border-radius: 16px; max-width: 400px; box-shadow: 0 8px 30px rgba(0,0,0,0.5); }
    h2 { color: #2ec4b6; margin-bottom: 12px; }
    p { color: #9ba1b7; line-height: 1.5; margin-bottom: 20px; }
    .room-badge { font-size: 20px; font-weight: bold; color: #ff9f1c; margin: 10px 0; }
  </style>
</head>
<body>
  <div class="card">
    <h2>✅ Zapisano pomyślnie!</h2>
    <p>Przypisano urządzenie do sali:</p>
    <div class="room-badge">)rawliteral" + String(config.roomNumber) + R"rawliteral(</div>
    <p>Sterownik łączy się z wybraną siecią WiFi i rozpoczyna pracę. Możesz zamknąć tę stronę.</p>
  </div>
</body>
</html>
)rawliteral";

  webServer.send(200, "text/html", html);
  delay(1000);

  exitPairingMode();
  WiFi.begin(config.wifiSsid, config.wifiPass);
}

void handleScan() {
  scanNearbyNetworks();
  StaticJsonDocument<2048> doc;
  JsonArray arr = doc.createNestedArray("networks");
  for (const auto& net : scannedNetworks) {
    if (net.ssid.length() == 0) continue;
    JsonObject obj = arr.createNestedObject();
    obj["ssid"] = net.ssid;
    obj["rssi"] = net.rssi;
    obj["secure"] = net.isEncrypted;
    obj["channel"] = net.channel;
  }
  String json;
  serializeJson(doc, json);
  webServer.send(200, "application/json", json);
}

// ============================================================================
// OBSŁUGA EEPROM
// ============================================================================
void loadConfig() {
  EEPROM.get(0, config);
  if (config.magic != EEPROM_MAGIC) {
    Serial.println("[EEPROM] Pamięć czysta lub brak konfiguracji. Ładowanie domyślnych wartości.");
    memset(&config, 0, sizeof(config));
    config.magic = EEPROM_MAGIC;
    strncpy(config.serverUrl, "https://sale.pwojtaszek.5g.in", sizeof(config.serverUrl) - 1);
    strncpy(config.deviceToken, "dev_token_sala104", sizeof(config.deviceToken) - 1);
    config.roomId = 0;
    saveConfig();
  } else {
    Serial.println("[EEPROM] Pomyślnie załadowano konfigurację:");
    Serial.printf("  WiFi SSID: %s\n", config.wifiSsid);
    Serial.printf("  Serwer: %s\n", config.serverUrl);
    Serial.printf("  Token: %s\n", config.deviceToken);
    Serial.printf("  Sala: %s (ID: %d)\n", config.roomNumber, config.roomId);
  }
}

void saveConfig() {
  config.magic = EEPROM_MAGIC;
  EEPROM.put(0, config);
  EEPROM.commit();
  Serial.println("[EEPROM] Konfiguracja zapisana w pamięci flash.");
}
