# Dostępność Sal - Politechnika Rzeszowska

[![Flutter](https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)
[![SQLite](https://img.shields.io/badge/SQLite-3-003B57?logo=sqlite&logoColor=white)](https://sqlite.org)
[![ESP8266](https://img.shields.io/badge/ESP8266-Wemos%20D1%20mini-E7352C?logo=espressif&logoColor=white)](https://www.espressif.com)
[![Version](https://img.shields.io/badge/Wersja-1.3.12%20(Code%2017)-brightgreen)](#)

Kompleksowy system monitorowania, wizualizacji na planie architektonicznym oraz zarządzania dostępnością sal wykładowych, laboratoriów i stref specjalnych (w tym wystawy pojazdów w Garażu) w budynku Politechniki Rzeszowskiej.

---

## 🚀 Główne Funkcjonalności

- 🗺️ **Wektorowy Plan Budynku (Auto-Fit & Zoom)**: Dynamiczny, wektorowy rzut Parteru i I Piętra dopasowujący się automatycznie do dowolnego ekranu z obsługą głębokiego zoomu (0.25x - 3.5x).
- 🚗 **Garaż na Parterze**: Dostępność strefy pojazdów zabytkowych wkomponowana w centralny dziedziniec Parteru.
- ✏️ **Tryb Edycji Rozkładu Sal**: Przeciąganie sal po planie i zapis współrzędnych do bazy w czasie rzeczywistym.
- 📺 **Tryb TV / Kiosk Dashboard**: Pełnoekranowy widok na duże telewizory z zegarem `HH:mm:ss`, statystykami sal i płynnym paskiem informacyjnym (ticker).
- 🔄 **Hybrydowa Synchronizacja LAN + Cloud**: Bezproblemowe działanie w sieci lokalnej (UDP Auto-Discovery na porcie 8082) oraz w Internecie przez szyfrowany tunel HTTPS ([https://sale.pwojtaszek.5g.in](https://sale.pwojtaszek.5g.in)).
- 📱 **Automatyczne Aktualizacje OTA (Android)**: Wbudowany sprawdzacz nowej wersji, pasek pobierania APK i instalacja.
- 💡 **Węzły IoT ESP8266 Wemos D1 mini**: Skaner sieci Wi-Fi i sprzętowa sygnalizacja statusu diodami LED.

---

## 📁 Przewodniki i Dokumentacja dla AI i Programistów

Szczegółowa dokumentacja techniczna znajduje się w dedykowanych plikach:

| Plik | Opis |
|---|---|
| [**`AI_CODEBASE_SUMMARY.md`**](AI_CODEBASE_SUMMARY.md) | **Główny podręcznik dla modeli AI**: Pełna architektura, diagramy Mermaid, schematy bazy SQLite, mapowanie komponentów i stanów |
| [**`DEVELOPER_GUIDE.md`**](DEVELOPER_GUIDE.md) | **Instrukcja uruchomienia i kompilacji**: Krok po kroku na nowym komputerze (Web, Android APK, Python, Cloudflare, ESP8266) |
| [**`API_REFERENCE.md`**](API_REFERENCE.md) | **Specyfikacja API**: Wszystkie endpointy REST, formaty JSON, nagłówki CORS i protokół UDP 8082 |
| [**`ROADMAP.md`**](ROADMAP.md) | **Plan rozwoju**: Zrealizowane kamienie milowe oraz proponowane kolejne zadania i ulepszenia |
| [**`TUNNEL_TOKEN.md`**](TUNNEL_TOKEN.md) | **Tunel `victus`**: jak przekazać projekt lub sam plik tokenu innej osobie |

---

## ⚡ Szybki Start na Nowym Urządzeniu (1 Kliknięciem)

Wystarczy przenieść ten folder na dowolny komputer z systemem Windows i uruchomić:
```cmd
PRZYGOTUJ_KOMPUTER.bat
```
Ten jeden plik automatycznie:
1. Sprawdza i w razie potrzeby instaluje środowisko **Python 3**.
2. Weryfikuje przenośny plik `cloudflared.exe` i token `.cloudflared/victus.token` w folderze projektu.
3. Pobiera pakiety Flutter (`flutter pub get`).
4. Tworzy skrót **"Uruchom Serwer Sal"** na Pulpicie nowego komputera.

Po zakończeniu działania tego jednego pliku komputer jest w 100% gotowy do pracy, a serwer i aplikacja natychmiast dostępne!

---

### Uruchomienie Serwera i Tunelu
W dowolnym momencie uruchom:
```cmd
run_server_and_tunnel.bat
```
(lub kliknij skrót na Pulpicie). Skrypt uruchomi usługi w tle i otworzy stronę [https://sale.pwojtaszek.5g.in](https://sale.pwojtaszek.5g.in).

---

## 🛠️ Zbudowane Narzędziami
- **Frontend**: Flutter / Dart
- **Backend**: Python 3 (wbudowany moduł `http.server` & `socketserver`)
- **Baza danych**: SQLite (`rooms_backend.db`)
- **Sieć**: Cloudflare Tunnel (`cloudflared`) + UDP Broadcast Beacon
- **Hardware**: ESP8266 (Wemos D1 mini / Arduino C++)
