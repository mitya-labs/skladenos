#!/bin/sh
# Язык внешней клавиатуры (us,ru, CapsLock) в основном баре SXMO — только в альбомной ориентации (scripts/sxmo-setup, шаг 3k).
# sxmo_kbd_lang.sh         — обновить один раз (зовёт sxmo_hook_rotate.sh)
# sxmo_kbd_lang.sh watch   — слушать события ввода sway (раскладка, подключение/отключение клавиатуры)
# Признак альбомной ориентации — файл sxmo.notch.hidden (его создаёт sxmo_hook_rotate.sh).
MARK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sxmo.notch.hidden"
update() {
	# клавиатура с несколькими раскладками; кнопки телефона (одна раскладка) не считаем; $1 — устройство из события
	L=$(swaymsg -t get_inputs 2>/dev/null | jq -r --arg id "${1:-}" \
		'[.[] | select(.type == "keyboard" and ((.xkb_layout_names // []) | length) > 1)]
		 | (map(select(.identifier == $id)) + .) | .[0].xkb_active_layout_name // empty')
	if [ -e "$MARK" ] && [ -n "$L" ]; then
		case "$L" in
			English*) L=EN ;;
			Russian*) L=RU ;;
			*) L=$(printf '%s' "$L" | cut -c1-2 | tr '[:lower:]' '[:upper:]') ;;
		esac
		sxmo_status.sh add 98-kbdlang "$L"
	else
		sxmo_status.sh del 98-kbdlang 2>/dev/null
	fi
}
if [ "$1" = watch ]; then
	update
	swaymsg -m -t subscribe '["input"]' | jq --unbuffered -r '.input.identifier' | while read -r id; do update "$id"; done
else
	update
fi
