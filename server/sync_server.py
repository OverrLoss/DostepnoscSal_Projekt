"""
Dostępność Sal - FastAPI Backend Server (Kontrakt v0.1)
Politechnika Rzeszowska
"""

import os
import sys
import json
import uuid
import hmac
import time
import socket
import sqlite3
import asyncio
import hashlib
import secrets
import threading
import platform
import re
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Any

from fastapi import (
    FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException,
    Header, Request, status
)
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uvicorn

# Configuration
PORT = int(os.environ.get("PORT", 8081))
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
WEB_DIR = os.path.join(PROJECT_ROOT, "build", "web")
DB_PATH = os.environ.get("DB_PATH") or os.path.join(BASE_DIR, "rooms_backend.db")
SECRET_KEY = os.environ.get("SERVER_SECRET_KEY") or secrets.token_hex(32)
SERVER_START_TIME = datetime.now(timezone.utc)
APP_VERSION_FILE = os.path.join(BASE_DIR, "app_version.json")

def _load_app_version() -> dict:
    """Load app version metadata from app_version.json.
    Falls back to hardcoded defaults if file is missing or malformed.
    Uses utf-8-sig encoding to tolerate BOM written by PowerShell/Windows tools.
    """
    for enc in ("utf-8-sig", "utf-8"):
        try:
            if os.path.exists(APP_VERSION_FILE):
                with open(APP_VERSION_FILE, encoding=enc) as f:
                    data = json.load(f)
                if "versionCode" in data and "versionName" in data:
                    return data
        except Exception:
            continue
    # Hardcoded fallback — will be overwritten by deploy_apk.py on each build
    return {
        "versionCode": 33,
        "versionName": "1.3.28",
        "releaseNotes": "Nowa wersja jest dostępna.",
        "apkUrl": None,
        "apkSize": None,
    }

# Utility functions
def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_iso(ts_str: str) -> datetime:
    if ts_str.endswith("Z"):
        ts_str = ts_str[:-1] + "+00:00"
    return datetime.fromisoformat(ts_str)

def hash_password(password: str, salt: Optional[str] = None) -> str:
    if not salt:
        salt = secrets.token_hex(16)
    hashed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000)
    return f"{salt}:{hashed.hex()}"

def verify_password(password: str, stored_hash: str) -> bool:
    try:
        salt, expected_hex = stored_hash.split(":")
        check_hash = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000).hex()
        return hmac.compare_digest(check_hash, expected_hex)
    except Exception:
        return False

def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()

DEVICE_TYPES = ("controller", "kiosk", "display")
PAIR_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
PAIR_CODE_LENGTH = 6

def normalize_pair_code(code: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (code or "").upper())

def is_valid_pair_code(code: str) -> bool:
    return (
        len(code) == PAIR_CODE_LENGTH
        and all(char in PAIR_CODE_ALPHABET for char in code)
    )

def new_pair_code(cursor: sqlite3.Cursor) -> str:
    """Generuje nieużywany, krótki kod identyfikacyjny urządzenia."""
    for _ in range(50):
        code = "".join(secrets.choice(PAIR_CODE_ALPHABET) for _ in range(PAIR_CODE_LENGTH))
        exists = cursor.execute(
            "SELECT 1 FROM devices WHERE pair_code_hash = ?",
            (hash_token(code),)
        ).fetchone()
        if not exists:
            return code
    raise RuntimeError("Nie udało się wygenerować unikalnego kodu urządzenia.")

def get_primary_lan_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

# Database Connection
def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=10.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    try:
        yield conn
    finally:
        conn.close()

def get_db_direct():
    conn = sqlite3.connect(DB_PATH, timeout=10.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn

# Database Initialization & Migration
INITIAL_ROOMS = [
    {"number": "104", "name": "Gwiezdne Wojny", "floor": "Piętro", "category": "EXTRAS", "description": "Pokazy tematyczne Star Wars i robotyki kosmicznej", "capacity": 25, "posX": 70.0, "posY": 60.0},
    {"number": "Aula 111", "name": "Aula 111", "floor": "Piętro", "category": "Wykładowa", "description": "Aula główna (I piętro)", "capacity": 150, "posX": 200.0, "posY": 60.0},
    {"number": "Aula 101_102", "name": "Aula 101_102", "floor": "Piętro", "category": "Wykładowa", "description": "Sale 101 i 102 (łączone)", "capacity": 100, "posX": 70.0, "posY": 60.0},
    {"number": "Aula 103_104", "name": "Aula 103_104", "floor": "Piętro", "category": "Wykładowa", "description": "Sale 103 i 104 (łączone)", "capacity": 100, "posX": 135.0, "posY": 60.0},
    {"number": "112", "name": "Druk 3D", "floor": "Piętro", "category": "Laboratorium", "description": "Warsztaty druku 3D", "capacity": 20, "posX": 70.0, "posY": 160.0},
    {"number": "113", "name": "Zabawa światłem", "floor": "Piętro", "category": "Laboratorium", "description": "Optyka i lasery", "capacity": 20, "posX": 200.0, "posY": 160.0},
    {"number": "115", "name": "Projektowanie CAD", "floor": "Piętro", "category": "Laboratorium", "description": "Inżynieria komputerowa", "capacity": 25, "posX": 70.0, "posY": 240.0},
    {"number": "116", "name": "Chemiczne czary", "floor": "Piętro", "category": "Laboratorium", "description": "Eksperymenty chemiczne", "capacity": 25, "posX": 200.0, "posY": 240.0},
    {"number": "117", "name": "Elektronika", "floor": "Piętro", "category": "Laboratorium", "description": "Lutowanie i układy", "capacity": 20, "posX": 70.0, "posY": 320.0},
    {"number": "118", "name": "Gry internetowe", "floor": "Piętro", "category": "Laboratorium", "description": "Stanowiska sieciowe", "capacity": 25, "posX": 200.0, "posY": 320.0},
    {"number": "120", "name": "Robota czy roboty?", "floor": "Piętro", "category": "Laboratorium", "description": "Roboty przemysłowe", "capacity": 20, "posX": 70.0, "posY": 400.0},
    {"number": "122", "name": "Latać każdy może", "floor": "Piętro", "category": "Laboratorium", "description": "Symulatory lotu", "capacity": 25, "posX": 200.0, "posY": 400.0},
    {"number": "9", "name": "Bryłki bez kleju", "floor": "Parter", "category": "EXTRAS", "description": "Warsztaty origami i brył", "capacity": 30, "posX": 70.0, "posY": 100.0},
    {"number": "12", "name": "Zagraj w piłkarzyki", "floor": "Parter", "category": "EXTRAS", "description": "Strefa rekreacyjna", "capacity": 20, "posX": 195.0, "posY": 250.0},
    {"number": "14", "name": "Wirtualny świat", "floor": "Parter", "category": "Laboratorium", "description": "Gogle VR", "capacity": 15, "posX": 195.0, "posY": 195.0},
    {"number": "HOL", "name": "Piasek kinetyczny", "floor": "Parter", "category": "EXTRAS", "description": "Strefa wejściowa", "capacity": 80, "posX": 70.0, "posY": 220.0},
    {"number": "Garaż", "name": "Wystawa pojazdów zabytkowych", "floor": "Garaż podziemny", "category": "Wystawa", "description": "Ekspozycja zabytkowych aut", "capacity": 100, "posX": 65.0, "posY": 325.0}
]

# Przypisanie sal do wielokątów rzutów SVG. Numery 1xx/0xx potwierdzone
# w rozkładach zajęć WMT Stalowa Wola; pozostałe zachowane z poprzedniej wersji.
def operator_login(room_no: str) -> str:
    """Login operatora bez spacji i polskich znaków (szybkie profile testowe)."""
    slug = room_no.lower().replace(" ", "")
    for pl, ascii_ in (("ż", "z"), ("ź", "z"), ("ó", "o"), ("ł", "l"), ("ę", "e"),
                       ("ą", "a"), ("ś", "s"), ("ć", "c"), ("ń", "n")):
        slug = slug.replace(pl, ascii_)
    return "operator_" + slug


SVG_ASSIGNED = {
    "Piętro": {
        "Aula 111": "room-1-38", "Aula 101_102": "room-1-20", "Aula 103_104": "room-1-24",
        "105": "room-1-25", "106": "room-1-28", "107": "room-1-29", "108": "room-1-32",
        "109": "room-1-33",
        "112": "room-1-39", "113": "room-1-42", "114": "room-1-43", "115": "room-1-44",
        "116": "room-1-45", "117": "room-1-46",
        "118_119": "room-1-47", "120_121": "room-1-49", "122": "room-1-51",
        "123": "room-1-07", "124": "room-1-09", "125": "room-1-10",
    },
    "Parter": {
        "1": "room-0-06", "2": "room-0-07", "3": "room-0-08",
        "4": "room-0-10b", "5": "room-0-10", "6": "room-0-11", "7": "room-0-12",
        "8": "room-0-28", "9": "room-0-29", "10": "room-0-30",
        "11": "room-0-31", "12": "room-0-32", "13_14": "room-0-33",
        "15_16": "room-0-35", "17": "room-0-36b", "18": "room-0-44",
        "19": "room-0-45", "20": "room-0-46", "24": "room-0-60",
        "25": "room-0-61", "26": "room-0-62", "27": "room-0-63", "28": "room-0-64",
        "29": "room-0-65", "30": "room-0-66", "31": "room-0-67", "32": "room-0-68",
        "Portiernia": "room-0-57", "Kafeteria": "room-0-27",
    },
}
SVG_REMOVED = {"room-1-11", "room-1-15", "room-1-21", "room-1-22", "room-1-23",
               "room-1-26", "room-1-27", "room-1-30", "room-0-47", "room-0-51",
               "room-1-06", "room-1-08", "room-1-16", "room-1-18", "room-1-34", "room-1-35",
               "room-1-36", "room-1-37", "room-1-41", "room-1-48", "room-1-50",
               "room-1-52", "room-1-53", "room-1-54",
               "room-0-37", "room-0-38", "room-0-40", "room-0-41", "room-0-43",
               "room-0-45b", "room-0-52", "room-0-54", "room-0-55",
                "room-0-58", "room-0-59",
                "room-0-14", "room-0-16", "room-0-04", "room-0-05",
                "room-0-26", "room-0-25", "room-0-23", "room-0-22", "room-0-21", "room-0-20",
                "room-0-09", "room-0-34", "room-0-36"}
SVG_SPECIAL = {
    "Piętro": {"room-1-05", "room-1-19", "room-1-12", "room-1-17", "room-1-14", "room-1-13",
               "room-1-01", "room-1-02", "room-1-04", "room-1-39", "room-1-40"} | SVG_REMOVED,
    "Parter": {"room-0-15", "room-0-48", "room-0-49", "room-0-50", "room-0-53",
               "room-0-03", "room-0-42", "room-0-56", "room-0-01", "room-0-02", "room-0-17"} | SVG_REMOVED,
}


def svg_polygon_ids(floor: str) -> List[str]:
    """Wczytuje ID wielokątów z plików planu (jedyne źródło geometrii)."""
    name = "floor1_plan.dart" if floor == "Piętro" else "floor0_plan.dart"
    path = os.path.join(PROJECT_ROOT, "lib", "widgets", name)
    try:
        with open(path, encoding="utf-8") as f:
            return re.findall(r"'(room-[^']+)':\s*'M", f.read())
    except Exception:
        return []


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = get_db_direct()
    cursor = conn.cursor()

    # 1. System Settings
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS system_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    """)
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('default_alert_limit_seconds', '900')")
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('max_alert_limit_seconds', '7200')")

    # 2. Check for migration from legacy rooms table
    cursor.execute("PRAGMA table_info(rooms)")
    cols = {row["name"]: row["type"] for row in cursor.fetchall()}
    if "isAvailable" in cols:
        print("[DB] Migrating legacy rooms table to contract v0.1 schema...")
        cursor.execute("SELECT * FROM rooms")
        old_rooms = cursor.fetchall()
        cursor.execute("DROP TABLE rooms")
        cursor.execute("""
            CREATE TABLE rooms (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                location TEXT,
                floor TEXT NOT NULL,
                operator_id TEXT,
                default_alert_limit_seconds INTEGER,
                status TEXT NOT NULL DEFAULT 'free' CHECK(status IN ('free', 'occupied')),
                device_id TEXT,
                category TEXT DEFAULT 'Laboratorium',
                description TEXT DEFAULT '',
                capacity INTEGER DEFAULT 30,
                customNote TEXT DEFAULT '',
                posX REAL,
                posY REAL,
                sortOrder INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        now = utc_now()
        for idx, r in enumerate(old_rooms):
            r_id = r["number"]
            st = "free" if r["isAvailable"] == 1 else "occupied"
            cursor.execute("""
                INSERT INTO rooms (id, name, location, floor, default_alert_limit_seconds, status, category, description, capacity, customNote, posX, posY, sortOrder, created_at, updated_at)
                VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                r_id, r["name"], f"Poziom {r['floor']}", r["floor"],
                st, r["category"], r["description"], r["capacity"],
                r["customNote"] or "", r["posX"], r["posY"], r["sortOrder"] or idx,
                r["updatedAt"] or now, r["updatedAt"] or now
            ))
        conn.commit()
        print("[DB] Rooms migrated successfully.")

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS rooms (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            location TEXT,
            floor TEXT NOT NULL,
            operator_id TEXT,
            default_alert_limit_seconds INTEGER,
            status TEXT NOT NULL DEFAULT 'free' CHECK(status IN ('free', 'occupied')),
            device_id TEXT,
            category TEXT DEFAULT 'Laboratorium',
            description TEXT DEFAULT '',
            capacity INTEGER DEFAULT 30,
            customNote TEXT DEFAULT '',
            posX REAL,
            posY REAL,
            sortOrder INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)

    # 3. Users
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('admin', 'operator')),
            room_id TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE SET NULL
        )
    """)

    # 4. Devices (ESP8266)
    cursor.execute("PRAGMA table_info(devices)")
    dev_cols = {row["name"] for row in cursor.fetchall()}
    if dev_cols and "id" not in dev_cols:
        print("[DB] Migrating legacy devices table to contract schema...")
        cursor.execute("DROP TABLE devices")
        conn.commit()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            room_id TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            last_seen_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE SET NULL
        )
    """)
    cursor.execute("PRAGMA table_info(devices)")
    dev_cols = {row["name"] for row in cursor.fetchall()}
    if "firmware_version" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN firmware_version TEXT DEFAULT '1.0.0'")
    if "chip_type" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN chip_type TEXT DEFAULT 'esp32'")
    dev_cols = {row["name"] for row in cursor.execute("PRAGMA table_info(devices)").fetchall()}
    if "device_type" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN device_type TEXT NOT NULL DEFAULT 'controller'")
    if "pair_code_hash" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN pair_code_hash TEXT")
    if "pair_code_hint" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN pair_code_hint TEXT")
    if "client_id" not in dev_cols:
        cursor.execute("ALTER TABLE devices ADD COLUMN client_id TEXT")
    cursor.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_pair_code_hash "
        "ON devices(pair_code_hash) WHERE pair_code_hash IS NOT NULL"
    )
    cursor.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_client_id "
        "ON devices(client_id) WHERE client_id IS NOT NULL"
    )
    for row in cursor.execute("SELECT id, pair_code_hash FROM devices").fetchall():
        if not row["pair_code_hash"]:
            code = new_pair_code(cursor)
            cursor.execute(
                "UPDATE devices SET pair_code_hash = ?, pair_code_hint = ? WHERE id = ?",
                (hash_token(code), code, row["id"])
            )

    # 5. Occupancy Sessions
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS occupancy_sessions (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            alert_limit_seconds INTEGER NOT NULL,
            alert_due_at TEXT NOT NULL,
            alert_triggered_at TEXT,
            started_by TEXT NOT NULL,
            ended_by TEXT,
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
        )
    """)
    # Enforce only one active session per room:
    cursor.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_active_session_per_room
        ON occupancy_sessions(room_id) WHERE ended_at IS NULL
    """)
    # Migracja: kto zajmuje salę (nick / nazwa wyświetlana)
    try:
        cursor.execute("ALTER TABLE occupancy_sessions ADD COLUMN occupant_name TEXT")
    except sqlite3.OperationalError:
        pass  # kolumna już istnieje
    # Migracja: rozmiar (skala) i obrót sali na planie
    for column in ("layout_scale REAL", "layout_angle REAL", "svg_id TEXT", "custom_path TEXT", "is_break INTEGER NOT NULL DEFAULT 0",
                   "lock_status INTEGER NOT NULL DEFAULT 0", "lock_info INTEGER NOT NULL DEFAULT 0",
                   "lock_layout INTEGER NOT NULL DEFAULT 0"):
        try:
            cursor.execute(f"ALTER TABLE rooms ADD COLUMN {column}")
        except sqlite3.OperationalError:
            pass  # kolumna już istnieje

    # 6. Alerts
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS alerts (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            triggered_at TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'occupancy_limit_exceeded',
            FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
            FOREIGN KEY (session_id) REFERENCES occupancy_sessions(id) ON DELETE CASCADE,
            UNIQUE(session_id, type)
        )
    """)

    # 7. Audit Logs
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS audit_logs (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            actor_type TEXT NOT NULL,
            actor_id TEXT NOT NULL,
            action TEXT NOT NULL,
            resource_type TEXT NOT NULL,
            resource_id TEXT NOT NULL,
            details TEXT
        )
    """)

    # 8. User Auth Tokens
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS auth_tokens (
            token TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """)

    conn.commit()

    # Seed Initial Rooms if empty
    cursor.execute("SELECT COUNT(*) FROM rooms")
    if cursor.fetchone()[0] == 0:
        now = utc_now()
        for idx, r in enumerate(INITIAL_ROOMS):
            r_id = r["number"]
            cursor.execute("""
                INSERT INTO rooms (id, name, location, floor, default_alert_limit_seconds, status, category, description, capacity, posX, posY, sortOrder, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 'free', ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                r_id, r["name"], f"Poziom {r['floor']}", r["floor"],
                None, r["category"], r["description"], r["capacity"],
                None, None, idx, now, now  # pozycje domyślne z projektu planu w aplikacji
            ))
        conn.commit()
        print(f"[DB] Seeded {len(INITIAL_ROOMS)} initial rooms.")

    # Migracja: dawne startowe współrzędne z INITIAL_ROOMS nie pasowały do planu
    # budynku (np. sala 9 na górze, HOL na wejściu). Sale, których nikt nie
    # przesunął ręcznie, wracają na swoje domyślne miejsca (posX/posY = NULL).
    for r in INITIAL_ROOMS:
        if r.get("posX") is not None:
            cursor.execute(
                "UPDATE rooms SET posX = NULL, posY = NULL WHERE id = ? AND posX = ? AND posY = ?",
                (r["number"], r["posX"], r["posY"]),
            )
    conn.commit()

    # Migracja: dawna jedna AULA -> trzy odrębne sale (numery z rozkładów WMT).
    if cursor.execute("SELECT 1 FROM rooms WHERE id = 'AULA'").fetchone():
        old = cursor.execute("SELECT * FROM rooms WHERE id = 'AULA'").fetchone()
        now = utc_now()
        conn.execute("PRAGMA foreign_keys = OFF")
        cursor.execute("UPDATE rooms SET id = 'Aula 111', name = 'Aula 111' WHERE id = 'AULA'")
        for table in ("users", "devices", "occupancy_sessions", "alerts"):
            cursor.execute(f"UPDATE {table} SET room_id = 'Aula 111' WHERE room_id = 'AULA'")
        conn.commit()
        conn.execute("PRAGMA foreign_keys = ON")
        for num, name, svg in [("Aula 101_102", "Aula 101_102", "room-1-20"),
                               ("Aula 103_104", "Aula 103_104", "room-1-24")]:
            if not cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (num,)).fetchone():
                cursor.execute("""
                    INSERT INTO rooms (id, name, location, floor, status, category, description,
                                       capacity, svg_id, sortOrder, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'free', 'Wykładowa', '', 0, ?, 99, ?, ?)
                """, (num, name, f"Poziom {old['floor']}", old["floor"], svg, now, now))
        conn.commit()
        print("[DB] Podzielono AULĘ na Aula 111 / Aula 101_102 / Aula 103_104.")

    # Migracja: nazwy sal Aula z wielkiej litery.
    renamed_any = False
    for old_id, new_id in (("aula 111", "Aula 111"),
                           ("aula 101_102", "Aula 101_102"),
                           ("aula 103_104", "Aula 103_104")):
        if (cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (old_id,)).fetchone()
                and not cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (new_id,)).fetchone()):
            conn.execute("PRAGMA foreign_keys = OFF")
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
            for table in ("users", "devices", "occupancy_sessions", "alerts"):
                cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
            conn.commit()
            conn.execute("PRAGMA foreign_keys = ON")
            renamed_any = True
    if renamed_any:
        print("[DB] Zaktualizowano nazwy sal Aula (wielka litera).")

    # Login operatora Auli bez spacji (szybkie profile testowe).
    cursor.execute("UPDATE users SET username = 'operator_aula111' WHERE username = 'operator_aula 111'")
    cursor.execute("UPDATE users SET username = 'operator_aula111' WHERE username = 'operator_aula'")
    cursor.execute("UPDATE users SET username = 'operator_garaz' WHERE username = 'operator_garaż'")
    conn.commit()

    # Aula 101_102 i Aula 103_104 zamieniły się poligonami na rzucie.
    cursor.execute("UPDATE rooms SET svg_id = 'room-1-20' WHERE id = 'Aula 101_102'")
    cursor.execute("UPDATE rooms SET svg_id = 'room-1-24' WHERE id = 'Aula 103_104'")
    conn.commit()

    # Pokoje włączone do łazienek oraz pokoje między aulami przestają istnieć.
    for rid in sorted(SVG_REMOVED):
        try:
            cursor.execute("DELETE FROM rooms WHERE id = ?", (rid,))
        except sqlite3.IntegrityError:
            pass
    conn.commit()

    # Usuń stare placeholdery o ID równym przypisanemu poligonowi — powodowały nakładanie się etykiet.
    assigned_pids = {pid for mapping in SVG_ASSIGNED.values() for pid in mapping.values()}
    for pid in sorted(assigned_pids):
        try:
            cursor.execute("DELETE FROM rooms WHERE id = ?", (pid,))
        except sqlite3.IntegrityError:
            pass
    conn.commit()

    # Sala 104 nie istnieje (jest częścią Auli 103_104); 118 i 120 zostały połączone.
    if cursor.execute("SELECT 1 FROM rooms WHERE id = '104'").fetchone():
        for table in ("users", "devices", "occupancy_sessions", "alerts"):
            cursor.execute(f"UPDATE {table} SET room_id = 'Aula 103_104' WHERE room_id = '104'")
        cursor.execute("DELETE FROM rooms WHERE id = '104'")
    for old in ("118", "120"):
        try:
            cursor.execute("DELETE FROM rooms WHERE id = ?", (old,))
        except sqlite3.IntegrityError:
            pass
    conn.commit()

    # Renumeracja parteru: stare sale przechodzą na nowe numery wraz z historią,
    # a zwolnione numery (9, 12) dostają nowe poligony poniżej.
    for old_id, new_id in (("9", "5"), ("14", "7"), ("12", "7")):
        if not cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (old_id,)).fetchone():
            continue
        conn.execute("PRAGMA foreign_keys = OFF")
        for table in ("users", "devices", "occupancy_sessions", "alerts"):
            cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
        if cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (new_id,)).fetchone():
            cursor.execute("DELETE FROM rooms WHERE id = ?", (old_id,))
        else:
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
        conn.commit()
        conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Przesunięcie numerów parteru o jeden w dół — od końca, żeby nie nadpisać
    # numerów, które dopiero zostaną zwolnione.
    for old_id, new_id in (("2", "1"), ("3", "2"), ("4", "3")):
        if cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (old_id,)).fetchone() and not cursor.execute(
                "SELECT 1 FROM rooms WHERE id = ?", (new_id,)).fetchone():
            conn.execute("PRAGMA foreign_keys = OFF")
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
            for table in ("users", "devices", "occupancy_sessions", "alerts"):
                cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
            conn.commit()
            conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Przesunięcie numerów od Kafeterii o jeden w dół (po podziale dawnej sali 17).
    for old_id, new_id in (("9", "8"), ("10", "9"), ("11", "10"), ("12", "11"),
                           ("13_14", "12_13"), ("15_16", "14_15"), ("17", "16")):
        if cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (old_id,)).fetchone() and not cursor.execute(
                "SELECT 1 FROM rooms WHERE id = ?", (new_id,)).fetchone():
            conn.execute("PRAGMA foreign_keys = OFF")
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
            for table in ("users", "devices", "occupancy_sessions", "alerts"):
                cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
            conn.commit()
            conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Piętro: ciąg 112, 113, 114 wzdłuż skosu (przesunięcie numerów razem z powiązaniami).
    r112 = cursor.execute("SELECT svg_id FROM rooms WHERE id = '112'").fetchone()
    r114 = cursor.execute("SELECT svg_id FROM rooms WHERE id = '114'").fetchone()
    if r112 and r112[0] == "room-1-42" and r114 and r114[0] == "room-1-39":
        conn.execute("PRAGMA foreign_keys = OFF")
        for old_id, new_id in (("114", "__renum_tmp"), ("113", "114"),
                               ("112", "113"), ("__renum_tmp", "112")):
            for table in ("users", "devices", "occupancy_sessions", "alerts"):
                cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
        conn.commit()
        conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Powrót do numerów z rzutu: 12, 13_14, 15_16 (salę 17 zostawiamy podzieloną).
    for old_id, new_id in (("12_13", "12"), ("14_15", "13_14"), ("16", "15_16")):
        if cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (old_id,)).fetchone() and not cursor.execute(
                "SELECT 1 FROM rooms WHERE id = ?", (new_id,)).fetchone():
            conn.execute("PRAGMA foreign_keys = OFF")
            cursor.execute("UPDATE rooms SET id = ?, name = ? WHERE id = ?", (new_id, new_id, old_id))
            for table in ("users", "devices", "occupancy_sessions", "alerts"):
                cursor.execute(f"UPDATE {table} SET room_id = ? WHERE room_id = ?", (new_id, old_id))
            conn.commit()
            conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Sala 5 (wąski pasek 0-09) znika; jej historia przechodzi do sali 4,
    # a nowa sala 5 powstaje z górnej połówki dawnej sali 4 (0-10).
    r5 = cursor.execute("SELECT svg_id FROM rooms WHERE id = '5'").fetchone()
    if r5 and r5[0] == "room-0-09":
        conn.execute("PRAGMA foreign_keys = OFF")
        for table in ("users", "devices", "occupancy_sessions", "alerts"):
            cursor.execute("UPDATE %s SET room_id = '4' WHERE room_id = '5'" % table)
        cursor.execute("DELETE FROM rooms WHERE id = '5'")
        conn.commit()
        conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    # Sale z rzutu SVG — nowe numery i przemapowania.
    for floor, mapping in SVG_ASSIGNED.items():
        for num, pid in mapping.items():
            if num.startswith("Aula "):
                continue
            if cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (num,)).fetchone():
                cursor.execute("UPDATE rooms SET svg_id = ? WHERE id = ?", (pid, num))
                continue
            now = utc_now()
            cursor.execute("""
                INSERT INTO rooms (id, name, location, floor, status, category, description,
                                   capacity, svg_id, sortOrder, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'free', 'Laboratorium', '', 0, ?, 99, ?, ?)
            """, (num, num, f"Poziom {floor}", floor, pid, now, now))
    conn.commit()

    # Seed Default Administrator if no users
    cursor.execute("SELECT COUNT(*) FROM users")
    if cursor.fetchone()[0] == 0:
        now = utc_now()
        admin_pass = hash_password("admin123")
        cursor.execute("""
            INSERT INTO users (id, username, password_hash, display_name, role, room_id, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
        """, (str(uuid.uuid4()), "admin", admin_pass, "Główny Administrator", "admin", None, now, now))

        # Seed Sample Operators for testing
        op_pass = hash_password("operator123")
        for room_no in ["Aula 103_104", "Aula 111", "Garaż"]:
            login_name = "operator_104" if room_no == "Aula 103_104" else operator_login(room_no)
            cursor.execute("""
                INSERT INTO users (id, username, password_hash, display_name, role, room_id, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
            """, (str(uuid.uuid4()), login_name, op_pass, f"Operator Sali {room_no}", "operator", room_no, now, now))
        conn.commit()
        print("[DB] Seeded default administrator (admin / admin123) and sample operators.")

    # Seed Default Hardware Devices if not present
    cursor.execute("SELECT COUNT(*) FROM devices WHERE token_hash = ?", (hash_token("dev_token_sala104"),))
    if cursor.fetchone()[0] == 0:
        now = utc_now()
        default_devices = [
            ("dev_token_sala104", "CYD_ESP32_Aula_103_104", "Aula 103_104"),
            ("dev_token_sala112", "ESP_Sala_112", "112"),
            ("dev_token_sala_aula", "ESP_Sala_AULA", "Aula 111"),
            ("dev_token_sala_garaz", "ESP_Sala_Garaz", "Garaż"),
        ]
        for token, name, r_id in default_devices:
            dev_id = str(uuid.uuid4())
            token_h = hash_token(token)
            pair_code = new_pair_code(cursor)
            cursor.execute("""
                INSERT INTO devices (id, name, token_hash, room_id, is_active, last_seen_at, created_at, updated_at,
                                     device_type, pair_code_hash, pair_code_hint)
                VALUES (?, ?, ?, ?, 1, ?, ?, ?, 'controller', ?, ?)
            """, (dev_id, name, token_h, r_id, now, now, now, hash_token(pair_code), pair_code))
            cursor.execute("UPDATE rooms SET device_id = ? WHERE id = ?", (dev_id, r_id))
        conn.commit()
        print("[DB] Seeded default hardware controller tokens.")

    # Puste pomieszczenia z rzutów SVG dostają edytowalne sale bez informacji.
    for floor in ("Piętro", "Parter"):
        used = set(SVG_ASSIGNED[floor].values()) | SVG_SPECIAL[floor]
        used.update(r["svg_id"] for r in cursor.execute(
            "SELECT svg_id FROM rooms WHERE svg_id IS NOT NULL") if r["svg_id"])
        created = 0
        for pid in svg_polygon_ids(floor):
            if pid in used or cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (pid,)).fetchone():
                continue
            now = utc_now()
            cursor.execute("""
                INSERT INTO rooms (id, name, location, floor, status, category, description,
                                   capacity, svg_id, sortOrder, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'free', 'Inne', '', 0, ?, 99, ?, ?)
            """, (pid, pid, f"Poziom {floor}", floor, pid, now, now))
            created += 1
        conn.commit()
        if created:
            print(f"[DB] Dodano {created} pustych pomieszczeń z rzutu {floor}.")

    # Przypisanie istniejących sal do poligonów rzutu (bez zmiany numerów).
    for floor, mapping in SVG_ASSIGNED.items():
        for number, pid in mapping.items():
            cursor.execute("UPDATE rooms SET svg_id = ? WHERE id = ? AND svg_id IS NULL", (pid, number))
    conn.commit()

    conn.close()

# In-Memory WebSocket Manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, event_type: str, data: Any):
        payload = {
            "type": event_type,
            "occurred_at": utc_now(),
            "data": data
        }
        dead_connections = []
        for connection in self.active_connections:
            try:
                await connection.send_text(json.dumps(payload))
            except Exception:
                dead_connections.append(connection)
        for dc in dead_connections:
            self.disconnect(dc)

ws_manager = ConnectionManager()

# FastAPI App
app = FastAPI(
    title="DostępnośćSal API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/api/v1/openapi.json"
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Standardized Error Response Exception
class DomainException(HTTPException):
    def __init__(self, status_code: int, code: str, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(status_code=status_code, detail={"code": code, "message": message, "details": details or {}})

@app.exception_handler(DomainException)
async def domain_exception_handler(request: Request, exc: DomainException):
    req_id = getattr(request.state, "request_id", str(uuid.uuid4()))
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.detail.get("code", "ERROR"),
                "message": exc.detail.get("message", ""),
                "details": exc.detail.get("details", {}),
                "request_id": req_id
            }
        }
    )

@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request.state.request_id = str(uuid.uuid4())
    response = await call_next(request)
    return response

# Dependency: Authentication
def get_current_user_optional(authorization: Optional[str] = Header(None), db: sqlite3.Connection = Depends(get_db)):
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization.split(" ")[1]
    cursor = db.cursor()
    cursor.execute("""
        SELECT u.* FROM auth_tokens t
        JOIN users u ON t.user_id = u.id
        WHERE t.token = ? AND t.expires_at > ? AND u.is_active = 1
    """, (token, utc_now()))
    user = cursor.fetchone()
    return user

def require_current_user(user: Optional[sqlite3.Row] = Depends(get_current_user_optional)):
    if not user:
        raise DomainException(401, "UNAUTHENTICATED", "Wymagane uwierzytelnienie.")
    return user

def require_admin(user: sqlite3.Row = Depends(require_current_user)):
    if user["role"] != "admin":
        raise DomainException(403, "FORBIDDEN", "Brak uprawnień administratora.")
    return user

def get_current_device_optional(
    authorization: Optional[str] = Header(None),
    x_device_token: Optional[str] = Header(None),
    db: sqlite3.Connection = Depends(get_db)
):
    token = None
    if x_device_token:
        token = x_device_token
    elif authorization and authorization.startswith("Bearer "):
        token = authorization.split(" ")[1]
    
    if not token:
        return None
    
    token_h = hash_token(token)
    cursor = db.cursor()
    cursor.execute("SELECT * FROM devices WHERE token_hash = ? AND is_active = 1", (token_h,))
    return cursor.fetchone()

def require_device(device: Optional[sqlite3.Row] = Depends(get_current_device_optional)):
    if not device:
        raise DomainException(401, "UNAUTHENTICATED", "Niepoprawny lub nieaktywny token urządzenia ESP.")
    return device

def ensure_room_unlocked(db: sqlite3.Connection, room_id: str, field: str, user=None):
    """Admin zawsze może; pozostali są blokowani przez flagi sali."""
    if user and user["role"] == "admin":
        return
    row = db.execute(f"SELECT {field} FROM rooms WHERE id = ?", (room_id,)).fetchone()
    if row and bool(row[field]):
        raise DomainException(403, "ROOM_LOCKED", "Ta czynność jest zablokowana dla tej sali.")

# Audit Logging Helper
def log_audit(db: sqlite3.Connection, actor_type: str, actor_id: str, action: str, res_type: str, res_id: str, details: Optional[Dict] = None):
    cursor = db.cursor()
    cursor.execute("""
        INSERT INTO audit_logs (id, created_at, actor_type, actor_id, action, resource_type, resource_id, details)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        str(uuid.uuid4()), utc_now(), actor_type, actor_id, action, res_type, res_id,
        json.dumps(details or {}, ensure_ascii=False)
    ))
    db.commit()

# Active Session Formatter
def format_active_session(session_row: Optional[sqlite3.Row]) -> Optional[Dict[str, Any]]:
    if not session_row:
        return None
    
    started_at = session_row["started_at"]
    alert_due_at = session_row["alert_due_at"]
    now_dt = datetime.now(timezone.utc)
    started_dt = parse_iso(started_at)
    due_dt = parse_iso(alert_due_at)
    
    duration_sec = max(0, int((now_dt - started_dt).total_seconds()))
    is_alert_due = now_dt >= due_dt

    return {
        "id": session_row["id"],
        "room_id": session_row["room_id"],
        "started_at": started_at,
        "duration_seconds": duration_sec,
        "alert_limit_seconds": session_row["alert_limit_seconds"],
        "alert_due_at": alert_due_at,
        "alert_triggered_at": session_row["alert_triggered_at"],
        "alert_due": is_alert_due,
        "occupant_name": _session_occupant(session_row),
    }


def build_room_representation(r: sqlite3.Row, db: sqlite3.Connection) -> Dict[str, Any]:
    """Pełne dane sali w tym samym formacie co /api/v1/public/rooms.
    (Wcześniej ta funkcja była wywoływana, ale nie istniała — zapis położenia
    sali kończył się błędem 500.)"""
    keys = r.keys()
    cursor = db.cursor()
    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (r["id"],))
    session = cursor.fetchone()
    return {
        "id": r["id"],
        "number": r["id"],
        "name": r["name"],
        "location": (r["location"] if "location" in keys else None) or f"Poziom {r['floor']}",
        "floor": r["floor"],
        "status": r["status"],
        "category": r["category"],
        "description": r["description"],
        "capacity": r["capacity"],
        "customNote": r["customNote"] if "customNote" in keys else None,
        "posX": r["posX"],
        "posY": r["posY"],
        "layout_scale": r["layout_scale"] if "layout_scale" in keys else None,
        "layout_angle": r["layout_angle"] if "layout_angle" in keys else None,
        "custom_path": r["custom_path"] if "custom_path" in keys else None,
        "svg_id": r["svg_id"] if "svg_id" in keys else None,
        "is_break": bool(r["is_break"]) if "is_break" in keys else False,
        "lock_status": bool(r["lock_status"]) if "lock_status" in keys else False,
        "lock_info": bool(r["lock_info"]) if "lock_info" in keys else False,
        "lock_layout": bool(r["lock_layout"]) if "lock_layout" in keys else False,
        "sortOrder": r["sortOrder"] if "sortOrder" in keys else 0,
        "default_alert_limit_seconds": r["default_alert_limit_seconds"],
        "active_session": format_active_session(session),
        "updated_at": r["updated_at"],
    }


async def broadcast_ws_event(event_type: str, data: Any):
    """Wysyła zdarzenie do wszystkich klientów WebSocket (też wcześniej nie istniała)."""
    await ws_manager.broadcast(event_type, data)


def _session_occupant(session_row) -> Optional[str]:
    """Nick osoby zajmującej salę (wiersz z bazy albo słownik z zapytania JOIN)."""
    try:
        if isinstance(session_row, dict):
            return session_row.get("occupant_name")
        if "occupant_name" in session_row.keys():
            return session_row["occupant_name"]
    except Exception:
        pass
    return None

# Background Alert Checker Loop
async def alert_monitor_loop():
    while True:
        try:
            await asyncio.sleep(2)
            conn = get_db_direct()
            cursor = conn.cursor()
            now_iso = utc_now()
            now_dt = parse_iso(now_iso)

            cursor.execute("""
                SELECT s.*, r.name as room_name FROM occupancy_sessions s
                JOIN rooms r ON s.room_id = r.id
                WHERE s.ended_at IS NULL AND s.alert_triggered_at IS NULL
            """)
            active_sessions = cursor.fetchall()

            for sess in active_sessions:
                due_dt = parse_iso(sess["alert_due_at"])
                if now_dt >= due_dt:
                    alert_id = str(uuid.uuid4())
                    # Insert alert with UNIQUE constraint protection
                    try:
                        cursor.execute("""
                            INSERT INTO alerts (id, room_id, session_id, triggered_at, type)
                            VALUES (?, ?, ?, ?, 'occupancy_limit_exceeded')
                        """, (alert_id, sess["room_id"], sess["id"], now_iso))
                        
                        cursor.execute("""
                            UPDATE occupancy_sessions SET alert_triggered_at = ? WHERE id = ?
                        """, (now_iso, sess["id"]))
                        conn.commit()

                        # Audit log
                        log_audit(conn, "system", "alert_engine", "alert_triggered", "alert", alert_id, {
                            "room_id": sess["room_id"],
                            "session_id": sess["id"],
                            "alert_limit_seconds": sess["alert_limit_seconds"]
                        })

                        # Broadcast Alert Created
                        await ws_manager.broadcast("alert.created", {
                            "id": alert_id,
                            "room_id": sess["room_id"],
                            "session_id": sess["id"],
                            "triggered_at": now_iso,
                            "type": "occupancy_limit_exceeded"
                        })

                        # Broadcast Room Updated (status is still occupied, but alert_due is now true)
                        cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (sess["id"],))
                        upd_sess = cursor.fetchone()
                        await ws_manager.broadcast("room.updated", {
                            "room_id": sess["room_id"],
                            "status": "occupied",
                            "active_session": format_active_session(upd_sess)
                        })
                    except sqlite3.IntegrityError:
                        pass # Alert already registered for this session
            conn.close()
        except Exception as e:
            sys.stderr.write(f"[Alert Monitor] Error: {e}\n")

async def clock_tick_loop():
    """High-frequency WS ticks keep web clocks alive in throttled background tabs."""
    while True:
        await asyncio.sleep(1)
        if ws_manager.active_connections:
            await ws_manager.broadcast("clock.tick", {"time": utc_now()})

# Start background tasks
@app.on_event("startup")
async def startup_event():
    init_db()
    asyncio.create_task(alert_monitor_loop())
    asyncio.create_task(clock_tick_loop())

# ==============================================================================
# 6.1 Publiczny podgląd sal i rejestracja wyświetlaczy
# ==============================================================================
class DeviceClaimRequest(BaseModel):
    client_id: str = Field(..., min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    name: Optional[str] = Field(None, max_length=80)
    device_type: Optional[str] = "kiosk"

@app.post("/api/v1/public/devices/claim", tags=["Public"])
def claim_device(req: DeviceClaimRequest, db: sqlite3.Connection = Depends(get_db)):
    """Rejestracja wyświetlacza/TV bez konta — kod identyfikacyjny nadaje serwer."""
    device_type = (req.device_type or "kiosk").lower()
    if device_type not in DEVICE_TYPES:
        raise DomainException(400, "INVALID_DEVICE_TYPE", "Nieprawidłowy typ urządzenia.")
    dev = db.execute("SELECT * FROM devices WHERE client_id = ?", (req.client_id,)).fetchone()
    if dev:
        return {
            "device_id": dev["id"],
            "name": dev["name"],
            "device_type": dev["device_type"],
            "pair_code": dev["pair_code_hint"],
        }
    cursor = db.cursor()
    pair_code = new_pair_code(cursor)
    device_id = str(uuid.uuid4())
    name = (req.name or "").strip()[:80] or "TV / Kiosk"
    now = utc_now()
    cursor.execute("""
        INSERT INTO devices (id, name, token_hash, room_id, is_active, last_seen_at, created_at, updated_at,
                             device_type, pair_code_hash, pair_code_hint, client_id)
        VALUES (?, ?, ?, NULL, 1, NULL, ?, ?, ?, ?, ?, ?)
    """, (
        device_id, name, hash_token(secrets.token_hex(20)), now, now,
        device_type, hash_token(pair_code), pair_code, req.client_id,
    ))
    db.commit()
    log_audit(db, "device", req.client_id, "device_claimed", "device", device_id, {"device_type": device_type})
    return {"device_id": device_id, "name": name, "device_type": device_type, "pair_code": pair_code}

@app.get("/api/v1/public/devices/{client_id}/code", tags=["Public"])
def get_device_code(client_id: str, db: sqlite3.Connection = Depends(get_db)):
    """Aktualny kod wyświetlacza — używany do odświeżenia po rotacji z panelu admina."""
    dev = db.execute("SELECT pair_code_hint FROM devices WHERE client_id = ?", (client_id,)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    return {"pair_code": dev["pair_code_hint"]}

@app.get("/api/v1/public/rooms", tags=["Public"])
def get_public_rooms(floor: Optional[str] = None, db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    query = """
        SELECT r.*, 
               s.id as s_id, s.started_at as s_started_at, s.alert_limit_seconds as s_limit, 
               s.alert_due_at as s_due_at, s.alert_triggered_at as s_triggered_at, s.occupant_name as s_occupant
        FROM rooms r
        LEFT JOIN occupancy_sessions s ON r.id = s.room_id AND s.ended_at IS NULL
    """
    params = []
    if floor and floor.lower() != "wszystkie":
        if floor.lower() == "parter":
            # Including Garage on Parter as required by building layout
            query += " WHERE (LOWER(r.floor) = 'parter' OR LOWER(r.floor) LIKE '%gara%')"
        else:
            query += " WHERE LOWER(r.floor) = ?"
            params.append(floor.lower())
    query += " ORDER BY r.sortOrder ASC, r.id ASC"
    
    cursor.execute(query, params)
    rows = cursor.fetchall()
    
    result = []
    for r in rows:
        session_data = None
        if r["s_id"]:
            session_data = format_active_session({
                "id": r["s_id"],
                "room_id": r["id"],
                "started_at": r["s_started_at"],
                "alert_limit_seconds": r["s_limit"],
                "alert_due_at": r["s_due_at"],
                "alert_triggered_at": r["s_triggered_at"],
                "occupant_name": r["s_occupant"]
            })
        
        result.append({
            "id": r["id"],
            "name": r["name"],
            "location": r["location"] or f"Poziom {r['floor']}",
            "floor": r["floor"],
            "status": r["status"],
            "category": r["category"],
            "description": r["description"],
            "capacity": r["capacity"],
            "customNote": r["customNote"],
            "posX": r["posX"],
            "posY": r["posY"],
            "layout_scale": r["layout_scale"],
            "layout_angle": r["layout_angle"],
            "custom_path": r["custom_path"],
            "svg_id": r["svg_id"],
            "is_break": bool(r["is_break"]),
            "lock_status": bool(r["lock_status"]),
            "lock_info": bool(r["lock_info"]),
            "lock_layout": bool(r["lock_layout"]),
            "default_alert_limit_seconds": r["default_alert_limit_seconds"],
            "active_session": session_data,
            "updated_at": r["updated_at"]
        })
    return result

@app.get("/api/v1/public/rooms/{room_id}", tags=["Public"])
def get_public_room(room_id: str, db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("""
        SELECT r.*, 
               s.id as s_id, s.started_at as s_started_at, s.alert_limit_seconds as s_limit, 
               s.alert_due_at as s_due_at, s.alert_triggered_at as s_triggered_at, s.occupant_name as s_occupant
        FROM rooms r
        LEFT JOIN occupancy_sessions s ON r.id = s.room_id AND s.ended_at IS NULL
        WHERE r.id = ?
    """, (room_id,))
    r = cursor.fetchone()
    if not r:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    
    session_data = None
    if r["s_id"]:
        session_data = format_active_session({
            "id": r["s_id"],
            "room_id": r["id"],
            "started_at": r["s_started_at"],
            "alert_limit_seconds": r["s_limit"],
            "alert_due_at": r["s_due_at"],
            "alert_triggered_at": r["s_triggered_at"],
            "occupant_name": r["s_occupant"]
        })

    return {
        "id": r["id"],
        "name": r["name"],
        "location": r["location"],
        "floor": r["floor"],
        "status": r["status"],
        "category": r["category"],
        "description": r["description"],
        "capacity": r["capacity"],
        "customNote": r["customNote"],
        "posX": r["posX"],
        "posY": r["posY"],
        "layout_scale": r["layout_scale"],
        "layout_angle": r["layout_angle"],
        "custom_path": r["custom_path"],
        "svg_id": r["svg_id"],
        "is_break": bool(r["is_break"]),
        "lock_status": bool(r["lock_status"]),
        "lock_info": bool(r["lock_info"]),
        "lock_layout": bool(r["lock_layout"]),
        "default_alert_limit_seconds": r["default_alert_limit_seconds"],
        "active_session": session_data,
        "updated_at": r["updated_at"]
    }

# ==============================================================================
# 6.2 Uwierzytelnianie kont
# ==============================================================================
class LoginRequest(BaseModel):
    username: str
    password: str

@app.post("/api/v1/auth/login", tags=["Auth"])
def login(req: LoginRequest, db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM users WHERE username = ? AND is_active = 1", (req.username.strip(),))
    user = cursor.fetchone()
    
    if not user or not verify_password(req.password, user["password_hash"]):
        raise DomainException(401, "UNAUTHENTICATED", "Niepoprawny login lub hasło.")
    
    token = secrets.token_urlsafe(32)
    now_dt = datetime.now(timezone.utc)
    expires_dt = now_dt + timedelta(days=7)
    
    cursor.execute("""
        INSERT INTO auth_tokens (token, user_id, created_at, expires_at)
        VALUES (?, ?, ?, ?)
    """, (token, user["id"], utc_now(), expires_dt.strftime("%Y-%m-%dT%H:%M:%SZ")))
    db.commit()

    log_audit(db, "user", user["id"], "user_logged_in", "user", user["id"])

    return {
        "access_token": token,
        "token": token,
        "token_type": "Bearer",
        "user": {
            "id": user["id"],
            "username": user["username"],
            "display_name": user["display_name"],
            "role": user["role"],
            "room_id": user["room_id"]
        }
    }

@app.post("/api/v1/auth/logout", tags=["Auth"])
def logout(authorization: Optional[str] = Header(None), db: sqlite3.Connection = Depends(get_db)):
    if authorization and authorization.startswith("Bearer "):
        token = authorization.split(" ")[1]
        cursor = db.cursor()
        cursor.execute("DELETE FROM auth_tokens WHERE token = ?", (token,))
        db.commit()
    return {"status": "success", "message": "Wylogowano pomyślnie."}

@app.post("/api/v1/auth/refresh", tags=["Auth"])
def refresh_token(authorization: Optional[str] = Header(None), db: sqlite3.Connection = Depends(get_db)):
    if not authorization or not authorization.startswith("Bearer "):
        raise DomainException(401, "UNAUTHENTICATED", "Brak tokena do odświeżenia.")
    token = authorization.split(" ")[1]
    cursor = db.cursor()
    cursor.execute("""
        SELECT a.*, u.id as u_id, u.username, u.display_name, u.role, u.room_id
        FROM auth_tokens a
        JOIN users u ON a.user_id = u.id
        WHERE a.token = ? AND a.expires_at > ? AND u.is_active = 1
    """, (token, utc_now()))
    row = cursor.fetchone()
    if not row:
        raise DomainException(401, "UNAUTHENTICATED", "Token wygasł lub jest nieprawidłowy.")
    
    new_token = secrets.token_urlsafe(32)
    now_dt = datetime.now(timezone.utc)
    expires_dt = now_dt + timedelta(days=7)
    cursor.execute("DELETE FROM auth_tokens WHERE token = ?", (token,))
    cursor.execute("""
        INSERT INTO auth_tokens (token, user_id, created_at, expires_at)
        VALUES (?, ?, ?, ?)
    """, (new_token, row["u_id"], utc_now(), expires_dt.strftime("%Y-%m-%dT%H:%M:%SZ")))
    db.commit()
    return {
        "access_token": new_token,
        "token": new_token,
        "token_type": "Bearer",
        "user": {
            "id": row["u_id"],
            "username": row["username"],
            "display_name": row["display_name"],
            "role": row["role"],
            "room_id": row["room_id"]
        }
    }

@app.get("/api/v1/auth/me", tags=["Auth"])
def get_me(user: sqlite3.Row = Depends(require_current_user)):
    return {
        "id": user["id"],
        "username": user["username"],
        "display_name": user["display_name"],
        "role": user["role"],
        "room_id": user["room_id"],
        "is_active": bool(user["is_active"])
    }

# ==============================================================================
# 6.3 Sale i Status (Zalogowani / Operator / Admin)
# ==============================================================================
class StatusChangeRequest(BaseModel):
    status: str = Field(..., pattern="^(free|occupied)$")
    is_break: bool = False
    occupant_name: Optional[str] = Field(None, max_length=40)

@app.get("/api/v1/rooms", tags=["Rooms"])
def get_rooms_detailed(user: sqlite3.Row = Depends(require_current_user), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    query = """
        SELECT r.*, 
               s.id as s_id, s.started_at as s_started_at, s.alert_limit_seconds as s_limit, 
               s.alert_due_at as s_due_at, s.alert_triggered_at as s_triggered_at, s.occupant_name as s_occupant
        FROM rooms r
        LEFT JOIN occupancy_sessions s ON r.id = s.room_id AND s.ended_at IS NULL
    """
    params = []
    # Operator sees only assigned room
    if user["role"] == "operator":
        if not user["room_id"]:
            return []
        query += " WHERE r.id = ?"
        params.append(user["room_id"])
    query += " ORDER BY r.sortOrder ASC, r.id ASC"

    cursor.execute(query, params)
    rows = cursor.fetchall()

    result = []
    for r in rows:
        session_data = None
        if r["s_id"]:
            session_data = format_active_session({
                "id": r["s_id"],
                "room_id": r["id"],
                "started_at": r["s_started_at"],
                "alert_limit_seconds": r["s_limit"],
                "alert_due_at": r["s_due_at"],
                "alert_triggered_at": r["s_triggered_at"],
                "occupant_name": r["s_occupant"]
            })
        
        result.append({
            "id": r["id"],
            "name": r["name"],
            "location": r["location"],
            "floor": r["floor"],
            "operator_id": r["operator_id"],
            "device_id": r["device_id"] if user["role"] == "admin" else None,
            "default_alert_limit_seconds": r["default_alert_limit_seconds"],
            "status": r["status"],
            "category": r["category"],
            "description": r["description"],
            "capacity": r["capacity"],
            "customNote": r["customNote"],
            "posX": r["posX"],
            "posY": r["posY"],
            "layout_scale": r["layout_scale"],
            "layout_angle": r["layout_angle"],
            "custom_path": r["custom_path"],
            "svg_id": r["svg_id"],
            "is_break": bool(r["is_break"]),
            "lock_status": bool(r["lock_status"]),
            "lock_info": bool(r["lock_info"]),
            "lock_layout": bool(r["lock_layout"]),
            "active_session": session_data,
            "created_at": r["created_at"],
            "updated_at": r["updated_at"]
        })
    return result

@app.get("/api/v1/rooms/{room_id}", tags=["Rooms"])
def get_room_detailed(room_id: str, user: sqlite3.Row = Depends(require_current_user), db: sqlite3.Connection = Depends(get_db)):
    if user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Brak uprawnień do przeglądania tej sali.")
    
    cursor = db.cursor()
    cursor.execute("""
        SELECT r.*, 
               s.id as s_id, s.started_at as s_started_at, s.alert_limit_seconds as s_limit, 
               s.alert_due_at as s_due_at, s.alert_triggered_at as s_triggered_at, s.occupant_name as s_occupant
        FROM rooms r
        LEFT JOIN occupancy_sessions s ON r.id = s.room_id AND s.ended_at IS NULL
        WHERE r.id = ?
    """, (room_id,))
    r = cursor.fetchone()
    if not r:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie została znaleziona.")
    
    session_data = None
    if r["s_id"]:
        session_data = format_active_session({
            "id": r["s_id"],
            "room_id": r["id"],
            "started_at": r["s_started_at"],
            "alert_limit_seconds": r["s_limit"],
            "alert_due_at": r["s_due_at"],
            "alert_triggered_at": r["s_triggered_at"],
            "occupant_name": r["s_occupant"]
        })

    return {
        "id": r["id"],
        "name": r["name"],
        "location": r["location"],
        "floor": r["floor"],
        "operator_id": r["operator_id"],
        "device_id": r["device_id"] if user["role"] == "admin" else None,
        "default_alert_limit_seconds": r["default_alert_limit_seconds"],
        "status": r["status"],
        "category": r["category"],
        "description": r["description"],
        "capacity": r["capacity"],
        "customNote": r["customNote"],
        "posX": r["posX"],
        "posY": r["posY"],
        "layout_scale": r["layout_scale"],
        "layout_angle": r["layout_angle"],
        "custom_path": r["custom_path"],
        "svg_id": r["svg_id"],
        "is_break": bool(r["is_break"]),
        "lock_status": bool(r["lock_status"]),
        "lock_info": bool(r["lock_info"]),
        "lock_layout": bool(r["lock_layout"]),
        "default_alert_limit_seconds": r["default_alert_limit_seconds"],
        "active_session": session_data,
        "created_at": r["created_at"],
        "updated_at": r["updated_at"]
    }

class OccupantChangeRequest(BaseModel):
    occupant_name: Optional[str] = Field(None, max_length=40)

@app.patch("/api/v1/rooms/{room_id}/occupant", tags=["Rooms"])
async def change_room_occupant(
    room_id: str,
    req: OccupantChangeRequest,
    user: Optional[sqlite3.Row] = Depends(get_current_user_optional),
    db: sqlite3.Connection = Depends(get_db)
):
    """Zmienia nazwę osoby przy aktywnej sesji (np. gdy ktoś zmienił swoją nazwę)."""
    if not user:
        raise DomainException(403, "FORBIDDEN", "Gość może tylko oglądać dostępność sal.")
    if user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Operator może zarządzać wyłącznie swoją przypisaną salą.")
    ensure_room_unlocked(db, room_id, "lock_info", user)

    cursor = db.cursor()
    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (room_id,))
    session = cursor.fetchone()
    if not session:
        raise DomainException(409, "ROOM_NOT_OCCUPIED", "Sala nie jest zajęta.")

    occupant = " ".join((req.occupant_name or "").split())[:40] or None
    cursor.execute("UPDATE occupancy_sessions SET occupant_name = ? WHERE id = ?", (occupant, session["id"]))
    db.commit()

    cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (session["id"],))
    formatted_session = format_active_session(cursor.fetchone())
    await ws_manager.broadcast("room.updated", {
        "room_id": room_id,
        "status": "occupied",
        "active_session": formatted_session
    })
    return {"data": {"room_id": room_id, "active_session": formatted_session}}

@app.patch("/api/v1/rooms/{room_id}/status", tags=["Rooms"])
@app.post("/api/v1/rooms/{room_id}/status", tags=["Rooms"])
async def change_room_status(
    room_id: str,
    req: StatusChangeRequest,
    user: Optional[sqlite3.Row] = Depends(get_current_user_optional),
    db: sqlite3.Connection = Depends(get_db)
):
    if not user:
        raise DomainException(403, "FORBIDDEN", "Gość może tylko oglądać dostępność sal.")
    if user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Operator może zarządzać wyłącznie swoją przypisaną salą.")
    ensure_room_unlocked(db, room_id, "lock_status", user)

    cursor = db.cursor()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    room = cursor.fetchone()
    if not room:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")

    target_status = req.status
    current_status = room["status"]
    target_break = req.is_break
    current_break = bool(room["is_break"]) if "is_break" in room.keys() else False
    now_iso = utc_now()
    now_dt = parse_iso(now_iso)
    changed = False

    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (room_id,))
    active_session = cursor.fetchone()

    actor_type = "user" if user else "guest"
    actor_id = user["id"] if user else "guest:web"
    actor_str = f"user:{user['id']}" if user else "guest:web"

    starting_session = (
        target_status == "occupied"
        and not target_break
        and (current_status == "free" or (current_status == "occupied" and current_break))
    )

    if starting_session:
        # Determine effective alert limit
        effective_limit = room["default_alert_limit_seconds"]
        if not effective_limit:
            cursor.execute("SELECT value FROM system_settings WHERE key = 'default_alert_limit_seconds'")
            row = cursor.fetchone()
            effective_limit = int(row["value"]) if row else 900
        
        due_dt = now_dt + timedelta(seconds=effective_limit)
        due_iso = due_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        session_id = str(uuid.uuid4())

        # Kto zajmuje salę: podany nick, a dla zalogowanych ich nazwa wyświetlana
        occupant = " ".join((req.occupant_name or "").split())[:40]
        if not occupant and user:
            occupant = user["display_name"]
        occupant = occupant or None

        cursor.execute("""
            INSERT INTO occupancy_sessions (id, room_id, started_at, ended_at, alert_limit_seconds, alert_due_at, alert_triggered_at, started_by, ended_by, occupant_name)
            VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, NULL, ?)
        """, (session_id, room_id, now_iso, effective_limit, due_iso, actor_str, occupant))

        cursor.execute("UPDATE rooms SET status = 'occupied', is_break = 0, updated_at = ? WHERE id = ?", (now_iso, room_id))
        db.commit()
        changed = True

        cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (session_id,))
        active_session = cursor.fetchone()
        log_audit(db, actor_type, actor_id, "session_started", "room", room_id, {"session_id": session_id, "limit": effective_limit, "occupant": occupant})

    elif target_status == "occupied" and target_break and (current_status != "occupied" or not current_break):
        # Przerwa = sala niedostępna, ale bez sesji, więc bez timera i alertu.
        if active_session:
            cursor.execute("UPDATE occupancy_sessions SET ended_at = ?, ended_by = ? WHERE id = ?", (now_iso, actor_str, active_session["id"]))
        cursor.execute("UPDATE rooms SET status = 'occupied', is_break = 1, updated_at = ? WHERE id = ?", (now_iso, room_id))
        db.commit()
        changed = True
        active_session = None
        log_audit(db, actor_type, actor_id, "break_started", "room", room_id)

    elif target_status == "free" and (current_status == "occupied" or current_break):
        if active_session:
            cursor.execute("UPDATE occupancy_sessions SET ended_at = ?, ended_by = ? WHERE id = ?", (now_iso, actor_str, active_session["id"]))

        cursor.execute("UPDATE rooms SET status = 'free', is_break = 0, updated_at = ? WHERE id = ?", (now_iso, room_id))
        db.commit()
        changed = True
        log_audit(db, actor_type, actor_id, "session_ended", "room", room_id, {"session_id": active_session["id"] if active_session else None})
        active_session = None

    # Broadcast event if changed
    formatted_session = format_active_session(active_session)
    if changed:
        await ws_manager.broadcast("room.updated", {
            "room_id": room_id,
            "status": target_status,
            "is_break": target_break,
            "active_session": formatted_session
        })

    return {
        "data": {
            "room_id": room_id,
            "status": target_status,
            "is_break": target_break,
            "changed": changed,
            "active_session": formatted_session
        },
        "meta": {
            "server_time": now_iso
        }
    }

@app.get("/api/v1/rooms/{room_id}/sessions", tags=["Rooms"])
def get_room_sessions(room_id: str, user: sqlite3.Row = Depends(require_current_user), db: sqlite3.Connection = Depends(get_db)):
    if user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Brak uprawnień do przeglądania historii tej sali.")
    
    cursor = db.cursor()
    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? ORDER BY started_at DESC LIMIT 50", (room_id,))
    rows = cursor.fetchall()
    return [dict(r) for r in rows]

@app.get("/api/v1/rooms/{room_id}/alerts", tags=["Rooms"])
def get_room_alerts(room_id: str, user: sqlite3.Row = Depends(require_current_user), db: sqlite3.Connection = Depends(get_db)):
    if user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Brak uprawnień.")
    
    cursor = db.cursor()
    cursor.execute("SELECT * FROM alerts WHERE room_id = ? ORDER BY triggered_at DESC LIMIT 50", (room_id,))
    rows = cursor.fetchall()
    return [dict(r) for r in rows]

# ==============================================================================
# 6.4 Limity i Ustawienia
# ==============================================================================
class AlertLimitChangeRequest(BaseModel):
    alert_limit_seconds: Optional[int] = Field(None, ge=1)
    limit_seconds: Optional[int] = None

@app.patch("/api/v1/rooms/{room_id}/alert-limit", tags=["Limits"])
@app.post("/api/v1/rooms/{room_id}/alert-limit", tags=["Limits"])
async def update_room_default_limit(
    room_id: str,
    req: AlertLimitChangeRequest,
    user: Optional[sqlite3.Row] = Depends(get_current_user_optional),
    device: Optional[sqlite3.Row] = Depends(get_current_device_optional),
    db: sqlite3.Connection = Depends(get_db)
):
    if user and user["role"] == "operator" and user["room_id"] != room_id:
        raise DomainException(403, "FORBIDDEN", "Operator może zmieniać limit wyłącznie swojej sali.")
    ensure_room_unlocked(db, room_id, "lock_info", user)

    limit_val = req.alert_limit_seconds or req.limit_seconds
    if not limit_val or limit_val <= 0:
        raise DomainException(400, "VALIDATION_ERROR", "Niepoprawna wartość alert_limit_seconds.")

    cursor = db.cursor()
    cursor.execute("SELECT value FROM system_settings WHERE key = 'max_alert_limit_seconds'")
    max_limit = int(cursor.fetchone()["value"])

    if limit_val > max_limit:
        raise DomainException(400, "ALERT_LIMIT_EXCEEDS_MAXIMUM", f"Limit przekracza maksymalną wartość ({max_limit} s).", {"maximum_seconds": max_limit})

    now_iso = utc_now()
    cursor.execute("UPDATE rooms SET default_alert_limit_seconds = ?, updated_at = ? WHERE id = ?", (limit_val, now_iso, room_id))

    # Natychmiast zaktualizuj także trwającą sesję dla tej sali
    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (room_id,))
    active_session = cursor.fetchone()
    if active_session:
        started_dt = parse_iso(active_session["started_at"])
        due_dt = started_dt + timedelta(seconds=limit_val)
        due_iso = due_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        cursor.execute("UPDATE occupancy_sessions SET alert_limit_seconds = ?, alert_due_at = ? WHERE id = ?", (limit_val, due_iso, active_session["id"]))
        cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (active_session["id"],))
        active_session = cursor.fetchone()

    db.commit()
    actor_id = user["id"] if user else (device["id"] if device else "public_client")
    log_audit(db, "user" if user else "system", actor_id, "room_default_limit_changed", "room", room_id, {"new_limit": limit_val})

    formatted_session = format_active_session(active_session)
    await ws_manager.broadcast("room.updated", {
        "room_id": room_id,
        "default_alert_limit_seconds": limit_val,
        "active_session": formatted_session
    })

    return {
        "status": "success",
        "room_id": room_id,
        "default_alert_limit_seconds": limit_val,
        "active_session": formatted_session
    }

@app.patch("/api/v1/sessions/{session_id}/alert-limit", tags=["Limits"])
async def update_active_session_limit(
    session_id: str,
    req: AlertLimitChangeRequest,
    admin: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db)
):
    if req.alert_limit_seconds is None:
        raise DomainException(400, "VALIDATION_ERROR", "Wymagana wartość alert_limit_seconds.")

    cursor = db.cursor()
    cursor.execute("SELECT value FROM system_settings WHERE key = 'max_alert_limit_seconds'")
    max_limit = int(cursor.fetchone()["value"])
    if req.alert_limit_seconds > max_limit:
        raise DomainException(400, "ALERT_LIMIT_EXCEEDS_MAXIMUM", f"Limit przekracza maksimum ({max_limit} s).", {"maximum_seconds": max_limit})

    cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (session_id,))
    sess = cursor.fetchone()
    if not sess or sess["ended_at"] is not None:
        raise DomainException(400, "SESSION_NOT_ACTIVE", "Sesja nie istnieje lub została już zakończona.")

    started_dt = parse_iso(sess["started_at"])
    new_due_dt = started_dt + timedelta(seconds=req.alert_limit_seconds)
    new_due_iso = new_due_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    cursor.execute("UPDATE occupancy_sessions SET alert_limit_seconds = ?, alert_due_at = ? WHERE id = ?", (req.alert_limit_seconds, new_due_iso, session_id))
    db.commit()

    log_audit(db, "user", admin["id"], "session_limit_changed", "session", session_id, {"new_limit": req.alert_limit_seconds, "new_due_at": new_due_iso})

    # Broadcast update
    cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (session_id,))
    upd_sess = cursor.fetchone()
    await ws_manager.broadcast("room.updated", {
        "room_id": sess["room_id"],
        "status": "occupied",
        "active_session": format_active_session(upd_sess)
    })

    return {"status": "success", "session_id": session_id, "alert_limit_seconds": req.alert_limit_seconds, "alert_due_at": new_due_iso}

@app.get("/api/v1/admin/settings", tags=["Limits"])
def get_system_settings(admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM system_settings")
    rows = cursor.fetchall()
    return {r["key"]: int(r["value"]) if r["value"].isdigit() else r["value"] for r in rows}

class SystemSettingsUpdateRequest(BaseModel):
    default_alert_limit_seconds: Optional[int] = Field(None, ge=1)
    max_alert_limit_seconds: Optional[int] = Field(None, ge=1)

@app.patch("/api/v1/admin/settings", tags=["Limits"])
def update_system_settings(req: SystemSettingsUpdateRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    if req.max_alert_limit_seconds is not None:
        cursor.execute("UPDATE system_settings SET value = ? WHERE key = 'max_alert_limit_seconds'", (str(req.max_alert_limit_seconds),))
    if req.default_alert_limit_seconds is not None:
        cursor.execute("UPDATE system_settings SET value = ? WHERE key = 'default_alert_limit_seconds'", (str(req.default_alert_limit_seconds),))
    db.commit()
    log_audit(db, "user", admin["id"], "system_settings_updated", "system", "settings", req.dict(exclude_none=True))
    return {"status": "success", "settings": req.dict(exclude_none=True)}

# ==============================================================================
# 6.5 Administracja salami i kontami
# ==============================================================================
class CreateRoomRequest(BaseModel):
    id: str
    name: str
    location: Optional[str] = ""
    floor: str = "Parter"
    category: str = "Laboratorium"
    description: Optional[str] = ""
    capacity: int = 30
    posX: Optional[float] = None
    posY: Optional[float] = None
    svg_id: Optional[str] = None
    default_alert_limit_seconds: Optional[int] = None

@app.post("/api/v1/admin/rooms", tags=["Admin"])
def create_room(req: CreateRoomRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT id FROM rooms WHERE id = ?", (req.id,))
    if cursor.fetchone():
        raise DomainException(409, "ROOM_ASSIGNMENT_CONFLICT", f"Sala o identyfikatorze '{req.id}' już istnieje.")
    
    now = utc_now()
    cursor.execute("""
        INSERT INTO rooms (id, name, location, floor, category, description, capacity, posX, posY, svg_id, default_alert_limit_seconds, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'free', ?, ?)
    """, (req.id, req.name, req.location, req.floor, req.category, req.description, req.capacity, req.posX, req.posY, req.svg_id, req.default_alert_limit_seconds, now, now))
    db.commit()
    log_audit(db, "user", admin["id"], "room_created", "room", req.id)
    return {"status": "success", "id": req.id}

class UpdateRoomRequest(BaseModel):
    name: Optional[str] = None
    location: Optional[str] = None
    floor: Optional[str] = None
    category: Optional[str] = None
    description: Optional[str] = None
    capacity: Optional[int] = None
    posX: Optional[float] = None
    posY: Optional[float] = None
    operator_id: Optional[str] = None
    svg_id: Optional[str] = None
    default_alert_limit_seconds: Optional[int] = None

@app.patch("/api/v1/admin/rooms/{room_id}", tags=["Admin"])
def update_room_admin(room_id: str, req: UpdateRoomRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    room = cursor.fetchone()
    if not room:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")

    fields = []
    values = []
    for k, v in req.dict(exclude_unset=True).items():
        fields.append(f"{k} = ?")
        values.append(v)
    
    if fields:
        fields.append("updated_at = ?")
        values.append(utc_now())
        values.append(room_id)
        cursor.execute(f"UPDATE rooms SET {', '.join(fields)} WHERE id = ?", values)
        db.commit()
        log_audit(db, "user", admin["id"], "room_updated", "room", room_id, req.dict(exclude_unset=True))
    
    return {"status": "success", "room_id": room_id}

class RoomLocksRequest(BaseModel):
    lock_status: Optional[bool] = None
    lock_info: Optional[bool] = None
    lock_layout: Optional[bool] = None

@app.patch("/api/v1/admin/rooms/{room_id}/locks", tags=["Admin"])
def set_room_locks(room_id: str, req: RoomLocksRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    if not cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (room_id,)).fetchone():
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    values = {k: v for k, v in req.dict(exclude_unset=True).items() if v is not None}
    if values:
        sets = ", ".join(f"{k} = ?" for k in values)
        cursor.execute(f"UPDATE rooms SET {sets}, updated_at = ? WHERE id = ?",
                       list(values.values()) + [utc_now(), room_id])
        db.commit()
        log_audit(db, "user", admin["id"], "room_locks_changed", "room", room_id, values)
    row = cursor.execute("SELECT lock_status, lock_info, lock_layout FROM rooms WHERE id = ?", (room_id,)).fetchone()
    return {"status": "success", "room_id": room_id,
            "lock_status": bool(row["lock_status"]), "lock_info": bool(row["lock_info"]),
            "lock_layout": bool(row["lock_layout"])}

@app.delete("/api/v1/admin/rooms/{room_id}", tags=["Admin"])
def delete_room_admin(room_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT id FROM rooms WHERE id = ?", (room_id,))
    if not cursor.fetchone():
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    cursor.execute("DELETE FROM rooms WHERE id = ?", (room_id,))
    db.commit()
    log_audit(db, "user", admin["id"], "room_deleted", "room", room_id)
    return {"status": "success", "message": "Sala została usunięta."}

class RoomPositionRequest(BaseModel):
    posX: float
    posY: float

@app.post("/api/v1/admin/rooms/{room_id}/position", tags=["Admin"])
async def set_room_position(room_id: str, req: RoomPositionRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    room = cursor.fetchone()
    if not room:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    now = utc_now()
    cursor.execute("UPDATE rooms SET posX = ?, posY = ?, updated_at = ? WHERE id = ?", (req.posX, req.posY, now, room_id))
    db.commit()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    updated = build_room_representation(cursor.fetchone(), db)
    await broadcast_ws_event("room.updated", updated)
    return {"status": "success", "room": updated}

class RoomLayoutRequest(BaseModel):
    scale: float = Field(1.0, ge=0.4, le=3.0)
    angle: float = Field(0.0, ge=-360, le=360)

@app.post("/api/v1/admin/rooms/{room_id}/layout", tags=["Admin"])
async def set_room_layout(room_id: str, req: RoomLayoutRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    """Rozmiar (skala) i obrót sali na planie budynku."""
    cursor = db.cursor()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    if not cursor.fetchone():
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    scale = round(max(0.4, min(3.0, float(req.scale))), 3)
    angle = float(req.angle) % 360.0
    if angle > 180:
        angle -= 360
    now = utc_now()
    cursor.execute(
        "UPDATE rooms SET layout_scale = ?, layout_angle = ?, updated_at = ? WHERE id = ?",
        (scale, round(angle, 2), now, room_id),
    )
    db.commit()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    updated = build_room_representation(cursor.fetchone(), db)
    await broadcast_ws_event("room.updated", updated)
    return {"status": "success", "room": updated}

class RoomPathRequest(BaseModel):
    path: str = Field(..., max_length=2000)


@app.post("/api/v1/admin/rooms/{room_id}/path", tags=["Admin"])
async def set_room_path(room_id: str, req: RoomPathRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    """Własna ścieżka (linie) sali na planie; pusty string przywraca domyślną."""
    raw = req.path.strip()
    if raw and not re.fullmatch(r"[MLZ0-9.\s\-]+", raw):
        raise DomainException(400, "INVALID_PATH", "Nieprawidłowa ścieżka sali.")
    cursor = db.cursor()
    cursor.execute("SELECT 1 FROM rooms WHERE id = ?", (room_id,))
    if not cursor.fetchone():
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Sala nie istnieje.")
    now = utc_now()
    cursor.execute(
        "UPDATE rooms SET custom_path = ?, updated_at = ? WHERE id = ?",
        (raw or None, now, room_id),
    )
    db.commit()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    updated = build_room_representation(cursor.fetchone(), db)
    await broadcast_ws_event("room.updated", updated)
    return {"status": "success", "room": updated}


class ResetPositionsRequest(BaseModel):
    floor: Optional[str] = None

@app.post("/api/v1/admin/rooms/reset-positions", tags=["Admin"])
def reset_room_positions(req: ResetPositionsRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    now = utc_now()
    if req.floor and req.floor != "Wszystkie":
        cursor.execute("UPDATE rooms SET posX = NULL, posY = NULL, layout_scale = NULL, layout_angle = NULL, custom_path = NULL, updated_at = ? WHERE floor = ?", (now, req.floor))
    else:
        cursor.execute("UPDATE rooms SET posX = NULL, posY = NULL, layout_scale = NULL, layout_angle = NULL, custom_path = NULL, updated_at = ?", (now,))
    db.commit()
    cursor.execute("SELECT * FROM rooms ORDER BY sortOrder ASC, id ASC")
    rooms = [build_room_representation(r, db) for r in cursor.fetchall()]
    return {"status": "success", "rooms": rooms}

class ReorderRoomsRequest(BaseModel):
    roomIds: List[str]

@app.post("/api/v1/admin/rooms/reorder", tags=["Admin"])
def reorder_rooms(req: ReorderRoomsRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    now = utc_now()
    for idx, r_id in enumerate(req.roomIds):
        cursor.execute("UPDATE rooms SET sortOrder = ?, updated_at = ? WHERE id = ?", (idx, now, r_id))
    db.commit()
    cursor.execute("SELECT * FROM rooms ORDER BY sortOrder ASC, id ASC")
    rooms = [build_room_representation(r, db) for r in cursor.fetchall()]
    return {"status": "success", "rooms": rooms}

@app.get("/api/v1/admin/users", tags=["Admin"])
def list_users(admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT id, username, display_name, role, room_id, is_active, created_at, updated_at FROM users ORDER BY created_at DESC")
    return [dict(r) for r in cursor.fetchall()]

class CreateUserRequest(BaseModel):
    username: str
    password: str
    display_name: str
    role: str = Field(..., pattern="^(admin|operator)$")
    room_id: Optional[str] = None

@app.post("/api/v1/admin/users", tags=["Admin"])
def create_user(req: CreateUserRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT id FROM users WHERE username = ?", (req.username.strip(),))
    if cursor.fetchone():
        raise DomainException(409, "VALIDATION_ERROR", "Użytkownik o takim loginie już istnieje.")

    user_id = str(uuid.uuid4())
    now = utc_now()
    p_hash = hash_password(req.password)

    cursor.execute("""
        INSERT INTO users (id, username, password_hash, display_name, role, room_id, is_active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
    """, (user_id, req.username.strip(), p_hash, req.display_name, req.role, req.room_id, now, now))

    if req.role == "operator" and req.room_id:
        cursor.execute("UPDATE rooms SET operator_id = ? WHERE id = ?", (user_id, req.room_id))

    db.commit()
    log_audit(db, "user", admin["id"], "user_created", "user", user_id, {"username": req.username, "role": req.role})
    return {"status": "success", "id": user_id, "username": req.username}

class UpdateUserRequest(BaseModel):
    display_name: Optional[str] = None
    role: Optional[str] = None
    room_id: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = None

@app.patch("/api/v1/admin/users/{user_id}", tags=["Admin"])
def update_user_admin(user_id: str, req: UpdateUserRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    user = cursor.fetchone()
    if not user:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Użytkownik nie istnieje.")

    fields = []
    values = []
    if req.display_name is not None:
        fields.append("display_name = ?")
        values.append(req.display_name)
    if req.role is not None:
        fields.append("role = ?")
        values.append(req.role)
    if req.room_id is not None:
        fields.append("room_id = ?")
        values.append(req.room_id)
        cursor.execute("UPDATE rooms SET operator_id = ? WHERE id = ?", (user_id, req.room_id))
    if req.is_active is not None:
        fields.append("is_active = ?")
        values.append(1 if req.is_active else 0)
    if req.password is not None:
        fields.append("password_hash = ?")
        values.append(hash_password(req.password))

    if fields:
        fields.append("updated_at = ?")
        values.append(utc_now())
        values.append(user_id)
        cursor.execute(f"UPDATE users SET {', '.join(fields)} WHERE id = ?", values)
        db.commit()
        log_audit(db, "user", admin["id"], "user_updated", "user", user_id)

    return {"status": "success", "user_id": user_id}

class PasswordResetRequest(BaseModel):
    new_password: Optional[str] = None

@app.post("/api/v1/admin/users/{user_id}/password-reset", tags=["Admin"])
def reset_user_password(user_id: str, req: PasswordResetRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    user = cursor.fetchone()
    if not user:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Użytkownik nie istnieje.")
    
    new_pass = req.new_password.strip() if (req.new_password and req.new_password.strip()) else secrets.token_urlsafe(8)
    cursor.execute("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?", (hash_password(new_pass), utc_now(), user_id))
    cursor.execute("DELETE FROM auth_tokens WHERE user_id = ?", (user_id,))
    db.commit()
    log_audit(db, "user", admin["id"], "password_reset", "user", user_id)
    return {"status": "success", "user_id": user_id, "new_password": new_pass}

# ==============================================================================
# 6.6 Urządzenia ESP8266
# ==============================================================================
def device_payload(db: sqlite3.Connection, dev: sqlite3.Row) -> Dict[str, Any]:
    """Reprezentacja urządzenia używana przez panel administratora."""
    room = None
    operator = None
    if dev["room_id"]:
        room_row = db.execute(
            "SELECT id, name, floor, status, is_break, operator_id FROM rooms WHERE id = ?",
            (dev["room_id"],)
        ).fetchone()
        if room_row:
            room = {
                "id": room_row["id"],
                "name": room_row["name"],
                "floor": room_row["floor"],
                "status": room_row["status"],
                "is_break": bool(room_row["is_break"]),
            }
            if room_row["operator_id"]:
                user = db.execute(
                    "SELECT id, username, display_name FROM users WHERE id = ?",
                    (room_row["operator_id"],)
                ).fetchone()
                if user:
                    operator = dict(user)
    device_type = dev["device_type"]
    return {
        "id": dev["id"],
        "name": dev["name"],
        "device_type": device_type,
        "room_id": dev["room_id"],
        "room": room,
        "operator": operator,
        "is_active": bool(dev["is_active"]),
        "last_seen_at": dev["last_seen_at"],
        "created_at": dev["created_at"],
        "updated_at": dev["updated_at"],
        "firmware_version": dev["firmware_version"],
        "chip_type": dev["chip_type"],
        "pair_code_hint": dev["pair_code_hint"],
        "capabilities": {
            "can_set_status": device_type == "controller",
            "can_show_only": device_type in ("kiosk", "display"),
        },
    }

class RegisterDeviceRequest(BaseModel):
    name: str
    room_id: Optional[str] = None
    device_type: Optional[str] = None

@app.post("/api/v1/admin/devices", tags=["Devices"])
def register_device(req: RegisterDeviceRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    device_type = (req.device_type or "controller").lower()
    if device_type not in DEVICE_TYPES:
        raise DomainException(400, "INVALID_DEVICE_TYPE", "Nieprawidłowy typ urządzenia.")

    raw_token = secrets.token_hex(20)
    token_h = hash_token(raw_token)
    device_id = str(uuid.uuid4())
    now = utc_now()

    cursor = db.cursor()
    pair_code = new_pair_code(cursor)
    cursor.execute("""
        INSERT INTO devices (id, name, token_hash, room_id, is_active, last_seen_at, created_at, updated_at,
                             device_type, pair_code_hash, pair_code_hint)
        VALUES (?, ?, ?, ?, 1, NULL, ?, ?, ?, ?, ?)
    """, (device_id, req.name, token_h, req.room_id, now, now, device_type, hash_token(pair_code), pair_code))

    if req.room_id:
        cursor.execute("UPDATE rooms SET device_id = ? WHERE id = ?", (device_id, req.room_id))

    db.commit()
    log_audit(db, "user", admin["id"], "device_registered", "device", device_id,
              {"name": req.name, "room_id": req.room_id, "device_type": device_type})

    return {
        "status": "success",
        "device_id": device_id,
        "name": req.name,
        "device_type": device_type,
        "pair_code": pair_code,
        "token": raw_token # Only returned once at registration
    }

@app.get("/api/v1/admin/devices", tags=["Devices"])
def list_devices(admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("""
        SELECT id, name, device_type, room_id, is_active, last_seen_at, created_at, updated_at,
               firmware_version, chip_type, pair_code_hint
        FROM devices
    """)
    return [dict(r) for r in cursor.fetchall()]

class DeviceResolveRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=32)

@app.post("/api/v1/admin/devices/resolve", tags=["Devices"])
def resolve_device(req: DeviceResolveRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    code = normalize_pair_code(req.code)
    if not is_valid_pair_code(code):
        raise DomainException(400, "INVALID_DEVICE_CODE", "Nieprawidłowy kod urządzenia.")
    dev = db.execute("SELECT * FROM devices WHERE pair_code_hash = ?", (hash_token(code),)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Nie znaleziono urządzenia o podanym kodzie.")
    log_audit(db, "user", admin["id"], "device_resolved", "device", dev["id"], {"channel": "code"})
    return device_payload(db, dev)

@app.get("/api/v1/admin/devices/{device_id}", tags=["Devices"])
def get_device(device_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    dev = db.execute("SELECT * FROM devices WHERE id = ?", (device_id,)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    return device_payload(db, dev)

@app.get("/api/v1/admin/devices/{device_id}/audit", tags=["Devices"])
def get_device_audit(device_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    dev = db.execute("SELECT 1 FROM devices WHERE id = ?", (device_id,)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    rows = db.execute("""
        SELECT id, created_at, actor_type, actor_id, action, resource_type, resource_id, details
        FROM audit_logs
        WHERE resource_type = 'device' AND resource_id = ?
        ORDER BY created_at DESC
        LIMIT 100
    """, (device_id,)).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        try:
            item["details"] = json.loads(item["details"] or "{}")
        except (ValueError, TypeError):
            item["details"] = {}
        result.append(item)
    return result

@app.post("/api/v1/admin/devices/{device_id}/rotate-token", tags=["Devices"])
def rotate_device_token(device_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    dev = db.execute("SELECT 1 FROM devices WHERE id = ?", (device_id,)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    raw_token = secrets.token_hex(20)
    db.execute(
        "UPDATE devices SET token_hash = ?, updated_at = ? WHERE id = ?",
        (hash_token(raw_token), utc_now(), device_id)
    )
    db.commit()
    log_audit(db, "user", admin["id"], "device_token_rotated", "device", device_id, {})
    return {"status": "success", "device_id": device_id, "token": raw_token}

@app.post("/api/v1/admin/devices/{device_id}/rotate-pair-code", tags=["Devices"])
def rotate_device_pair_code(device_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    dev = cursor.execute("SELECT 1 FROM devices WHERE id = ?", (device_id,)).fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    pair_code = new_pair_code(cursor)
    cursor.execute(
        "UPDATE devices SET pair_code_hash = ?, pair_code_hint = ?, updated_at = ? WHERE id = ?",
        (hash_token(pair_code), pair_code, utc_now(), device_id)
    )
    db.commit()
    log_audit(db, "user", admin["id"], "device_pair_code_rotated", "device", device_id, {})
    return {"status": "success", "device_id": device_id, "pair_code": pair_code}

class UpdateDeviceRequest(BaseModel):
    name: Optional[str] = None
    room_id: Optional[str] = None
    is_active: Optional[bool] = None
    device_type: Optional[str] = None

@app.patch("/api/v1/admin/devices/{device_id}", tags=["Devices"])
def update_device(device_id: str, req: UpdateDeviceRequest, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM devices WHERE id = ?", (device_id,))
    dev = cursor.fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    
    fields = []
    params = []
    if req.name is not None:
        fields.append("name = ?")
        params.append(req.name)
    if req.room_id is not None:
        fields.append("room_id = ?")
        params.append(req.room_id)
        cursor.execute("UPDATE rooms SET device_id = NULL WHERE device_id = ?", (device_id,))
        if req.room_id:
            cursor.execute("UPDATE rooms SET device_id = ? WHERE id = ?", (device_id, req.room_id))
    if req.is_active is not None:
        fields.append("is_active = ?")
        params.append(1 if req.is_active else 0)
    if req.device_type is not None:
        device_type = req.device_type.lower()
        if device_type not in DEVICE_TYPES:
            raise DomainException(400, "INVALID_DEVICE_TYPE", "Nieprawidłowy typ urządzenia.")
        fields.append("device_type = ?")
        params.append(device_type)
    
    if fields:
        fields.append("updated_at = ?")
        params.append(utc_now())
        params.append(device_id)
        cursor.execute(f"UPDATE devices SET {', '.join(fields)} WHERE id = ?", params)
        db.commit()
    
    log_audit(db, "user", admin["id"], "device_updated", "device", device_id, req.model_dump(exclude_unset=True))
    updated = db.execute("SELECT * FROM devices WHERE id = ?", (device_id,)).fetchone()
    return device_payload(db, updated)

@app.delete("/api/v1/admin/devices/{device_id}", tags=["Devices"])
def delete_device(device_id: str, admin: sqlite3.Row = Depends(require_admin), db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT * FROM devices WHERE id = ?", (device_id,))
    dev = cursor.fetchone()
    if not dev:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Urządzenie nie istnieje.")
    cursor.execute("UPDATE rooms SET device_id = NULL WHERE device_id = ?", (device_id,))
    cursor.execute("DELETE FROM devices WHERE id = ?", (device_id,))
    db.commit()
    log_audit(db, "user", admin["id"], "device_deleted", "device", device_id, {"name": dev["name"]})
    return {"status": "success", "message": "Urządzenie zostało usunięte."}

@app.get("/api/v1/device/state", tags=["Devices"])
def get_device_assigned_room_state(
    device: sqlite3.Row = Depends(require_device),
    x_firmware_version: Optional[str] = Header(None),
    x_chip_type: Optional[str] = Header(None),
    db: sqlite3.Connection = Depends(get_db)
):
    room_id = device["room_id"]
    if not room_id:
        raise DomainException(400, "ROOM_NOT_ASSIGNED", "Urządzenie nie ma przypisanej sali.")
    
    cursor = db.cursor()
    cursor.execute("""
        SELECT r.*, 
               s.id as s_id, s.started_at as s_started_at, s.alert_limit_seconds as s_limit, 
               s.alert_due_at as s_due_at, s.alert_triggered_at as s_triggered_at, s.occupant_name as s_occupant
        FROM rooms r
        LEFT JOIN occupancy_sessions s ON r.id = s.room_id AND s.ended_at IS NULL
        WHERE r.id = ?
    """, (room_id,))
    r = cursor.fetchone()
    if not r:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Przypisana sala nie istnieje.")

    session_data = None
    if r["s_id"]:
        session_data = format_active_session({
            "id": r["s_id"],
            "room_id": r["id"],
            "started_at": r["s_started_at"],
            "alert_limit_seconds": r["s_limit"],
            "alert_due_at": r["s_due_at"],
            "alert_triggered_at": r["s_triggered_at"],
            "occupant_name": r["s_occupant"]
        })

    # Update device last_seen_at and metadata
    dev_name = device["name"].lower()
    chip = (x_chip_type or ("esp32" if ("cyd" in dev_name or "32" in dev_name) else "esp8266")).lower()

    update_fields = ["last_seen_at = ?", "chip_type = ?"]
    update_params = [utc_now(), chip]
    if x_firmware_version:
        update_fields.append("firmware_version = ?")
        update_params.append(x_firmware_version)
    update_params.append(device["id"])

    cursor.execute(f"UPDATE devices SET {', '.join(update_fields)} WHERE id = ?", update_params)
    db.commit()

    is_esp8266 = "8266" in chip or "wemos" in chip
    fw_ver = "1.3.10" if is_esp8266 else "1.3.8"
    bin_name = "esp8266_firmware.bin" if is_esp8266 else "cyd_firmware.bin"
    bin_path = os.path.join(BASE_DIR, bin_name)
    has_update = os.path.exists(bin_path)
    chip_tag = "esp8266" if is_esp8266 else "esp32"
    fw_url = f"https://sale.pwojtaszek.5g.in/api/v1/firmware/download?chip={chip_tag}&v={fw_ver.replace('.', '')}"

    return {
        "device_id": device["id"],
        "room_id": r["id"],
        "room_name": r["name"],
        "status": r["status"],
        "server_time": utc_now(),
        "active_session": session_data,
        "firmware": {
            "chip": chip,
            "version": fw_ver,
            "has_update": has_update,
            "url": fw_url
        }
    }

@app.post("/api/v1/device/status", tags=["Devices"])
async def set_device_room_status(
    req: StatusChangeRequest,
    device: sqlite3.Row = Depends(require_device),
    db: sqlite3.Connection = Depends(get_db)
):
    room_id = device["room_id"]
    if not room_id:
        raise DomainException(400, "ROOM_NOT_ASSIGNED", "Urządzenie nie ma przypisanej sali.")
    ensure_room_unlocked(db, room_id, "lock_status")

    cursor = db.cursor()
    cursor.execute("SELECT * FROM rooms WHERE id = ?", (room_id,))
    room = cursor.fetchone()
    if not room:
        raise DomainException(404, "RESOURCE_NOT_FOUND", "Przypisana sala nie istnieje.")

    target_status = req.status
    current_status = room["status"]
    target_break = req.is_break
    current_break = bool(room["is_break"]) if "is_break" in room.keys() else False
    now_iso = utc_now()
    now_dt = parse_iso(now_iso)
    changed = False

    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (room_id,))
    active_session = cursor.fetchone()

    actor_str = f"device:{device['id']}"

    starting_session = (
        target_status == "occupied"
        and not target_break
        and (current_status == "free" or (current_status == "occupied" and current_break))
    )

    if starting_session:
        effective_limit = room["default_alert_limit_seconds"]
        if not effective_limit:
            cursor.execute("SELECT value FROM system_settings WHERE key = 'default_alert_limit_seconds'")
            row = cursor.fetchone()
            effective_limit = int(row["value"]) if row else 900
        
        due_dt = now_dt + timedelta(seconds=effective_limit)
        due_iso = due_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        session_id = str(uuid.uuid4())

        cursor.execute("""
            INSERT INTO occupancy_sessions (id, room_id, started_at, ended_at, alert_limit_seconds, alert_due_at, alert_triggered_at, started_by, ended_by)
            VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, NULL)
        """, (session_id, room_id, now_iso, effective_limit, due_iso, actor_str))

        cursor.execute("UPDATE rooms SET status = 'occupied', is_break = 0, updated_at = ? WHERE id = ?", (now_iso, room_id))
        changed = True

        cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (session_id,))
        active_session = cursor.fetchone()
        log_audit(db, "device", device["id"], "session_started", "room", room_id, {"session_id": session_id})

    elif target_status == "occupied" and target_break and (current_status != "occupied" or not current_break):
        if active_session:
            cursor.execute("UPDATE occupancy_sessions SET ended_at = ?, ended_by = ? WHERE id = ?", (now_iso, actor_str, active_session["id"]))
        cursor.execute("UPDATE rooms SET status = 'occupied', is_break = 1, updated_at = ? WHERE id = ?", (now_iso, room_id))
        changed = True
        active_session = None
        log_audit(db, "device", device["id"], "break_started", "room", room_id)

    elif target_status == "free" and (current_status == "occupied" or current_break):
        if active_session:
            cursor.execute("UPDATE occupancy_sessions SET ended_at = ?, ended_by = ? WHERE id = ?", (now_iso, actor_str, active_session["id"]))
        cursor.execute("UPDATE rooms SET status = 'free', is_break = 0, updated_at = ? WHERE id = ?", (now_iso, room_id))
        changed = True
        log_audit(db, "device", device["id"], "session_ended", "room", room_id, {"session_id": active_session["id"] if active_session else None})
        active_session = None

    cursor.execute("UPDATE devices SET last_seen_at = ? WHERE id = ?", (now_iso, device["id"]))
    db.commit()

    formatted_session = format_active_session(active_session)
    if changed:
        await ws_manager.broadcast("room.updated", {
            "room_id": room_id,
            "status": target_status,
            "is_break": target_break,
            "active_session": formatted_session
        })

    return {
        "room_id": room_id,
        "status": target_status,
        "is_break": target_break,
        "changed": changed,
        "active_session": formatted_session
    }

@app.post("/api/v1/device/heartbeat", tags=["Devices"])
def device_heartbeat(device: sqlite3.Row = Depends(require_device), db: sqlite3.Connection = Depends(get_db)):
    now = utc_now()
    cursor = db.cursor()
    cursor.execute("UPDATE devices SET last_seen_at = ? WHERE id = ?", (now, device["id"]))
    db.commit()
    return {"status": "ok", "server_time": now}

class DeviceAlertLimitRequest(BaseModel):
    limit_seconds: Optional[int] = None
    alert_limit_seconds: Optional[int] = None

@app.post("/api/v1/device/alert-limit", tags=["Devices"])
@app.patch("/api/v1/device/alert-limit", tags=["Devices"])
async def device_set_alert_limit(
    req: DeviceAlertLimitRequest,
    room_id: Optional[str] = None,
    device: Optional[sqlite3.Row] = Depends(get_current_device_optional),
    user: Optional[sqlite3.Row] = Depends(get_current_user_optional),
    db: sqlite3.Connection = Depends(get_db)
):
    target_room_id = room_id
    if device:
        target_room_id = device["room_id"]
    elif user:
        if not target_room_id:
            target_room_id = user["room_id"]
    else:
        raise DomainException(401, "UNAUTHENTICATED", "Wymagana autoryzacja urządzenia lub użytkownika.")

    if not target_room_id:
        raise DomainException(400, "ROOM_NOT_ASSIGNED", "Brak przypisanej sali.")
    if user and user["role"] == "operator" and user["room_id"] != target_room_id:
        raise DomainException(403, "FORBIDDEN", "Operator może zmieniać czas wyłącznie swojej sali.")
    ensure_room_unlocked(db, target_room_id, "lock_info", user)

    limit_val = req.limit_seconds or req.alert_limit_seconds
    if not limit_val or limit_val <= 0:
        raise DomainException(400, "VALIDATION_ERROR", "Niepoprawna wartość limit_seconds.")

    cursor = db.cursor()
    now_iso = utc_now()
    cursor.execute("UPDATE rooms SET default_alert_limit_seconds = ?, updated_at = ? WHERE id = ?", (limit_val, now_iso, target_room_id))

    cursor.execute("SELECT * FROM occupancy_sessions WHERE room_id = ? AND ended_at IS NULL", (target_room_id,))
    active_session = cursor.fetchone()
    if active_session:
        started_dt = parse_iso(active_session["started_at"])
        due_dt = started_dt + timedelta(seconds=limit_val)
        due_iso = due_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        cursor.execute("UPDATE occupancy_sessions SET alert_limit_seconds = ?, alert_due_at = ? WHERE id = ?", (limit_val, due_iso, active_session["id"]))
        cursor.execute("SELECT * FROM occupancy_sessions WHERE id = ?", (active_session["id"],))
        active_session = cursor.fetchone()

    db.commit()
    formatted = format_active_session(active_session)
    await ws_manager.broadcast("room.updated", {
        "room_id": target_room_id,
        "active_session": formatted
    })
    return {"status": "success", "room_id": target_room_id, "default_alert_limit_seconds": limit_val, "active_session": formatted}

# ==============================================================================
# 6.7 WebSocket na żywo (/api/v1/ws)
# ==============================================================================
@app.websocket("/api/v1/ws")
async def websocket_endpoint(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        while True:
            # Keep connection alive, listen for ping/pong or client messages
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("type") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong", "time": utc_now()}))
            except Exception:
                pass
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception:
        ws_manager.disconnect(websocket)

# ==============================================================================
# System, Health & OTA App Updates
# ==============================================================================
@app.get("/api/v1/health", tags=["System"])
@app.get("/api/health", tags=["System"])
@app.get("/api/server-info", tags=["System"])
def health():
    lan_ip = get_primary_lan_ip()
    return {
        "status": "ok",
        "service": "DostepnoscSal-FastAPI",
        "contract_version": "0.1",
        "time": utc_now(),
        "lanIp": lan_ip,
        "lanUrl": f"http://{lan_ip}:{PORT}"
    }

@app.get("/api/service-info", tags=["System"])
def get_service_info(db: sqlite3.Connection = Depends(get_db)):
    cursor = db.cursor()
    cursor.execute("SELECT COUNT(*) FROM rooms")
    total_rooms = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM rooms WHERE status = 'free'")
    free_rooms = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM rooms WHERE status = 'occupied'")
    occupied_rooms = cursor.fetchone()[0]

    db_size = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0
    db_size_formatted = f"{db_size / 1024:.1f} KB" if db_size < 1048576 else f"{db_size / 1048576:.2f} MB"

    uptime_sec = int((datetime.now(timezone.utc) - SERVER_START_TIME).total_seconds())
    mins, sec = divmod(uptime_sec, 60)
    hours, mins = divmod(mins, 60)
    uptime_human = f"{hours}h {mins}m {sec}s" if hours > 0 else f"{mins}m {sec}s"

    return {
        "status": "ok",
        "service": "DostepnoscSal-FastAPI",
        "contract_version": "0.1",
        "uptime_human": uptime_human,
        "uptime_seconds": uptime_sec,
        "server_os": platform.platform(),
        "python_version": platform.python_version(),
        "sqlite_version": sqlite3.sqlite_version,
        "database": {
            "path": DB_PATH,
            "size_formatted": db_size_formatted,
            "total_rooms": total_rooms,
            "free_rooms": free_rooms,
            "occupied_rooms": occupied_rooms,
        },
        "traffic_metrics": {
            "total_requests": 150,
            "file_downloads": 1,
        }
    }

def _find_apk_file() -> str:
    """Find the latest (newest + largest) APK file from all candidate locations."""
    candidates = [
        os.path.join(BASE_DIR,       "DostepnoscSal.apk"),         # server/ — always updated by deploy_apk.py
        os.path.join(PROJECT_ROOT,   "DostepnoscSal.apk"),
        os.path.join(PROJECT_ROOT,   "build", "app", "outputs", "flutter-apk", "app-release.apk"),
        os.path.join(PROJECT_ROOT,   "build", "web", "DostepnoscSal.apk"),
    ]
    best = None
    best_mtime = 0
    for p in candidates:
        try:
            if os.path.exists(p) and os.path.getsize(p) > 10_000_000:
                mtime = os.path.getmtime(p)
                if mtime > best_mtime:
                    best_mtime = mtime
                    best = p
        except OSError:
            pass
    return best or os.path.join(BASE_DIR, "DostepnoscSal.apk")

@app.get("/api/app-version", tags=["System"])
@app.get("/api/v1/app-version", tags=["System"])
def get_app_version():
    apk_path = _find_apk_file()
    apk_size_actual = os.path.getsize(apk_path) if os.path.exists(apk_path) else 0

    # Load version metadata from file (written by deploy_apk.py after each build)
    ver = _load_app_version()
    version_code = ver.get("versionCode", 7)
    version_name = ver.get("versionName", "1.0.0")
    release_notes = ver.get("releaseNotes", "Nowa wersja jest dostępna.")
    # Prefer stored apkSize (exact), fallback to measured file size
    apk_size = ver.get("apkSize") or apk_size_actual
    # Prefer stored URL (has cache-buster param), otherwise build it
    apk_url = ver.get("apkUrl") or f"https://sale.pwojtaszek.5g.in/DostepnoscSal.apk?v={version_code}"

    return JSONResponse(
        content={
            "versionCode": version_code,
            "versionName": version_name,
            "apkUrl": apk_url,
            "apkSize": apk_size,
            "releaseNotes": release_notes,
        },
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
    )

@app.get("/DostepnoscSal.apk", tags=["System"])
@app.get("/dostepnoscsal.apk", tags=["System"])
def download_apk():
    """Download the latest APK (always newest build, bypasses cache via ?v=N query param)."""
    apk_path = _find_apk_file()
    if os.path.exists(apk_path):
        return FileResponse(
            apk_path,
            filename="DostepnoscSal.apk",
            media_type="application/vnd.android.package-archive",
            headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
        )
    raise HTTPException(status_code=404, detail="Plik APK nie został jeszcze zbudowany.")

@app.get("/DostepnoscSal_v{version}.apk", tags=["System"])
def download_apk_versioned(version: str):
    """Download versioned APK — always redirects to the latest build."""
    apk_path = _find_apk_file()
    if os.path.exists(apk_path):
        return FileResponse(
            apk_path,
            filename=f"DostepnoscSal_v{version}.apk",
            media_type="application/vnd.android.package-archive",
            headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
        )
    raise HTTPException(status_code=404, detail="Plik APK nie został jeszcze zbudowany.")

def _get_firmware_file(chip: str) -> str:
    c = chip.lower()
    if "8266" in c or "wemos" in c:
        return os.path.join(BASE_DIR, "esp8266_firmware.bin")
    return os.path.join(BASE_DIR, "cyd_firmware.bin")

@app.get("/api/v1/firmware/version", tags=["Firmware"])
def get_firmware_version(chip: str = "esp32"):
    fw_path = _get_firmware_file(chip)
    fw_size = os.path.getsize(fw_path) if os.path.exists(fw_path) else 0
    norm_chip = "esp8266" if "8266" in chip.lower() else "esp32"
    version = "1.3.10" if norm_chip == "esp8266" else "1.3.8"
    version_tag = version.replace(".", "")
    return JSONResponse(
        content={
            "chip": norm_chip,
            "version": version,
            "has_update": os.path.exists(fw_path),
            "firmware_url": f"https://sale.pwojtaszek.5g.in/api/v1/firmware/download?chip={norm_chip}&v={version_tag}",
            "firmware_size": fw_size,
            "release_notes": f"Wersja {version}: Zegar synchronizowany z serwerem (NTP jako zapas) oraz odswiezanie listy wolnych sal co 5 sekund."
        },
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
    )

@app.get("/api/v1/cyd-version", tags=["Firmware"])
def get_cyd_version():
    return get_firmware_version("esp32")

@app.get("/api/v1/esp8266-version", tags=["Firmware"])
def get_esp8266_version():
    return get_firmware_version("esp8266")

@app.get("/api/v1/firmware/download", tags=["Firmware"])
@app.get("/api/v1/cyd-firmware.bin", tags=["Firmware"])
@app.get("/api/v1/esp8266-firmware.bin", tags=["Firmware"])
def download_firmware(chip: str = "esp32"):
    fw_path = _get_firmware_file(chip)
    filename = os.path.basename(fw_path)
    if os.path.exists(fw_path):
        return FileResponse(
            fw_path,
            filename=filename,
            media_type="application/octet-stream",
            headers={"Cache-Control": "no-cache, no-store, must-revalidate"}
        )
    raise HTTPException(status_code=404, detail="Brak pliku oprogramowania firmware dla tego układu.")

# Static Web SPA serving (fallback for frontend build)
@app.get("/{full_path:path}", include_in_schema=False)
def serve_web_spa(full_path: str):
    no_cache_headers = {
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Pragma": "no-cache",
        "Expires": "0"
    }
    target = os.path.join(WEB_DIR, full_path)
    if os.path.isfile(target):
        return FileResponse(target, headers=no_cache_headers)
    index_path = os.path.join(WEB_DIR, "index.html")
    if os.path.isfile(index_path):
        return FileResponse(index_path, headers=no_cache_headers)
    return {"message": "DostępnośćSal API działa. Otwórz /docs aby zobaczyć dokumentację Swagger."}

# UDP Broadcast Beacon for local network discovery (Port 8082)
def start_udp_beacon():
    def worker():
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", 8082))
            while True:
                data, addr = sock.recvfrom(1024)
                msg = data.decode("utf-8", errors="ignore").strip()
                if "DISCOVER" in msg or "ROOM_SERVER" in msg:
                    lan_ip = get_primary_lan_ip()
                    reply = json.dumps({
                        "type": "ROOM_SERVER_ANNOUNCEMENT",
                        "lanIp": lan_ip,
                        "port": PORT,
                        "lanUrl": f"http://{lan_ip}:{PORT}"
                    })
                    sock.sendto(reply.encode("utf-8"), addr)
        except Exception as e:
            sys.stderr.write(f"[UDP Beacon] Error: {e}\n")

    t = threading.Thread(target=worker, daemon=True)
    t.start()

if __name__ == "__main__":
    init_db()
    start_udp_beacon()
    print("==================================================================")
    print(" Dostępność Sal - FastAPI Backend Server (Kontrakt v0.1)")
    print(f" Port: {PORT}")
    print(f" Baza SQLite: {DB_PATH}")
    print(f" Swagger UI: http://localhost:{PORT}/docs")
    print(f" OpenAPI JSON: http://localhost:{PORT}/api/v1/openapi.json")
    print(f" Adres lokalny: http://localhost:{PORT}")
    print("==================================================================")
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
