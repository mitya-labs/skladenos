#!/bin/sh
# SXMO deviceprofile для Xiaomi Poco F1 (beryllium-ebbg). Основа — апстрим postmarketOS (SXMO 1.18.1,
# sxmo_deviceprofile_xiaomi,beryllium[-ebbg].sh); идентификаторы — из `swaymsg -t get_inputs`.
# SXMO_DEVICE_NAME = первая compatible из /proc/device-tree/compatible: xiaomi,beryllium-ebbg
export SXMO_MONITOR="DSI-1"
export SXMO_POWER_BUTTON="0:0:pm8941_pwrkey"
export SXMO_VOLUME_BUTTON="1:1:gpio-keys 0:0:pm8941_resin"
export SXMO_SWAY_SCALE="3"
export SXMO_VIBRATE_DEV="/dev/input/by-path/platform-c440000.spmi-platform-c440000.spmi:pmic@3:haptics@c000-event"
# ниже — не из апстрима, нужны SXMO 1.12 из Mobian
export SXMO_TOUCHSCREEN_ID="0:0:generic_ft5x06_(d0)"
export SXMO_DISABLE_LEDS="1"
