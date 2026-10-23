"""Wi-Fi через NetworkManager (nmcli)."""
from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from typing import Optional

from .i18n import t

@dataclass
class WifiNet:
    ssid: str
    signal: int = 0
    security: str = ""
    in_use: bool = False

    @property
    def secured(self) -> bool:
        return self.security not in ("", "--")


def split_terse(line: str) -> list[str]:
    """Разбор `nmcli -t`: разделитель ':', литеральные ':' и '\\' экранированы обратной косой."""
    out, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def parse_wifi_list(text: str) -> list[WifiNet]:
    """Вывод `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list`. Скрытые SSID пропускаются, дубли -> сильнейший."""
    best: dict[str, WifiNet] = {}
    for line in text.splitlines():
        f = split_terse(line)
        if len(f) < 4 or not f[1]:
            continue
        try:
            sig = int(f[2])
        except ValueError:
            sig = 0
        net = WifiNet(f[1], sig, f[3], f[0].strip() == "*")
        old = best.get(net.ssid)
        if old is None or net.in_use or (not old.in_use and net.signal > old.signal):
            best[net.ssid] = net
    return sorted(best.values(), key=lambda n: (not n.in_use, -n.signal, n.ssid.lower()))


def friendly_error(msg: str) -> str:
    low = msg.lower()
    if "secrets were required" in low or "password" in low or "802-1x" in low:
        return t("wifi.bad_pw")
    if "no network with ssid" in low:
        return t("wifi.not_found")
    if "timeout" in low or "timed out" in low:
        return t("wifi.timeout")
    if "not authorized" in low or "insufficient privileges" in low:
        return t("wifi.no_rights")
    return msg.strip().splitlines()[-1] if msg.strip() else t("wifi.failed")


class WifiBackend:
    def available(self) -> tuple[bool, str]: raise NotImplementedError
    def scan(self) -> list[WifiNet]: raise NotImplementedError
    def connect(self, ssid: str, password: str = "") -> tuple[bool, str]: raise NotImplementedError
    def current(self) -> Optional[str]: raise NotImplementedError
    def connectivity(self) -> str: raise NotImplementedError


class NmcliBackend(WifiBackend):
    def __init__(self, binary: Optional[str] = None):
        self.binary = binary or os.environ.get("SKLADENOS_NMCLI", "nmcli")

    def _run(self, args, input=None, timeout=60):
        try:
            p = subprocess.run([self.binary, *args], input=input, capture_output=True, text=True, timeout=timeout)
        except FileNotFoundError:
            return 127, t("wifi.no_nmcli")
        except subprocess.TimeoutExpired:
            return 124, "timeout"
        return p.returncode, (p.stdout + p.stderr)

    def available(self):
        rc, out = self._run(["-t", "-f", "TYPE,STATE", "device"], timeout=10)
        if rc != 0:
            return False, t("wifi.no_nm")
        if not any(l.startswith("wifi:") for l in out.splitlines()):
            return False, t("wifi.no_adapter")
        self._run(["radio", "wifi", "on"], timeout=10)
        return True, ""

    def scan(self):
        rc, out = self._run(["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"], timeout=30)
        return parse_wifi_list(out) if rc == 0 else []

    def connect(self, ssid, password=""):
        # пароль идёт через stdin (--ask), а не в argv, чтобы не светиться в ps
        args = ["--ask", "dev", "wifi", "connect", ssid] if password else ["dev", "wifi", "connect", ssid]
        rc, out = self._run(args, input=(password + "\n") if password else None, timeout=60)
        if rc != 0:
            # неудачный профиль не оставляем в NM
            self._run(["connection", "delete", "id", ssid], timeout=10)
            return False, friendly_error(out)
        conn = self.connectivity()
        if conn == "full":
            return True, t("wifi.ok_internet")
        if conn == "portal":
            return True, t("wifi.ok_portal")
        return True, t("wifi.ok_no_internet")

    def current(self):
        rc, out = self._run(["-t", "-f", "ACTIVE,SSID", "dev", "wifi"], timeout=10)
        for line in out.splitlines():
            f = split_terse(line)
            if len(f) >= 2 and f[0] == "yes" and f[1]:
                return f[1]
        return None

    def connectivity(self):
        rc, out = self._run(["-t", "networking", "connectivity", "check"], timeout=20)
        return out.strip().splitlines()[-1] if rc == 0 and out.strip() else "unknown"
