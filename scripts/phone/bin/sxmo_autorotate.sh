#!/bin/sh
# Автоповорот SXMO для Poco F1: штатный скрипт читает in_accel_*_raw из IIO, а у нас акселерометр идёт через SSC (STATE п.116–117).
# Берём ориентацию у iio-sensor-proxy (monitor-sensor -a) и зовём sxmo_rotate.sh. Ставится в /usr/local/bin (раньше /usr/bin в PATH).
# right-up (правый край вверху) → rotleft (transform 270), left-up → rotright (transform 90) (направление исправлено после первой проверки, STATE п.117).
. sxmo_common.sh 2>/dev/null

fifo="$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/autorotate.XXXXXX")"
mkfifo "$fifo" || exit 1
monitor-sensor -a > "$fifo" &
mpid=$!
trap 'kill "$mpid" 2>/dev/null; rm -f "$fifo"' EXIT INT TERM

while read -r line; do
	case "$line" in
		*"orientation changed: "*) ;;
		*) continue ;;
	esac
	case "${line##*: }" in
		normal)    sxmo_rotate.sh rotnormal ;;
		right-up)  sxmo_rotate.sh rotleft ;;
		left-up)   sxmo_rotate.sh rotright ;;
		bottom-up) sxmo_rotate.sh rotinvert ;;
	esac
done < "$fifo"
