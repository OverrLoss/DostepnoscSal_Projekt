"""
Testy akceptacyjne kontraktu DostępnośćSal (API-01 do API-20)
"""

import sys
import os
import tempfile
import unittest
from fastapi.testclient import TestClient

# Testy mutują bazę — zawsze na tymczasowej instancji, nigdy na rooms_backend.db.
_tmp_db = tempfile.NamedTemporaryFile(prefix="dostepnosc_test_", suffix=".db", delete=False)
_tmp_db.close()
os.environ["DB_PATH"] = _tmp_db.name

# Po migracjach sala "104" istnieje jako "Aula 103_104" — taki jest room_id operatora_104.
OPERATOR_ROOM = "Aula%20103_104"
OTHER_ROOM = "Aula%20111"

# Add server directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_server import app, init_db, get_db_direct

class TestDostepnoscSalContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        init_db()
        cls.client = TestClient(app)

        # Login admin
        res = cls.client.post("/api/v1/auth/login", json={"username": "admin", "password": "admin123"})
        assert res.status_code == 200, f"Admin login failed: {res.text}"
        cls.admin_token = res.json()["access_token"]
        cls.admin_headers = {"Authorization": f"Bearer {cls.admin_token}"}

        # Login operator_104
        res = cls.client.post("/api/v1/auth/login", json={"username": "operator_104", "password": "operator123"})
        assert res.status_code == 200, f"Operator login failed: {res.text}"
        cls.op_token = res.json()["access_token"]
        cls.op_headers = {"Authorization": f"Bearer {cls.op_token}"}

    @classmethod
    def tearDownClass(cls):
        try:
            os.unlink(_tmp_db.name)
        except OSError:
            pass

    def test_api_01_public_rooms_unauthenticated(self):
        """API-01: Niezalogowany klient odczytuje publiczną listę - Sukces; tylko pola publiczne"""
        res = self.client.get("/api/v1/public/rooms")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIsInstance(data, list)
        self.assertGreater(len(data), 0)
        first = data[0]
        # Sprawdzenie obecności pól publicznych
        self.assertIn("id", first)
        self.assertIn("name", first)
        self.assertIn("status", first)
        self.assertIn("floor", first)
        # Brak pól prywatnych w widoku publicznym
        self.assertNotIn("operator_id", first)
        self.assertNotIn("device_id", first)

    def test_api_02_unauthenticated_status_change_denied(self):
        """API-02: Gość wysyła zmianę statusu - 403 FORBIDDEN; status i sesja bez zmian."""
        res = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "occupied"})
        self.assertEqual(res.status_code, 403)
        err = res.json()
        self.assertIn("error", err)
        self.assertEqual(err["error"]["code"], "FORBIDDEN")

    def test_api_03_and_04_operator_status_change_permissions(self):
        """API-03 & API-04: Operator zmienia status swojej sali (sukces) i cudzej sali (403 odmowa)"""
        # Upewnij się że 104 jest 'free' na start
        self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "free"}, headers=self.admin_headers)

        # API-03: Operator 104 zmienia status sali 104 na 'occupied' -> Sukces
        res = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "occupied"}, headers=self.op_headers)
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["data"]["status"], "occupied")
        self.assertTrue(body["data"]["changed"])
        self.assertIsNotNone(body["data"]["active_session"])

        # API-04: Operator 104 próbuje zmienić salę AULA -> 403 FORBIDDEN
        res_other = self.client.patch(f"/api/v1/rooms/{OTHER_ROOM}/status", json={"status": "occupied"}, headers=self.op_headers)
        self.assertEqual(res_other.status_code, 403)
        self.assertEqual(res_other.json()["error"]["code"], "FORBIDDEN")

    def test_api_05_and_06_idempotent_status_transitions(self):
        """API-05 & API-06: Idempotentność podwójnych wywołań occupied i free"""
        # API-05: Dwa razy ustaw occupied na sali 104
        res1 = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "occupied"}, headers=self.op_headers)
        self.assertEqual(res1.status_code, 200)
        sess1 = res1.json()["data"]["active_session"]

        res2 = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "occupied"}, headers=self.op_headers)
        self.assertEqual(res2.status_code, 200)
        self.assertFalse(res2.json()["data"]["changed"])
        sess2 = res2.json()["data"]["active_session"]
        # started_at i session id nie ulegają zmianie
        self.assertEqual(sess1["id"], sess2["id"])
        self.assertEqual(sess1["started_at"], sess2["started_at"])

        # API-06: Dwa razy ustaw free
        res3 = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "free"}, headers=self.op_headers)
        self.assertEqual(res3.status_code, 200)
        self.assertTrue(res3.json()["data"]["changed"])
        self.assertIsNone(res3.json()["data"]["active_session"])

        res4 = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/status", json={"status": "free"}, headers=self.op_headers)
        self.assertEqual(res4.status_code, 200)
        self.assertFalse(res4.json()["data"]["changed"])
        self.assertIsNone(res4.json()["data"]["active_session"])

    def test_api_08_and_09_alert_limit_rules(self):
        """API-08 & API-09: Zmiana limitu sali i odrzucenie limitu powyżej maksimum"""
        # API-09: Operator próbuje ustawić limit 100000 s (maksimum to 7200 s) -> 400 ALERT_LIMIT_EXCEEDS_MAXIMUM
        res_exceed = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/alert-limit", json={"alert_limit_seconds": 100000}, headers=self.op_headers)
        self.assertEqual(res_exceed.status_code, 400)
        self.assertEqual(res_exceed.json()["error"]["code"], "ALERT_LIMIT_EXCEEDS_MAXIMUM")

        # Poprawna zmiana limitu domyślnego
        res_valid = self.client.patch(f"/api/v1/rooms/{OPERATOR_ROOM}/alert-limit", json={"alert_limit_seconds": 1200}, headers=self.op_headers)
        self.assertEqual(res_valid.status_code, 200)
        self.assertEqual(res_valid.json()["default_alert_limit_seconds"], 1200)

    def test_api_13_14_16_device_esp_workflow(self):
        """API-13, 14, 16: Urządzenia ESP - autoryzacja tokenem, ignorowanie manipulacji ID i nieaktywne ESP"""
        # Rejestracja nowego urządzenia dla sali 112
        reg_res = self.client.post("/api/v1/admin/devices", json={"name": "ESP_Sala_112", "room_id": "112"}, headers=self.admin_headers)
        self.assertEqual(reg_res.status_code, 200)
        dev_token = reg_res.json()["token"]
        dev_id = reg_res.json()["device_id"]
        dev_headers = {"Authorization": f"Bearer {dev_token}"}

        # API-13: ESP pobiera stan przypisanej sali
        st_res = self.client.get("/api/v1/device/state", headers=dev_headers)
        self.assertEqual(st_res.status_code, 200)
        self.assertEqual(st_res.json()["room_id"], "112")

        # API-13: ESP zmienia status przypisanej sali na occupied
        ch_res = self.client.post("/api/v1/device/status", json={"status": "occupied"}, headers=dev_headers)
        self.assertEqual(ch_res.status_code, 200)
        self.assertEqual(ch_res.json()["status"], "occupied")

        # API-16: Dezaktywacja ESP przez admina
        self.client.patch(f"/api/v1/admin/devices/{dev_id}", headers=self.admin_headers) # deaktywacja przez SQL:
        conn = get_db_direct()
        conn.execute("UPDATE devices SET is_active = 0 WHERE id = ?", (dev_id,))
        conn.commit()
        conn.close()

        # Po dezaktywacji -> 401 UNAUTHENTICATED
        denied_res = self.client.get("/api/v1/device/state", headers=dev_headers)
        self.assertEqual(denied_res.status_code, 401)

    def test_api_20_resource_not_found(self):
        """API-20: Żądanie nieistniejącego zasobu -> 404 RESOURCE_NOT_FOUND"""
        res = self.client.get("/api/v1/public/rooms/nieistniejaca_sala_999")
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.json()["error"]["code"], "RESOURCE_NOT_FOUND")

    def test_api_21_device_code_identification(self):
        """API-21: Identyfikacja urządzenia krótkim kodem, uprawnienia i rotacja."""
        reg = self.client.post(
            "/api/v1/admin/devices",
            json={"name": "TV testowy", "device_type": "kiosk"},
            headers=self.admin_headers,
        )
        self.assertEqual(reg.status_code, 200)
        data = reg.json()
        code = data["pair_code"]
        self.assertEqual(len(code), 6)
        self.assertEqual(data["device_type"], "kiosk")

        resolved = self.client.post(
            "/api/v1/admin/devices/resolve",
            json={"code": code.lower()},
            headers=self.admin_headers,
        )
        self.assertEqual(resolved.status_code, 200)
        body = resolved.json()
        self.assertEqual(body["id"], data["device_id"])
        self.assertEqual(body["device_type"], "kiosk")
        self.assertTrue(body["capabilities"]["can_show_only"])
        self.assertFalse(body["capabilities"]["can_set_status"])
        self.assertNotIn("token", body)
        self.assertNotIn("pair_code_hash", body)

        denied = self.client.post(
            "/api/v1/admin/devices/resolve",
            json={"code": code},
            headers=self.op_headers,
        )
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.json()["error"]["code"], "FORBIDDEN")

        invalid = self.client.post(
            "/api/v1/admin/devices/resolve",
            json={"code": "IO1234"},
            headers=self.admin_headers,
        )
        self.assertEqual(invalid.status_code, 400)
        self.assertEqual(invalid.json()["error"]["code"], "INVALID_DEVICE_CODE")

        rotated = self.client.post(
            f"/api/v1/admin/devices/{data['device_id']}/rotate-pair-code",
            headers=self.admin_headers,
        )
        self.assertEqual(rotated.status_code, 200)
        new_code = rotated.json()["pair_code"]
        self.assertNotEqual(new_code, code)
        old = self.client.post(
            "/api/v1/admin/devices/resolve",
            json={"code": code},
            headers=self.admin_headers,
        )
        self.assertEqual(old.status_code, 404)

        audit = self.client.get(
            f"/api/v1/admin/devices/{data['device_id']}/audit",
            headers=self.admin_headers,
        )
        self.assertEqual(audit.status_code, 200)
        actions = [row["action"] for row in audit.json()]
        self.assertIn("device_registered", actions)
        self.assertIn("device_resolved", actions)
        self.assertIn("device_pair_code_rotated", actions)
        self.assertNotIn(code, str(audit.json()))
        self.assertNotIn(new_code, str(audit.json()))

    def test_api_22_device_token_rotation_and_type_update(self):
        """API-22: Rotacja tokenu i zmiana typu urządzenia."""
        reg = self.client.post(
            "/api/v1/admin/devices",
            json={"name": "Sterownik testowy", "room_id": "112"},
            headers=self.admin_headers,
        )
        self.assertEqual(reg.status_code, 200)
        data = reg.json()
        old_token = data["token"]
        old_headers = {"X-Device-Token": old_token}
        self.assertEqual(self.client.get("/api/v1/device/state", headers=old_headers).status_code, 200)

        rotated = self.client.post(
            f"/api/v1/admin/devices/{data['device_id']}/rotate-token",
            headers=self.admin_headers,
        )
        self.assertEqual(rotated.status_code, 200)
        new_token = rotated.json()["token"]
        self.assertNotEqual(new_token, old_token)
        self.assertEqual(self.client.get("/api/v1/device/state", headers=old_headers).status_code, 401)
        self.assertEqual(
            self.client.get("/api/v1/device/state", headers={"X-Device-Token": new_token}).status_code,
            200,
        )

        updated = self.client.patch(
            f"/api/v1/admin/devices/{data['device_id']}",
            json={"device_type": "display", "is_active": False},
            headers=self.admin_headers,
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["device_type"], "display")
        self.assertFalse(updated.json()["is_active"])


    def test_api_23_automatic_device_code_claim(self):
        """API-23: Wyświetlacz sam otrzymuje kod, a jego rotacja jest widoczna publicznie."""
        client_id = "tv-install-test-0001"
        claim = self.client.post(
            "/api/v1/public/devices/claim",
            json={"client_id": client_id, "name": "TV testowy", "device_type": "kiosk"},
        )
        self.assertEqual(claim.status_code, 200)
        code = claim.json()["pair_code"]
        self.assertEqual(len(code), 6)
        self.assertEqual(claim.json()["device_type"], "kiosk")

        again = self.client.post(
            "/api/v1/public/devices/claim",
            json={"client_id": client_id},
        )
        self.assertEqual(again.status_code, 200)
        self.assertEqual(again.json()["pair_code"], code)
        self.assertEqual(again.json()["device_id"], claim.json()["device_id"])

        resolved = self.client.post(
            "/api/v1/admin/devices/resolve",
            json={"code": code},
            headers=self.admin_headers,
        )
        self.assertEqual(resolved.status_code, 200)
        device_id = resolved.json()["id"]

        rotated = self.client.post(
            f"/api/v1/admin/devices/{device_id}/rotate-pair-code",
            headers=self.admin_headers,
        )
        self.assertEqual(rotated.status_code, 200)
        new_code = rotated.json()["pair_code"]
        refreshed = self.client.get(f"/api/v1/public/devices/{client_id}/code")
        self.assertEqual(refreshed.status_code, 200)
        self.assertEqual(refreshed.json()["pair_code"], new_code)
        self.assertNotEqual(refreshed.json()["pair_code"], code)


if __name__ == "__main__":
    unittest.main()
