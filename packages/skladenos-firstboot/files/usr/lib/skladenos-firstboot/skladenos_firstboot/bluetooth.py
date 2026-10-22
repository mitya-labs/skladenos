"""Bluetooth через постоянный сеанс bluetoothctl (BlueZ): поиск, сопряжение, доверие, подключение.

Постоянный сеанс нужен из-за агента: старые клавиатуры требуют ввести PIN/passkey, который
bluetoothctl печатает в [agent]-строках, а разовые команды агента не держат.
"""
from __future__ import annotations

import os
import queue
import re
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Za-z0-9]")
PROMPT_PREFIX_RE = re.compile(r"^\[[^\]]*\][#>]\s*")
MAC_RE = r"(?P<mac>[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})"
KBD_NAME_RE = re.compile(r"keyboard|kbd|клав|keys|k380|k480|k780|mx keys", re.I)


@dataclass
class BtDevice:
    mac: str
    name: str = ""
    icon: str = ""
    paired: bool = False
    connected: bool = False
    trusted: bool = False

    @property
    def is_keyboard(self) -> bool:
        return self.icon == "input-keyboard" or bool(KBD_NAME_RE.search(self.name))

    @property
    def has_real_name(self) -> bool:
        # безымянные устройства BlueZ называет по MAC с дефисами
        return bool(self.name) and self.name.replace("-", ":").upper() != self.mac.upper()


@dataclass
class Event:
    kind: str
    mac: str = ""
    text: str = ""


def clean(line: str) -> str:
    line = ANSI_RE.sub("", line).replace("\r", "").replace("\x01", "").replace("\x02", "")
    return PROMPT_PREFIX_RE.sub("", line.strip("\n"))


def parse_line(line: str) -> Optional[Event]:
    """Одна строка вывода bluetoothctl -> Event или None."""
    s = clean(line).strip()
    if not s:
        return None
    m = re.match(r"\[NEW\] Device " + MAC_RE + r"\s*(?P<n>.*)$", s)
    if m:
        return Event("new", m["mac"].upper(), m["n"])
    m = re.match(r"\[DEL\] Device " + MAC_RE, s)
    if m:
        return Event("del", m["mac"].upper())
    m = re.match(r"\[CHG\] Device " + MAC_RE + r" (?P<k>[A-Za-z ]+): (?P<v>.*)$", s)
    if m:
        return Event("chg", m["mac"].upper(), m["k"].strip() + "=" + m["v"].strip())
    m = re.search(r"Confirm passkey (\d+)", s)
    if m:
        return Event("confirm", text=m[1])
    m = re.search(r"Request confirmation", s)
    if m:
        return Event("confirm_req")
    m = re.search(r"Authorize service|Authorize\b.*\(yes/no\)", s)
    if m:
        return Event("authorize")
    m = re.search(r"Enter (?:PIN code|passkey)\b", s, re.I)
    if m:
        return Event("pin_request")
    m = re.search(r"(?:\[agent\]\s*)?(?:Passkey|PIN code): (\d+)", s)
    if m:
        return Event("passkey", text=m[1])
    if "Pairing successful" in s:
        return Event("paired")
    m = re.search(r"Failed to pair: (.*)", s)
    if m:
        return Event("pair_failed", text=m[1])
    if "Connection successful" in s:
        return Event("connected")
    m = re.search(r"Failed to connect: (.*)", s)
    if m:
        return Event("connect_failed", text=m[1])
    m = re.match(r"Device " + MAC_RE + r"\b", s)
    if m:
        return Event("info_head", m["mac"].upper())
    m = re.match(r"(Icon|Paired|Trusted|Connected|Name|Alias): (.*)$", s)
    if m:
        return Event("info", text=m[1] + "=" + m[2])
    if "No default controller" in s or "no default controller" in s:
        return Event("no_controller")
    return None


class LineSplitter:
    """Режет поток на строки; незавершённый промпт ('... (yes/no): ') отдаёт как строку."""

    PARTIAL_RE = re.compile(r"\(yes/no\):?\s*$|Enter (?:PIN code|passkey)[^\n]*:\s*$", re.I)

    def __init__(self):
        self.buf = ""

    def feed(self, chunk: str) -> list[str]:
        self.buf += chunk
        parts = re.split(r"[\n\r]", self.buf)
        self.buf = parts.pop()
        out = [p for p in parts if p.strip()]
        if self.buf and self.PARTIAL_RE.search(clean(self.buf)):
            out.append(self.buf)
            self.buf = ""
        return out


class BluetoothBackend:
    """Интерфейс, общий для настоящего и демо-бэкенда."""

    def available(self) -> tuple[bool, str]: raise NotImplementedError
    def start_scan(self) -> None: raise NotImplementedError
    def devices(self) -> list[BtDevice]: raise NotImplementedError
    def pair(self, mac: str, on_event: Callable[[str, str], None], timeout: float = 90) -> tuple[bool, str]: raise NotImplementedError
    def stop(self) -> None: raise NotImplementedError


class BluetoothctlBackend(BluetoothBackend):
    def __init__(self, binary: Optional[str] = None):
        self.binary = binary or os.environ.get("SKLADENOS_BLUETOOTHCTL", "bluetoothctl")
        self.proc: Optional[subprocess.Popen] = None
        self._devs: dict[str, BtDevice] = {}
        self._lock = threading.Lock()
        self._events: "queue.Queue[Event]" = queue.Queue()
        self._info_mac = ""
        self._no_controller = False
        self._pairing = False

    # --- сеанс ---
    def _ensure(self) -> None:
        if self.proc and self.proc.poll() is None:
            return
        self.proc = subprocess.Popen([self.binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, bufsize=0)
        threading.Thread(target=self._reader, daemon=True).start()
        for cmd in ("power on", "agent KeyboardDisplay", "default-agent"):
            self._send(cmd)

    def _send(self, cmd: str) -> None:
        assert self.proc and self.proc.stdin
        try:
            self.proc.stdin.write((cmd + "\n").encode())
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def _reader(self) -> None:
        proc = self.proc
        sp = LineSplitter()
        assert proc and proc.stdout
        while True:
            chunk = os.read(proc.stdout.fileno(), 4096)
            if not chunk:
                return
            for line in sp.feed(chunk.decode("utf-8", "replace")):
                ev = parse_line(line)
                if ev:
                    self._handle(ev)

    def _handle(self, ev: Event) -> None:
        with self._lock:
            if ev.kind == "no_controller":
                self._no_controller = True
            elif ev.kind == "new":
                d = self._devs.setdefault(ev.mac, BtDevice(ev.mac))
                d.name = ev.text or d.name
            elif ev.kind == "del":
                self._devs.pop(ev.mac, None)
            elif ev.kind == "chg":
                d = self._devs.setdefault(ev.mac, BtDevice(ev.mac))
                self._apply(d, *ev.text.split("=", 1))
            elif ev.kind == "info_head":
                self._info_mac = ev.mac
                self._devs.setdefault(ev.mac, BtDevice(ev.mac))
            elif ev.kind == "info" and self._info_mac:
                self._apply(self._devs[self._info_mac], *ev.text.split("=", 1))
        self._events.put(ev)

    @staticmethod
    def _apply(d: BtDevice, key: str, val: str) -> None:
        yes = val.startswith("yes")
        if key in ("Name", "Alias") and val:
            d.name = val
        elif key == "Icon":
            d.icon = val
        elif key == "Paired":
            d.paired = yes
        elif key == "Trusted":
            d.trusted = yes
        elif key == "Connected":
            d.connected = yes

    # --- API ---
    def available(self) -> tuple[bool, str]:
        try:
            self._ensure()
        except FileNotFoundError:
            return False, "bluetoothctl не найден"
        time.sleep(0.8)
        if self._no_controller:
            return False, "Bluetooth-адаптер не найден"
        return True, ""

    def start_scan(self) -> None:
        self._ensure()
        self._send("scan on")
        self._send("devices")

    def devices(self) -> list[BtDevice]:
        with self._lock:
            devs = [d for d in self._devs.values() if d.has_real_name]
        for d in devs:
            if not d.icon and not self._pairing:
                self._send("info " + d.mac)
        return sorted(devs, key=lambda d: (not d.is_keyboard, not d.connected, d.name.lower()))

    def _drain(self) -> None:
        while not self._events.empty():
            self._events.get_nowait()

    def _wait(self, kinds: set[str], timeout: float, on_event) -> Optional[Event]:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                ev = self._events.get(timeout=0.2)
            except queue.Empty:
                continue
            if ev.kind == "confirm":
                on_event("passkey_confirm", ev.text)
                self._send("yes")
            elif ev.kind == "confirm_req":
                self._send("yes")
            elif ev.kind == "authorize":
                self._send("yes")
            elif ev.kind == "pin_request":
                on_event("pin_request", "0000")
                self._send("0000")
            elif ev.kind == "passkey":
                on_event("passkey", ev.text)
            if ev.kind in kinds:
                return ev
        return None

    def pair(self, mac, on_event, timeout=90):
        """Сопряжение + доверие + подключение. on_event(kind, text): 'passkey' (ввести на клавиатуре),
        'passkey_confirm', 'pin_request', 'status'. Возвращает (успех, сообщение)."""
        self._ensure()
        self._pairing = True
        try:
            self._send("scan off")
            self._drain()
            d = self._devs.get(mac)
            if not (d and d.paired):
                on_event("status", "Сопряжение...")
                self._send("pair " + mac)
                ev = self._wait({"paired", "pair_failed"}, timeout, on_event)
                if ev is None:
                    self._send("cancel-pairing")
                    return False, "Время ожидания сопряжения истекло"
                if ev.kind == "pair_failed" and "AlreadyExists" not in ev.text:
                    return False, "Не удалось сопрячь: " + ev.text
            self._send("trust " + mac)
            on_event("status", "Подключение...")
            self._drain()
            self._send("connect " + mac)
            ev = self._wait({"connected", "connect_failed"}, 30, on_event)
            if ev is None or ev.kind == "connect_failed":
                return False, "Не удалось подключить" + (": " + ev.text if ev else " (время вышло)")
            return True, "Подключено"
        finally:
            self._pairing = False

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self._send("scan off")
            self._send("quit")
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
