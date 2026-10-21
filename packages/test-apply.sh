#!/usr/bin/env bash
# Тест слоя B (skladenos-apply) на настоящем sxmo-utils (arm64) в Docker: установка пакета, применение, идемпотентность,
# защита пользовательских правок, --force, синтаксис хуков, sway --validate. Перед запуском: packages/build.sh skladenos-config.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
docker build -q -t skladenos-sxmotest "$R/build/sxmotest" >/dev/null
docker run --rm -v "$R/out/packages":/o skladenos-sxmotest bash -c '
  set -e; useradd -m -s /bin/sh mobian
  dpkg -i --force-depends /o/skladenos-wallpapers_*_all.deb /o/skladenos-config_*_all.deb >/dev/null 2>&1
  H=/home/mobian/.config/sxmo
  skladenos-apply --user mobian --force | grep -q "пропущено (изменено пользователем) 0" || { echo "FAIL: --force"; exit 1; }
  [ "$(skladenos-apply --user mobian | grep -c "записано 0,")" = 1 ] || { echo "FAIL: идемпотентность"; exit 1; }
  echo "# правка пользователя" >> $H/sway; skladenos-apply --user mobian | grep -q "пропущен: .*sway" || { echo "FAIL: защита правок"; exit 1; }
  skladenos-apply --user mobian --force >/dev/null
  for f in $H/hooks/*.sh $H/userscripts/* $H/userscripts/Питание/* /home/mobian/.local/bin/*; do [ -f "$f" ] && sh -n "$f"; done
  grep -q "^export KEYBOARD_ARGS=" $H/profile || { echo "FAIL: KEYBOARD_ARGS"; exit 1; }
  export XDG_RUNTIME_DIR=/tmp/xdg HOME=/home/mobian WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
  mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; sway --validate -c $H/sway
  echo "OK: skladenos-apply (применение, идемпотентность, защита правок, --force, sh -n, sway --validate)"'
