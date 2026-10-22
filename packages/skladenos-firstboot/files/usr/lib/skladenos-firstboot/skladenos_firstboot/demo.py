"""Заглушки бэкендов для --demo (Mac, без железа) и тестов UI."""
from __future__ import annotations

import time

from .account import AccountBackend
from .bluetooth import BluetoothBackend, BtDevice
from .wifi import WifiBackend, WifiNet


class DemoBluetooth(BluetoothBackend):
    def __init__(self, delay: float = 0.6, fail_pair: bool = False, present: bool = True):
        self.delay, self.fail_pair, self.present = delay, fail_pair, present
        self.t0 = 0.0
        self.paired: set = set()

    def available(self):
        return (True, "") if self.present else (False, "Bluetooth-адаптер не найден")

    def start_scan(self):
        self.t0 = time.monotonic()

    def devices(self):
        d = [BtDevice("AA:BB:CC:00:00:01", "Телевизор", "video-display"),
             BtDevice("AA:BB:CC:00:00:02", "Logitech K380 Keyboard", "input-keyboard"),
             BtDevice("AA:BB:CC:00:00:03", "Наушники", "audio-headset")]
        n = 1 if time.monotonic() - self.t0 < self.delay else 3
        return d[:n][::-1] if n == 3 else d[:n]

    def pair(self, mac, on_event, timeout=90):
        on_event("status", "Сопряжение...")
        time.sleep(self.delay)
        on_event("passkey", "123456")
        time.sleep(self.delay)
        if self.fail_pair:
            return False, "Не удалось сопрячь: AuthenticationFailed"
        self.paired.add(mac)
        return True, "Подключено"

    def stop(self):
        pass


class DemoWifi(WifiBackend):
    def __init__(self, delay: float = 0.5, good_password: str = "password"):
        self.delay, self.good, self.cur = delay, good_password, None

    def available(self):
        return True, ""

    def scan(self):
        time.sleep(self.delay)
        return [WifiNet("Home-5G", 82, "WPA2"), WifiNet("Кафе", 55, ""), WifiNet("Neighbour", 30, "WPA2 WPA3")]

    def connect(self, ssid, password=""):
        time.sleep(self.delay)
        if ssid == "Кафе" or password == self.good:
            self.cur = ssid
            return True, "Подключено, интернет есть"
        return False, "Неверный пароль или не удалось пройти проверку"

    def current(self):
        return self.cur

    def connectivity(self):
        return "full" if self.cur else "none"


class DemoAccount(AccountBackend):
    def __init__(self, rename_pending: bool = True):
        self.calls = []
        self.rename_pending = rename_pending

    def current_user(self):
        return "skladen"

    def taken_names(self):
        return ["root", "skladen", "daemon"]

    def apply(self, new_user, password):
        time.sleep(0.4)
        self.calls.append((new_user, password))
        return {"ok": True, "rename_pending": new_user != "skladen" and self.rename_pending}
