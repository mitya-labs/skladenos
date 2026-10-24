#!/bin/sh
# configversion: @CONFIGVERSION@
# Poco F1: вырез и скруглённые углы при повороте (scripts/sxmo-setup).
# $1 = normal | right (transform 90: челка слева) | left (transform 270: челка справа) | invert (180: челка снизу)
NOTCH_H="${NOTCH_H:-28}"
MARK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sxmo.notch.hidden"
MAIN=$(swaymsg -t get_bar_config | jq -r '.[]' | grep -v '^notch$' | head -1)
reset_gaps() { for e in top right bottom left; do swaymsg gaps "$e" all set 0 >/dev/null; done; }
# runtime-команда `bar gaps` меняет конфиг, но swaybar не перерисовывается → пересоздаём поверхность (invisible → dock)
main_gaps() { swaymsg bar "$MAIN" gaps "$@" >/dev/null; swaymsg bar "$MAIN" mode invisible >/dev/null; sleep 1; swaymsg bar "$MAIN" mode dock >/dev/null; }
case "$1" in
	normal)
		rm -f "$MARK"
		swaymsg bar notch mode overlay >/dev/null
		main_gaps "$NOTCH_H" 0 0 0
		reset_gaps
		;;
	right|left|invert)
		: > "$MARK"
		swaymsg bar notch mode invisible >/dev/null
		# бар не заходит в зону челки: со стороны челки отступ NOTCH_H (right: слева, left: справа)
		case "$1" in right) main_gaps 0 12 0 "$NOTCH_H" ;; left) main_gaps 0 "$NOTCH_H" 0 12 ;; *) main_gaps 0 12 0 12 ;; esac
		reset_gaps
		case "$1" in
			right) swaymsg gaps left all set "$NOTCH_H" >/dev/null ;;
			left) swaymsg gaps right all set "$NOTCH_H" >/dev/null ;;
			invert) swaymsg gaps bottom all set "$NOTCH_H" >/dev/null ;;
		esac
		;;
esac
# Обои: портретные для normal/invert, ландшафтные для right/left (STATE п.104); swaybg перезапускаем юнитом sxmo-wallpaper (п.103)
case "$1" in right|left) O=landscape ;; *) O=portrait ;; esac
# фирменные обои (пакет skladenos-artwork), если установлен, иначе свободные (skladenos-wallpapers)
WP=/usr/share/skladenos/wallpaper-branded-$O.png; [ -f "$WP" ] || WP=/usr/share/skladenos/wallpaper-$O.png
if [ -f "$WP" ]; then
	systemctl --user stop sxmo-wallpaper 2>/dev/null
	systemd-run --user --collect --unit=sxmo-wallpaper -E WAYLAND_DISPLAY -E XDG_RUNTIME_DIR swaybg -o DSI-1 -i "$WP" -m fill >/dev/null 2>&1
fi
# QEMU (Jornada) после смены размера окна надо «пнуть», иначе картинка остаётся мелкой (STATE п.111)
QRESIZE="$(command -v sxmo_qemu_resize.sh 2>/dev/null || ls "$HOME/.local/bin/sxmo_qemu_resize.sh" 2>/dev/null)"
[ -n "$QRESIZE" ] && pgrep -x qemu-system-arm >/dev/null 2>&1 && "$QRESIZE" >/dev/null 2>&1 &
# часы-виджет читает метку ориентации при старте → перезапускаем
systemctl --user restart sxmo_desktop_widget >/dev/null 2>&1 &
sxmo_hook_statusbar.sh time >/dev/null 2>&1
sxmo_hook_statusbar.sh state >/dev/null 2>&1
sxmo_kbd_lang.sh >/dev/null 2>&1
