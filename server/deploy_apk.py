#!/usr/bin/env python3
"""
deploy_apk.py
-------------
Skrypt dystrybucji APK uruchamiany po każdym flutter build apk --release.

Kopiuje plik app-release.apk do wszystkich miejsc serwujących go przez Cloudflare,
i automatycznie AKTUALIZUJE server/app_version.json o nowy versionCode + versionName
odczytując je bezpośrednio z pliku APK poprzez AndroidManifest.xml (aapt/aapt2).

Użycie:
  python server/deploy_apk.py

Wymaganie: Android SDK Build-Tools muszą być zainstalowane (dla aapt2).
"""

import os
import sys
import json
import glob
import re
import shutil
import subprocess
from datetime import datetime

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_DIR    = os.path.join(PROJECT_ROOT, "server")
WEB_DIR       = os.path.join(PROJECT_ROOT, "build", "web")
SRC_APK       = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk")
VERSION_FILE  = os.path.join(SERVER_DIR, "app_version.json")

ANDROID_SDK = os.environ.get(
    "ANDROID_HOME",
    os.path.expanduser(r"~\AppData\Local\Android\Sdk")
)

def find_aapt2():
    """Finds aapt2.exe from Android SDK build-tools."""
    pattern = os.path.join(ANDROID_SDK, "build-tools", "*", "aapt2.exe")
    matches = sorted(glob.glob(pattern), reverse=True)
    if matches:
        return matches[0]
    # Fallback: aapt (old)
    pattern2 = os.path.join(ANDROID_SDK, "build-tools", "*", "aapt.exe")
    matches2 = sorted(glob.glob(pattern2), reverse=True)
    return matches2[0] if matches2 else None

def get_apk_version(apk_path: str) -> tuple[int, str] | None:
    """Extract versionCode and versionName from APK using aapt2/aapt."""
    aapt = find_aapt2()
    if not aapt:
        print("[deploy] WARNING: aapt2 not found — version will not be auto-detected.")
        return None

    try:
        if "aapt2" in aapt:
            result = subprocess.run(
                [aapt, "dump", "badging", apk_path],
                capture_output=True, text=True, timeout=15
            )
        else:
            result = subprocess.run(
                [aapt, "dump", "badging", apk_path],
                capture_output=True, text=True, timeout=15
            )

        output = result.stdout
        vc_match  = re.search(r"versionCode='(\d+)'", output)
        vn_match  = re.search(r"versionName='([^']+)'", output)

        if vc_match and vn_match:
            return int(vc_match.group(1)), vn_match.group(1)
    except Exception as e:
        print(f"[deploy] aapt error: {e}")
    return None

def update_version_json(version_code: int, version_name: str, apk_size: int):
    """Write/update server/app_version.json with new version info.
    Always reads with utf-8-sig (tolerates BOM) and writes without BOM.
    """
    if os.path.exists(VERSION_FILE):
        try:
            # utf-8-sig tolerates BOM written by PowerShell / Windows tools
            with open(VERSION_FILE, encoding="utf-8-sig") as f:
                data = json.load(f)
        except Exception:
            data = {}
    else:
        data = {}
    if "releaseNotes" not in data:
        data["releaseNotes"] = "Nowa wersja jest dostępna."

    old_code = data.get("versionCode", 0)
    data["versionCode"] = version_code
    data["versionName"] = version_name
    data["apkSize"] = apk_size
    data["apkUrl"]  = f"https://sale.pwojtaszek.5g.in/DostepnoscSal.apk?v={version_code}"
    data["builtAt"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"[deploy] app_version.json: v{old_code} → v{version_code} ({version_name}), size={apk_size}")

def copy_apk(src: str, version_name: str, version_code: int):
    """Copy APK to all distribution locations."""
    destinations = [
        os.path.join(PROJECT_ROOT,   "DostepnoscSal.apk"),
        os.path.join(PROJECT_ROOT,   f"DostepnoscSal_v{version_name}.apk"),
        os.path.join(SERVER_DIR,     "DostepnoscSal.apk"),
        os.path.join(SERVER_DIR,     f"DostepnoscSal_v{version_name}.apk"),
    ]
    # Add web dir if it exists
    if os.path.isdir(WEB_DIR):
        destinations += [
            os.path.join(WEB_DIR, "DostepnoscSal.apk"),
            os.path.join(WEB_DIR, f"DostepnoscSal_v{version_name}.apk"),
        ]

    # Remove old versioned APKs to avoid clutter
    for pattern in [
        os.path.join(PROJECT_ROOT, "DostepnoscSal_v*.apk"),
        os.path.join(SERVER_DIR,   "DostepnoscSal_v*.apk"),
        os.path.join(WEB_DIR,      "DostepnoscSal_v*.apk") if os.path.isdir(WEB_DIR) else "",
    ]:
        if pattern:
            for old in glob.glob(pattern):
                base = os.path.basename(old)
                if f"v{version_name}" not in base:
                    try:
                        os.remove(old)
                        print(f"[deploy] Usunięto starą wersję: {old}")
                    except Exception:
                        pass

    for dest in destinations:
        try:
            shutil.copy2(src, dest)
            print(f"[deploy] OK: {dest}")
        except Exception as e:
            print(f"[deploy] BŁĄD kopiowania do {dest}: {e}")

def main():
    print("\n=== deploy_apk.py ===")
    print(f"[deploy] Źródło: {SRC_APK}")

    if not os.path.exists(SRC_APK):
        print(f"[deploy] BŁĄD: Plik APK nie istnieje: {SRC_APK}")
        print("[deploy] Najpierw uruchom: flutter build apk --release")
        sys.exit(1)

    apk_size = os.path.getsize(SRC_APK)
    print(f"[deploy] Rozmiar APK: {apk_size / 1024 / 1024:.1f} MB")

    # Try to detect version from APK automatically
    version_info = get_apk_version(SRC_APK)
    if version_info:
        version_code, version_name = version_info
        print(f"[deploy] Wykryta wersja: {version_name} (versionCode={version_code})")
    else:
        # Fallback: read from app_version.json
        if os.path.exists(VERSION_FILE):
            with open(VERSION_FILE, encoding="utf-8") as f:
                existing = json.load(f)
            version_code = existing.get("versionCode", 1)
            version_name = existing.get("versionName", "1.0.0")
            print(f"[deploy] Wersja z app_version.json: {version_name} (versionCode={version_code})")
        else:
            print("[deploy] Nie można ustalić wersji. Podaj ręcznie:")
            version_name = input("  versionName (np. 1.4.0): ").strip() or "1.3.22"
            version_code = int(input("  versionCode (np. 26): ").strip() or "27")

    # Distribute APK
    copy_apk(SRC_APK, version_name, version_code)

    # Update version JSON
    update_version_json(version_code, version_name, apk_size)

    print(f"\n[deploy] ✓ Dystrybucja zakończona pomyślnie!")
    print(f"[deploy] APK URL: https://sale.pwojtaszek.5g.in/DostepnoscSal.apk?v={version_code}")
    print("[deploy] Zrestartuj sync_server.py jeśli jest uruchomiony, aby odświeżyć apkSize.\n")

if __name__ == "__main__":
    main()
