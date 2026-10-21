#!/bin/sh
# QEMU (SDL, Wayland) не растягивает картинку по размеру окна, пока не получит resize: в обычном (тайловом) окне sway она остаётся мелкой
# (~1/3 окна). «Пинок»: окно на ~0,3 с становится плавающим и возвращается — QEMU перерисовывается на весь размер. STATE п.111.
# sxmo_qemu_resize.sh          — сейчас (для уже открытого окна; вызывается из хука поворота экрана)
# sxmo_qemu_resize.sh --wait   — ждать появления окна qemu-system-arm (опрос 0,2 с, до 90 с), +0,5 с и пнуть (из пунктов меню Jornada)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SEL='[app_id="qemu-system-arm"]'
has_window() { swaymsg -t get_tree 2>/dev/null | grep -q '"app_id": "qemu-system-arm"'; }
if [ "$1" = "--wait" ]; then
	i=0
	while [ "$i" -lt 450 ] && ! has_window; do sleep 0.2; i=$((i + 1)); done
	sleep 0.5
fi
has_window || exit 0
swaymsg "$SEL floating enable" >/dev/null 2>&1
sleep 0.3
swaymsg "$SEL floating disable" >/dev/null 2>&1
