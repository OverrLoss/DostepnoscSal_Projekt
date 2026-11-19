# Specyfikacja API i Protokołów Komunikacyjnych (API Reference)

Serwer backendowy (`server/sync_server.py`) udostępnia interfejs REST API na porcie `8081` (lub przez HTTPS pod adresem [https://sale.pwojtaszek.5g.in](https://sale.pwojtaszek.5g.in)) oraz responder UDP na porcie `8082`.

---

## 1. Punkty Końcowe REST API

### 1.1. Pobieranie listy sal: `GET /api/rooms`
Zwraca listę sal zarejestrowanych w systemie.

- **Parametry zapytania (opcjonalne)**:
  - `floor`: Filtr piętra, np. `Parter`, `Piętro`, `Wszystkie`.  
    *Uwaga: Gdy podano `floor=Parter`, odpowiedź zawiera również salę `Garaż podziemny`.*
  - `status`: Filtr dostępności: `free` (tylko wolne) lub `occupied` (tylko zajęte).

- **Przykładowa odpowiedź (`200 OK`)**:
```json
[
  {
    "id": 11,
    "number": "9",
    "name": "Bryłki bez kleju",
    "floor": "Parter",
    "isAvailable": true,
    "category": "EXTRAS",
    "description": "Warsztaty kreatywne dla dzieci i młodzieży",
    "capacity": 30,
    "customNote": "",
    "updatedAt": "2026-10-19T14:40:20.873800+00:00",
    "posX": null,
    "posY": null,
    "sortOrder": 0
  },
  {
    "id": 15,
    "number": "Garaż",
    "name": "Wystawa pojazdów zabytkowych",
    "floor": "Garaż podziemny",
    "isAvailable": false,
    "category": "Wystawa",
    "description": "Ekspozycja unikalnych pojazdów i motocykli zabytkowych",
    "capacity": 100,
    "customNote": "",
    "updatedAt": "2026-10-19T14:40:20.873800+00:00",
    "posX": 65.0,
    "posY": 325.0,
    "sortOrder": 0
  }
]
```

---

### 1.2. Aktualizacja lub dodanie sali: `POST /api/rooms`
Tworzy nową salę lub aktualizuje istniejącą na podstawie numeru sali (`number`).

- **Ciało żądania (`application/json`)**:
```json
{
  "number": "104",
  "name": "Gwiezdne Wojny",
  "floor": "Piętro",
  "category": "EXTRAS",
  "description": "Pokazy tematyczne Star Wars i robotyki kosmicznej",
  "capacity": 25,
  "isAvailable": 1,
  "customNote": "Zajęcia od 11:00",
  "posX": 120.5,
  "posY": 85.0
}
```

- **Odpowiedź (`200 OK`)**:
```json
{
  "status": "success",
  "message": "Room saved successfully",
  "id": 1
}
```

---

### 1.3. Szybkie przełączenie dostępności: `POST /api/rooms/toggle`
Zmienia stan sali (`isAvailable`) na przeciwny.

- **Ciało żądania (`application/json`)**:
```json
{
  "number": "104"
}
```

- **Odpowiedź (`200 OK`)**:
```json
{
  "status": "success",
  "number": "104",
  "isAvailable": false,
  "updatedAt": "2026-10-20T08:00:00.000000+00:00"
}
```

---

### 1.4. Usuwanie sali: `DELETE /api/rooms?number=104` lub `DELETE /api/rooms?id=1`
Usuwa salę o podanym numerze lub ID.

- **Odpowiedź (`200 OK`)**:
```json
{
  "status": "success",
  "message": "Room deleted successfully"
}
```

---

### 1.5. Sprawdzanie aktualizacji aplikacji: `GET /api/app-version`
Używane przez klienta Android do automatycznego wykrywania nowej wersji `.apk`.

- **Przykładowa odpowiedź (`200 OK`)**:
```json
{
  "versionCode": 4,
  "versionName": "1.2.0",
  "apkUrl": "https://sale.pwojtaszek.5g.in/DostepnoscSal.apk",
  "apkSize": 54795717,
  "releaseNotes": "• Nowy widok wszystkich pięter na jednym ekranie (Tryb TV / Kiosk)\n• Ulepszone wyświetlanie mapy w przeglądarce i przeniesienie przycisku układu sal\n• Automatyczne pobieranie adresu serwera w sieci lokalnej Wi-Fi\n• Skaner sieci Wi-Fi i integracja ESP8266 Wemos D1 mini",
  "updatedAt": "2026-10-20T07:40:54.929856+00:00"
}
```

---

### 1.6. Informacje o sieci i serwerze: `GET /api/server-info`
Zwraca adresy IP oraz URL-e serwera w sieci lokalnej oraz w Internecie.

- **Przykładowa odpowiedź (`200 OK`)**:
```json
{
  "lanUrl": "http://10.90.250.195:8081",
  "lanIp": "10.90.250.195",
  "port": 8081,
  "allLanUrls": [
    "http://10.90.250.195:8081"
  ],
  "publicUrl": "https://sale.pwojtaszek.5g.in"
}
```

---

### 1.7. Sprawdzenie stanu (Healthcheck): `GET /api/health`
Prosty test gotowości serwera.

- **Przykładowa odpowiedź (`200 OK`)**:
```json
{
  "status": "ok",
  "service": "RoomAvailabilitySyncServer",
  "version": "1.1.1",
  "time": "2026-10-20T07:41:32.114934+00:00",
  "lanUrl": "http://10.90.250.195:8081",
  "lanIp": "10.90.250.195",
  "port": 8081,
  "publicUrl": "https://sale.pwojtaszek.5g.in"
}
```

---

### 1.8. Statystyki obłożenia: `GET /api/stats`
Podsumowanie liczby sal wolnych i zajętych w podziale na piętra.

- **Przykładowa odpowiedź (`200 OK`)**:
```json
{
  "stats": {
    "Parter": { "total": 5, "free": 3, "occupied": 2 },
    "Piętro": { "total": 10, "free": 8, "occupied": 2 },
    "Garaż podziemny": { "total": 1, "free": 0, "occupied": 1 }
  },
  "overall": {
    "total": 16,
    "free": 11,
    "occupied": 5
  }
}
```

---

### 1.9. Raport urządzenia IoT: `POST /api/esp8266/report`
Opcjonalny punkt końcowy dla mikrokontrolerów ESP8266 przesyłających raport ze skanowania otoczenia Wi-Fi.

- **Ciało żądania (`application/json`)**:
```json
{
  "chipId": "ESP8266_A1B2C3",
  "ip": "10.90.250.210",
  "assignedRoom": "104",
  "networksFound": 5,
  "rssi": -65
}
```

---

## 2. Protokół Rozgłoszeniowy UDP (Auto-Discovery)

Serwer nasłuchuje na porcie UDP `8082`.

1. **Klient wysyła zapytanie (Broadcast)**:
   - Adres docelowy: `255.255.255.255:8082`
   - Treść pakietu (tekst UTF-8):
     ```
     DISCOVER_ROOM_SERVER
     ```

2. **Serwer odsyła odpowiedź (Unicast na adres klienta)**:
   - Treść odpowiedzi (JSON):
     ```json
     {
       "type": "ROOM_SERVER_ANNOUNCEMENT",
       "lanIp": "10.90.250.195",
       "port": 8081,
       "lanUrl": "http://10.90.250.195:8081"
     }
     ```

3. **Rezultat**:
   Aplikacja automatycznie konfiguruje zmienną `serverUrl` na otrzymany `lanUrl`, zapewniając płynną synchronizację w sieci lokalnej bez ręcznej konfiguracji.
