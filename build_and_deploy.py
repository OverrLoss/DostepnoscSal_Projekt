#!/usr/bin/env python3
"""
build_and_deploy.py
-------------------
Jednorazowy skrypt budowania CAŁEGO projektu (web + APK) i dystrybucji.

Użycie:
  python build_and_deploy.py                  # web + APK
  python build_and_deploy.py --web-only       # tylko web
  python build_and_deploy.py --apk-only       # tylko APK
  python build_and_deploy.py --apk-only --skip-build  # tylko deployment (bez flutter build)

Co robi:
  1. flutter build web --release
  2. flutter build apk --release
  3. Kopiuje APK do wszystkich lokalizacji serwera (server/, build/web/, PROJECT_ROOT/)
  4. Aktualizuje server/app_version.json z nowym versionCode, versionName i rozmiar
  5. Restartuje sync_server.py (opcjonalnie)
"""

import os
import sys
import json
import glob
import re
import shutil
import subprocess
from datetime import datetime
import argparse

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR   = os.path.join(PROJECT_ROOT, "server")
WEB_DIR      = os.path.join(PROJECT_ROOT, "build", "web")
SRC_APK      = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk")
VERSION_FILE = os.path.join(SERVER_DIR, "app_version.json")
PUBSPEC      = os.path.join(PROJECT_ROOT, "pubspec.yaml")

ANDROID_SDK = os.environ.get(
    "ANDROID_HOME",
    os.environ.get(
        "ANDROID_SDK_ROOT",
        os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Android", "Sdk")
    )
)


def run(cmd, cwd=None):
    print(f"\n>>> {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd or PROJECT_ROOT, shell=True)
    if result.returncode != 0:
        print(f"[build] BŁĄD: Komenda zakończona z kodem {result.returncode}")
        sys.exit(result.returncode)


def get_version_from_pubspec():
    """Extract version from pubspec.yaml, e.g. '1.3.2+7' → ('1.3.2', 7)."""
    try:
        with open(PUBSPEC, encoding="utf-8") as f:
            content = f.read()
        m = re.search(r"^version:\s*(\S+)", content, re.MULTILINE)
        if m:
            full = m.group(1)  # e.g. '1.3.2+7'
            if "+" in full:
                name, code = full.split("+", 1)
                return name.strip(), int(code.strip())
            return full.strip(), 1
    except Exception as e:
        print(f"[build] pubspec.yaml read error: {e}")
    return "1.0.0", 1


def find_aapt2():
    pattern = os.path.join(ANDROID_SDK, "build-tools", "*", "aapt2.exe")
    matches = sorted(glob.glob(pattern), reverse=True)
    return matches[0] if matches else None


def get_apk_version_from_apk(apk_path):
    """Try to extract version from APK directly via aapt2."""
    aapt = find_aapt2()
    if not aapt:
        return None
    try:
        result = subprocess.run(
            [aapt, "dump", "badging", apk_path],
            capture_output=True, text=True, timeout=20
        )
        output = result.stdout
        vc = re.search(r"versionCode='(\d+)'", output)
        vn = re.search(r"versionName='([^']+)'", output)
        if vc and vn:
            return vn.group(1), int(vc.group(1))
    except Exception:
        pass
    return None


def update_version_json(version_name, version_code, apk_size, release_notes=None):
    """Update server/app_version.json."""
    data = {}
    if os.path.exists(VERSION_FILE):
        try:
            with open(VERSION_FILE, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}

    if release_notes:
        data["releaseNotes"] = release_notes
    elif "releaseNotes" not in data:
        data["releaseNotes"] = "Nowa wersja jest dostępna."

    data["versionCode"] = version_code
    data["versionName"] = version_name
    data["apkSize"] = apk_size
    data["apkUrl"]  = f"https://sale.pwojtaszek.codes/DostepnoscSal.apk?v={version_code}"
    data["builtAt"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"\n[build] app_version.json → v{version_name} (code={version_code}) size={apk_size:,} B")


def distribute_apk(version_name, version_code):
    """Copy APK to all distribution locations and clean up old versioned files."""
    if not os.path.exists(SRC_APK):
        print(f"[build] BŁĄD: Brak pliku: {SRC_APK}")
        return

    apk_size = os.path.getsize(SRC_APK)

    locations = [
        PROJECT_ROOT,
        SERVER_DIR,
    ]
    if os.path.isdir(WEB_DIR):
        locations.append(WEB_DIR)

    # Remove old versioned APKs
    for loc in locations:
        for old in glob.glob(os.path.join(loc, "DostepnoscSal_v*.apk")):
            if f"v{version_name}" not in os.path.basename(old):
                try:
                    os.remove(old)
                    print(f"[build] Usunięto: {old}")
                except Exception:
                    pass

    # Copy to all locations
    for loc in locations:
        for dest_name in [
            "DostepnoscSal.apk",
            f"DostepnoscSal_v{version_name}.apk",
        ]:
            dest = os.path.join(loc, dest_name)
            try:
                shutil.copy2(SRC_APK, dest)
                print(f"[build] Skopiowano: {dest}")
            except Exception as e:
                print(f"[build] BŁĄD kopiowania do {dest}: {e}")

    return apk_size


def main():
    parser = argparse.ArgumentParser(description="Build & Deploy Dostępność Sal")
    parser.add_argument("--web-only",    action="store_true", help="Tylko Flutter Web")
    parser.add_argument("--apk-only",    action="store_true", help="Tylko APK Android")
    parser.add_argument("--skip-build",  action="store_true", help="Pomiń flutter build (tylko deploy)")
    parser.add_argument("--release-notes", default=None, help="Notatki do aktualizacji")
    args = parser.parse_args()

    build_web = not args.apk_only
    build_apk = not args.web_only

    version_name, version_code = get_version_from_pubspec()
    print(f"\n[build] Wersja z pubspec.yaml: v{version_name} (versionCode={version_code})")

    if not args.skip_build:
        if build_web:
            run(["flutter", "build", "web", "--release"])

        if build_apk:
            run(["flutter", "build", "apk", "--release"])

    if build_apk and os.path.exists(SRC_APK):
        # Try to get exact version from APK binary (most reliable)
        apk_ver = get_apk_version_from_apk(SRC_APK)
        if apk_ver:
            version_name, version_code = apk_ver
            print(f"[build] Wersja z APK: v{version_name} (versionCode={version_code})")

        apk_size = distribute_apk(version_name, version_code)
        update_version_json(
            version_name, version_code, apk_size,
            release_notes=args.release_notes
        )

    print("\n" + "=" * 60)
    print(f"  ✓ Build & Deploy zakończony pomyślnie!")
    print(f"  Wersja: v{version_name} (versionCode={version_code})")
    if build_apk:
        print(f"  APK URL: https://sale.pwojtaszek.codes/DostepnoscSal.apk?v={version_code}")
    print("=" * 60)
    print("\n  Zrestartuj teraz sync_server.py aby serwer wczytał nowe dane.\n")


if __name__ == "__main__":
    main()
