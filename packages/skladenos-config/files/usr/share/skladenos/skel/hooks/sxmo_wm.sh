#!/bin/sh
# Обёртка над /usr/bin/sxmo_wm.sh (scripts/sxmo-setup, шаг 3e).
# Проблема Poco F1: после выключения дисплея ПЕРВАЯ команда включения (`output * dpms true` / `power on`) возвращает success,
# но панель остаётся выключенной (drm dpms Off, bl_power=4; в dmesg: edt_ft5x06 14-0038 «Unable to fetch data, error: -5»,
# geni_i2c «GPI transfer failed: -5»). Со второй попытки экран включается — отсюда «подсветка только со второго нажатия питания».
# В SXMO `sxmo_wm.sh dpms off` = ВКЛЮЧИТЬ экран (имена инвертированы). Повторяем включение, пока sway не покажет power: true.
REAL=/usr/bin/sxmo_wm.sh
"$REAL" "$@"
rc=$?
if [ "$1" = dpms ] && [ "$2" = off ] && command -v swaymsg >/dev/null 2>&1; then
	i=0
	while [ "$i" -lt "${DPMS_RETRIES:-5}" ]; do
		swaymsg -t get_outputs 2>/dev/null | grep -q '"power": false' || break
		sleep "${DPMS_RETRY_DELAY:-0.4}"
		swaymsg -- output '*' power on >/dev/null 2>&1
		i=$((i + 1))
	done
fi
exit $rc
