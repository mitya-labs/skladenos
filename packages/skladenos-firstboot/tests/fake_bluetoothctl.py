#!/usr/bin/env python3
"""Имитация bluetoothctl для тестов: читает команды из stdin, печатает строки как BlueZ (с ANSI и промптом без \\n)."""
import os, sys, time

MAC = "AA:BB:CC:00:00:02"
MODE = os.environ.get("FAKE_BT_MODE", "passkey")  # passkey | confirm | fail | noctl


def out(s):
    sys.stdout.write(s)
    sys.stdout.flush()


if MODE == "noctl":
    out("No default controller available\n")
for line in sys.stdin:
    c = line.strip()
    if c == "scan on":
        out("Discovery started\n\x1b[0;92m[NEW]\x1b[0m Device %s Logitech K380 Keyboard\n" % MAC)
        out("[NEW] Device AA:BB:CC:00:00:03 AA-BB-CC-00-00-03\n[NEW] Device AA:BB:CC:00:00:04 Наушники\n")
    elif c.startswith("info "):
        mac = c.split()[1]
        icon = "input-keyboard" if mac == MAC else "audio-headset"
        nm = "Logitech K380 Keyboard" if mac == MAC else "Наушники"
        out("Device %s (public)\n\tName: " % mac + nm + "\n\tIcon: %s\n\tPaired: no\n" % icon)
    elif c.startswith("pair "):
        if MODE == "fail":
            out("Attempting to pair with %s\nFailed to pair: org.bluez.Error.AuthenticationFailed\n" % c.split()[1])
        elif MODE == "confirm":
            out("[agent] Confirm passkey 654321 (yes/no): ")
        else:
            out("Attempting to pair with %s\n[CHG] Device %s Connected: yes\n[agent] Passkey: 123456\n" % (MAC, MAC))
            time.sleep(0.2)
            out("[CHG] Device %s Paired: yes\nPairing successful\n" % MAC)
    elif c == "yes":
        out("[CHG] Device %s Paired: yes\nPairing successful\n" % MAC)
    elif c.startswith("trust "):
        out("[CHG] Device %s Trusted: yes\nChanging %s trust succeeded\n" % (MAC, MAC))
    elif c.startswith("connect "):
        out("Attempting to connect to %s\n[CHG] Device %s Connected: yes\nConnection successful\n" % (MAC, MAC))
    elif c == "quit":
        break
