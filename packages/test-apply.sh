#!/usr/bin/env bash
# Тест слоя B (skladenos-apply) на настоящем sxmo-utils (arm64) в Docker: установка пакета, применение, идемпотентность,
# защита пользовательских правок, --force, синтаксис хуков, sway --validate. Перед запуском: packages/build.sh skladenos-config.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
docker build -q -t skladenos-sxmotest "$R/build/sxmotest" >/dev/null
docker run --rm -v "$R/out/packages":/o skladenos-sxmotest bash -c '
  set -e; useradd -m -s /bin/sh -u 1000 skladen
  dpkg -i --force-depends /o/skladenos-wallpapers_*_all.deb /o/skladenos-fonts_*_all.deb /o/skladenos-config_*_all.deb >/dev/null 2>&1
  H=/home/skladen/.config/sxmo
  # без --user и SKLADENOS_USER берётся пользователь с uid 1000 (а не зашитое имя)
  [ "$(skladenos-apply --dry-run | grep -c "записано")" = 1 ] || { echo "FAIL: пользователь по умолчанию (uid 1000)"; exit 1; }
  # sudoers: группа, не имя; sshd: политика есть, снимается по флагу
  grep -q "^%sudo " /etc/sudoers.d/sxmo-rtcwake && ! grep -q "^mobian" /etc/sudoers.d/* || { echo "FAIL: sudoers"; exit 1; }
  [ -f /etc/ssh/sshd_config.d/10-skladenos.conf ] || { echo "FAIL: sshd drop-in"; exit 1; }
  /usr/lib/skladenos/sshd-policy; [ -f /etc/ssh/sshd_config.d/10-skladenos.conf ] || { echo "FAIL: sshd-policy без флага"; exit 1; }
  touch /var/lib/skladenos/firstboot-done; /usr/lib/skladenos/sshd-policy; [ ! -f /etc/ssh/sshd_config.d/10-skladenos.conf ] || { echo "FAIL: sshd-policy по флагу"; exit 1; }
  skladenos-apply --user skladen --force | grep -q "пропущено (изменено пользователем) 0" || { echo "FAIL: --force"; exit 1; }
  [ "$(skladenos-apply --user skladen | grep -c "записано 0,")" = 1 ] || { echo "FAIL: идемпотентность"; exit 1; }
  echo "# правка пользователя" >> $H/sway; skladenos-apply --user skladen | grep -q "пропущен: .*sway" || { echo "FAIL: защита правок"; exit 1; }
  skladenos-apply --user skladen --force >/dev/null
  for f in $H/hooks/*.sh $H/userscripts/* $H/userscripts/Питание/* /home/skladen/.local/bin/*; do [ -f "$f" ] && sh -n "$f"; done
  [ "$(sed -n 2p $H/hooks/sxmo_hook_icons.sh)" = "$(sed -n 2p /usr/share/sxmo/default_hooks/sxmo_hook_icons.sh)" ] || { echo "FAIL: configversion хука значков"; exit 1; }
  # глифы 4-байтные (U+F0xxx) не должны быть испорчены перекодировкой (UTF-8 прочитан как Latin-1)
  [ "$(sed -n "s/^icon_2fa=\"\(.*\)\".*/\1/p" $H/hooks/sxmo_hook_icons.sh | od -An -tx1 | tr -d " \n")" = "f3b0a6af0a" ] || { echo "FAIL: испорчена кодировка глифов в sxmo_hook_icons.sh"; exit 1; }
  grep -q "^icon_ena=" $H/hooks/sxmo_hook_icons.sh || { echo "FAIL: icon_ena"; exit 1; }
  # foot.ini: [colors] -> [colors-dark] без обнуления файла (иначе SXMO создаёт foot.ini.needs-migration); пустой хвост убирается
  F=/home/skladen/.config/foot/foot.ini
  [ -s $F ] && grep -q "^\[colors-dark\]" $F && grep -q "configversion" $F || { echo "FAIL: foot.ini пуст или без [colors-dark]"; exit 1; }
  touch $F.needs-migration; skladenos-apply --user skladen >/dev/null; [ ! -e $F.needs-migration ] || { echo "FAIL: пустой foot.ini.needs-migration не убран"; exit 1; }
  sed -i "s/^\[colors-dark\]/[colors]/" $F; skladenos-apply --user skladen >/dev/null; grep -q "^\[colors-dark\]" $F && [ -s $F ] || { echo "FAIL: foot [colors] не переименован"; exit 1; }
  grep -q "^export KEYBOARD_ARGS=" $H/profile || { echo "FAIL: KEYBOARD_ARGS"; exit 1; }
  export XDG_RUNTIME_DIR=/tmp/xdg HOME=/home/skladen WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
  mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; sway --validate -c $H/sway
  echo "OK: skladenos-apply (применение, значки, идемпотентность, защита правок, --force, sh -n, sway --validate)"'
