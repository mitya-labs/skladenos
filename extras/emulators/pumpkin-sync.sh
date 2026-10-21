#!/usr/bin/env bash
# PumpkinOS из рабочей копии на Маке (ветка pmOS с Wayland, 21 коммит и правки, которых нет на GitHub) → телефон, сборка в фоне. STATE п.109.
# Запуск с Мака при подключённом телефоне: extras/emulators/pumpkin-sync.sh   (источник: PUMPKIN_SRC, по умолчанию ~/Developer/pmOS/PumpkinOS)
#   1. nosleep; apt: libwayland-dev wayland-protocols libwayland-bin libxkbcommon-dev libdecor-0-dev (для libwwayland);
#   2. tar только файлов под git (с Вашими незакоммиченными правками; без bin/, pumpkin, логов) → scp на телефон (~30 МБ, ~1 мин);
#   3. старый ~/PumpkinOS (клон master) → ~/PumpkinOS.master; новая копия распаковывается в ~/PumpkinOS (там же ваш pumpkin_pmos.sh);
#   4. `make` в src БЕЗ -j в фоне (~10-20 мин): лог ~/logs/pumpkin-build.log, итог ~/logs/pumpkin-build.status (OK|FAIL).
# Следить: scripts/phone-ssh 'cat ~/logs/pumpkin-build.status; tail -3 ~/logs/pumpkin-build.log | cut -c1-150'
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"; P="$R/scripts/phone-ssh"
export PHONE_HOST="${PHONE_HOST:-10.66.0.1}" PHONE_PASS="${PHONE_PASS:-1234}"
SRC="${PUMPKIN_SRC:-$HOME/Developer/pmOS/PumpkinOS}"
[ -f "$SRC/pumpkin_pmos.sh" ] || { echo "нет $SRC/pumpkin_pmos.sh" >&2; exit 1; }
q() { "$P" "$@" | { grep -v assword || true; }; }
TGZ="$(mktemp -t pumpkin-pmos).tgz"
trap 'rm -f "$TGZ"' EXIT

echo "[1/4] [$(date +%H:%M), ~1-2 мин] nosleep + apt (Wayland-заголовки)"
q 'phone-nosleep on'
q 'echo '"$PHONE_PASS"' | sudo -S -p "" env DEBIAN_FRONTEND=noninteractive apt-get install -y libwayland-dev wayland-protocols libwayland-bin libxkbcommon-dev libdecor-0-dev 2>&1 | tail -2'

echo "[2/4] [$(date +%H:%M), ~1 мин] архив рабочей копии: $SRC ($(git -C "$SRC" branch --show-current), HEAD $(git -C "$SRC" rev-parse --short HEAD))"
(cd "$SRC" && git ls-files -z | tar --null -T - -czf "$TGZ")
ls -la "$TGZ" | awk '{print "архив:", $5, "байт"}'
/usr/bin/expect -f <(cat <<'EXP'
set timeout 600
spawn scp -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no [lindex $argv 0] mobian@[lindex $argv 1]:/home/mobian/pumpkin-pmos.tgz
expect {
  "assword:" { send "$env(PHONE_PASS)\r"; exp_continue }
  eof
}
EXP
) "$TGZ" "$PHONE_HOST" 2>&1 | tr -d '\r' | tail -1

echo "[3/4] распаковка в ~/PumpkinOS (старая копия → ~/PumpkinOS.master)"
q 'cd ~ && { [ -d PumpkinOS.master ] || { [ -d PumpkinOS ] && mv PumpkinOS PumpkinOS.master; }; }; rm -rf PumpkinOS && mkdir PumpkinOS && tar -xzf pumpkin-pmos.tgz -C PumpkinOS && rm -f pumpkin-pmos.tgz && chmod +x PumpkinOS/pumpkin_pmos.sh && ls PumpkinOS | head -5 && du -sh PumpkinOS | tail -1'

echo "[4/4] [$(date +%H:%M)] сборка в фоне (make без -j, ~10-20 мин)"
q 'mkdir -p ~/logs; rm -f ~/logs/pumpkin-build.status; (setsid nohup sh -c "cd ~/PumpkinOS/src && make && [ -x ~/PumpkinOS/pumpkin ] && echo OK > ~/logs/pumpkin-build.status || echo FAIL > ~/logs/pumpkin-build.status" > ~/logs/pumpkin-build.log 2>&1 &); sleep 15; tail -2 ~/logs/pumpkin-build.log | cut -c1-150'
echo
echo "Запущено. Готово, когда ~/logs/pumpkin-build.status = OK:"
echo "  scripts/phone-ssh 'cat ~/logs/pumpkin-build.status; tail -3 ~/logs/pumpkin-build.log | cut -c1-150'"
