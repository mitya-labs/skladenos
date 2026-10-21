#!/bin/sh
# Подменю папки из ~/.config/sxmo/userscripts: sxmo_userscripts_folder.sh <папка>. Вызывается из хука sxmo_hook_scripts.sh (STATE п.106).
# Заголовки пунктов — как в меню Scripts: строка `# title="..."` из первых строк скрипта, иначе имя файла.
. sxmo_common.sh
. sxmo_hook_icons.sh
DIR="$1"
[ -d "$DIR" ] || exit 1

get_title() {
	title=""
	eval "$(head "$1" | grep '# title="[^\\"]*"' | sed 's/^# //g')"
	if [ -n "$title" ]; then echo "$title"; else echo "$icon_itm $(basename "$1")"; fi
}

LIST="$(find "$DIR" -maxdepth 1 \( -type f -o -type l \) | sort -f | while read -r s; do
	printf '%s ^ %s\n' "$(get_title "$s")" "$s"
done)"
LIST="$LIST
$icon_cls Close Menu ^ quit"

PICKED="$(printf '%s\n' "$LIST" | awk -F' \\^ ' 'NF {print $1}' | sxmo_dmenu.sh -i -p "$(basename "$DIR" | tr '_' ' ')")" || exit 0
CMD="$(printf '%s\n' "$LIST" | awk -F' \\^ ' -v p="$PICKED" '$1 == p {print $2; exit}')"
[ -n "$CMD" ] && [ "$CMD" != quit ] && exec "$CMD"
exit 0
