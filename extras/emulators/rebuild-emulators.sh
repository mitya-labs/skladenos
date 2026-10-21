#!/usr/bin/env bash
# Повторная сборка эмуляторов на телефоне (после extras/emulators/build-emulators.sh): заливает актуальный
# extras/emulators/phone/build-emulators-on-phone.sh и запускает в фоне. QEMU уже собран → ninja сразу «no work to do»;
# докомпилируются PumpkinOS (make без -j) и WindEmu (с исправлением arm710.h для GCC 16). ~5-15 мин.
# Следить: scripts/phone-ssh 'cat ~/logs/emulators-build.status; tail -5 ~/logs/emulators-build.log'
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"; P="$R/scripts/phone-ssh"
export PHONE_HOST="${PHONE_HOST:-10.66.0.1}" PHONE_PASS="${PHONE_PASS:-1234}"
q() { "$P" "$@" | { grep -v assword || true; }; }
echo "[$(date +%H:%M)] nosleep + заливка скрипта сборки"
q 'phone-nosleep on'
q --put "$R/extras/emulators/phone/build-emulators-on-phone.sh" /home/mobian/build-emulators-on-phone.sh
q 'chmod +x ~/build-emulators-on-phone.sh; (JOBS='"${JOBS:-4}"' setsid nohup ~/build-emulators-on-phone.sh >/dev/null 2>&1 &); sleep 15; tail -2 ~/logs/emulators-build.log | cut -c1-150'
echo "Запущено в фоне. Готово, когда в ~/logs/emulators-build.status появится FINISHED."
