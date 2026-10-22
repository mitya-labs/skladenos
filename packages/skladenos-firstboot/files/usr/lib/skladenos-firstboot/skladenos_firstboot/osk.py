"""Экранная клавиатура SXMO (wvkbd) через sxmo_keyboard.sh; без KEYBOARD запускает wvkbd-mobintl сама."""
from __future__ import annotations

import os
import shutil
import subprocess
from typing import Optional


class Osk:
    def __init__(self, enabled: bool = True):
        self.enabled = enabled
        self.proc: Optional[subprocess.Popen] = None

    def _script(self, arg: str) -> int:
        return subprocess.run(["sxmo_keyboard.sh", arg], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=10).returncode

    def is_open(self) -> bool:
        if not self.enabled:
            return False
        try:
            if os.environ.get("KEYBOARD") and shutil.which("sxmo_keyboard.sh"):
                return self._script("isopen") == 0
        except Exception:  # noqa: BLE001
            pass
        return self.proc is not None and self.proc.poll() is None

    def show(self) -> None:
        if not self.enabled or self.is_open():
            return
        try:
            if os.environ.get("KEYBOARD") and shutil.which("sxmo_keyboard.sh"):
                self._script("open")
            else:
                args = os.environ.get("KEYBOARD_ARGS", "-l simple,cyrillic,special").split()
                self.proc = subprocess.Popen(["wvkbd-mobintl", *args])
        except Exception:  # noqa: BLE001
            pass

    def hide(self) -> None:
        if not self.enabled:
            return
        try:
            if self.proc is not None and self.proc.poll() is None:
                self.proc.terminate()
            if os.environ.get("KEYBOARD") and shutil.which("sxmo_keyboard.sh"):
                self._script("close")
        except Exception:  # noqa: BLE001
            pass

    def toggle(self) -> None:
        self.hide() if self.is_open() else self.show()
