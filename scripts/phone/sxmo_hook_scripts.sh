#!/bin/sh
# configversion: 68f36c53d0af94ac7d7b85616afad638
# Меню Scripts (Poco F1): как стандартное, но подпапки ~/.config/sxmo/userscripts/<папка>/ показываются подменю (STATE п.106).
# Файлы верхнего уровня — как обычно; папки — пункты `icon_dir имя` → sxmo_userscripts_folder.sh (имя папки без пробелов, «_» → пробел).

# shellcheck source=scripts/core/sxmo_common.sh
. sxmo_common.sh
# shellcheck source=configs/default_hooks/sxmo_hook_icons.sh
. sxmo_hook_icons.sh

write_line() {
	printf "%s ^ 0 ^ %s\n" "$1" "$2"
}

get_title() {
	title=""
	eval "$(head "$1" | grep '# title="[^\\"]*"' | sed 's/^# //g')"
	if [ -n "$title" ]; then
		echo "$title"
	else
		basename="$(basename "$1")"
		echo "$icon_itm $basename"
	fi
}

UD="$XDG_CONFIG_HOME/sxmo/userscripts"
if [ -f "$UD" ]; then
	cat "$UD"
elif [ -d "$UD" ]; then
	find "$UD" -mindepth 1 -maxdepth 1 -type d | sort -f | while read -r dir; do
		write_line "$icon_dir $(basename "$dir" | tr '_' ' ')" "$HOME/.local/bin/sxmo_userscripts_folder.sh $dir"
	done
	find "$UD" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) | sort -f | while read -r script; do
		title="$(get_title "$script")"
		write_line "$title" "$script"
	done
fi

write_line "$icon_cfg Edit Userscripts" "sxmo_terminal.sh $EDITOR $UD/*"

# System Scripts
find "$(xdg_data_path sxmo/appscripts)" -type f -o -type l | sort -f | while read -r script; do
	title="$(get_title "$script")"
	write_line "$title" "$script"
done
