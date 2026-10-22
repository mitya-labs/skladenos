"""Точка входа: python3 -m skladenos_firstboot [--demo]. Коды выхода: 0 готово, 2 пропущено, 10 нужна перезагрузка."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="skladenos-firstboot")
    ap.add_argument("--demo", action="store_true", help="заглушки вместо Bluetooth/Wi-Fi/пользователя (без root)")
    args = ap.parse_args(argv)
    try:
        from .ui import Backends, FirstBootApp
    except ImportError as e:
        print("Не хватает python3-textual:", e, file=sys.stderr)
        return 1
    if args.demo:
        from .demo import DemoAccount, DemoBluetooth, DemoWifi
        from .osk import Osk
        os.environ.setdefault("SKLADENOS_STATE_DIR", tempfile.mkdtemp(prefix="skladenos-demo-"))
        be = Backends(DemoBluetooth(), DemoWifi(), DemoAccount(), Osk(enabled=False))
    else:
        from .account import SudoHelperBackend
        from .bluetooth import BluetoothctlBackend
        from .osk import Osk
        from .wifi import NmcliBackend
        be = Backends(BluetoothctlBackend(), NmcliBackend(), SudoHelperBackend(), Osk())
    rc = FirstBootApp(be).run() or 0
    if rc == 10 and not args.demo:
        if subprocess.run(["systemctl", "reboot"]).returncode != 0:
            subprocess.run(["sudo", "-n", "systemctl", "reboot"])
    return rc


if __name__ == "__main__":
    sys.exit(main())
