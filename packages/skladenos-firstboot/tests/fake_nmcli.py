#!/usr/bin/env python3
"""Имитация nmcli для тестов."""
import sys

a = sys.argv[1:]
if a[:3] == ["-t", "-f", "TYPE,STATE"]:
    print("ethernet:unavailable\nwifi:disconnected")
elif a[:2] == ["radio", "wifi"]:
    pass
elif "list" in a:
    print(" :Home-5G:82:WPA2\n*:Кафе:55:--\n :Home-5G:40:WPA2\n :Weird\\:Name:70:WPA2 WPA3\n ::10:WPA2")
elif a[:2] == ["-t", "networking"]:
    print("full")
elif "connect" in a:
    ssid = a[a.index("connect") + 1]
    pw = sys.stdin.readline().strip() if "--ask" in a else ""
    if ssid == "Home-5G" and pw != "goodpass":
        sys.stderr.write("Error: Connection activation failed: (7) Secrets were required, but not provided.\n")
        sys.exit(4)
    print("Device 'wlan0' successfully activated")
elif a[:2] == ["connection", "delete"]:
    pass
elif a[:3] == ["-t", "-f", "ACTIVE,SSID"]:
    print("no:Home-5G\nyes:Кафе")
