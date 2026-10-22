#!/usr/bin/env bash
# Тест слоя B (skladenos-apply) на настоящем sxmo-utils (arm64) в Docker: установка пакета, применение, идемпотентность,
# защита пользовательских правок, --force, синтаксис хуков, sway --validate. Перед запуском: packages/build.sh skladenos-config.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
docker build -q -t skladenos-sxmotest "$R/build/sxmotest" >/dev/null
docker run --rm -v "$R/out/packages":/o skladenos-sxmotest bash -c '
  set -e; useradd -m -s /bin/sh mobian
  dpkg -i --force-depends /o/skladenos-wallpapers_*_all.deb /o/skladenos-fonts_*_all.deb /o/skladenos-config_*_all.deb >/dev/null 2>&1
  H=/home/mobian/.config/sxmo
  skladenos-apply --user mobian --force | grep -q "пропущено (изменено пользователем) 0" || { echo "FAIL: --force"; exit 1; }
  [ "$(skladenos-apply --user mobian | grep -c "записано 0,")" = 1 ] || { echo "FAIL: идемпотентность"; exit 1; }
  echo "# правка пользователя" >> $H/sway; skladenos-apply --user mobian | grep -q "пропущен: .*sway" || { echo "FAIL: защита правок"; exit 1; }
  skladenos-apply --user mobian --force >/dev/null
  for f in $H/hooks/*.sh $H/userscripts/* $H/userscripts/Питание/* /home/mobian/.local/bin/*; do [ -f "$f" ] && sh -n "$f"; done
  [ "$(sed -n 2p $H/hooks/sxmo_hook_icons.sh)" = "$(sed -n 2p /usr/share/sxmo/default_hooks/sxmo_hook_icons.sh)" ] || { echo "FAIL: configversion хука значков"; exit 1; }
  # глифы 4-байтные (U+F0xxx) не должны быть испорчены перекодировкой (UTF-8 прочитан как Latin-1)
  [ "$(sed -n "s/^icon_2fa=\"\(.*\)\".*/\1/p" $H/hooks/sxmo_hook_icons.sh | od -An -tx1 | tr -d " \n")" = "f3b0a6af0a" ] || { echo "FAIL: испорчена кодировка глифов в sxmo_hook_icons.sh"; exit 1; }
  grep -q "^icon_ena=" $H/hooks/sxmo_hook_icons.sh || { echo "FAIL: icon_ena"; exit 1; }
  grep -q "^export KEYBOARD_ARGS=" $H/profile || { echo "FAIL: KEYBOARD_ARGS"; exit 1; }
  export XDG_RUNTIME_DIR=/tmp/xdg HOME=/home/mobian WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
  mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; sway --validate -c $H/sway
  echo "OK: skladenos-apply (применение, значки, идемпотентность, защита правок, --force, sh -n, sway --validate)"'
