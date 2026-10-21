#!/usr/bin/env bash
# Эмуляторы из ваших репозиториев на телефон: зависимости, ROM, сборка в фоне (STATE п.105).
# Запускать на Маке с подключённым по USB телефоном: extras/emulators/build-emulators.sh
#   1. включает nosleep;
#   2. apt: Qt5 (для WindEmu) и libasound2-dev (для PumpkinOS) — ~2-3 мин, по Wi-Fi;
#   3. копирует ROM с Мака: ~/jorn720/jornada720.bin → qemu-jornada720/roms/, Psion 5mx → ~/roms/5mx_eng.bin;
#   4. заливает extras/emulators/phone/build-emulators-on-phone.sh и запускает его в фоне (QEMU + PumpkinOS + WindEmu, ~40-90 мин).
# Следить: scripts/phone-ssh 'cat ~/logs/emulators-build.status; tail -5 ~/logs/emulators-build.log'
# Переменные: PHONE_HOST (10.66.0.1), PHONE_PASS (1234), JORNADA_ROM, PSION_ROM, JOBS (4).
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
export PHONE_HOST="${PHONE_HOST:-10.66.0.1}" PHONE_PASS="${PHONE_PASS:-1234}"
P="$R/scripts/phone-ssh"
JORNADA_ROM="${JORNADA_ROM:-$HOME/jorn720/jornada720.bin}"
PSION_ROM="${PSION_ROM:-$HOME/Downloads/5mx_v1.05(260)_eng.bin}"

for f in "$JORNADA_ROM" "$PSION_ROM"; do [ -f "$f" ] || { echo "нет файла ROM: $f" >&2; exit 1; }; done

scp_put() { # локальный_файл удалённый_путь
  /usr/bin/expect -f <(cat <<'EXP'
set timeout 300
spawn scp -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no [lindex $argv 0] mobian@[lindex $argv 1]:[lindex $argv 2]
expect {
  "assword:" { send "$env(PHONE_PASS)\r"; exp_continue }
  eof
}
EXP
  ) "$1" "$PHONE_HOST" "$2" 2>&1 | tr -d '\r' | tail -2
}

echo "[1/4] [$(date +%H:%M)] nosleep"
"$P" 'phone-nosleep on' | { grep -v assword || true; }

echo "[2/4] [$(date +%H:%M), ~2-3 мин] apt: qtbase5-dev qt5-qmake libasound2-dev"
"$P" 'echo '"$PHONE_PASS"' | sudo -S -p "" env DEBIAN_FRONTEND=noninteractive apt-get install -y qtbase5-dev qt5-qmake libasound2-dev 2>&1 | tail -2' | { grep -v assword || true; }

echo "[3/4] [$(date +%H:%M), ~1 мин] ROM → телефон"
"$P" 'mkdir -p ~/Developer/qemu-jornada720/roms ~/roms' | { grep -v assword || true; }
scp_put "$JORNADA_ROM" /home/mobian/Developer/qemu-jornada720/roms/jornada720.bin
scp_put "$PSION_ROM" /home/mobian/roms/5mx_eng.bin
"$P" 'ls -la ~/Developer/qemu-jornada720/roms/jornada720.bin ~/roms/5mx_eng.bin' | { grep -v assword || true; }

echo "[4/4] [$(date +%H:%M)] сборка на телефоне в фоне (~40-90 мин)"
"$P" --put "$R/extras/emulators/phone/build-emulators-on-phone.sh" /home/mobian/build-emulators-on-phone.sh | { grep -v assword || true; }
"$P" 'chmod +x ~/build-emulators-on-phone.sh; (JOBS='"${JOBS:-4}"' setsid nohup ~/build-emulators-on-phone.sh >/dev/null 2>&1 &); sleep 20; tail -3 ~/logs/emulators-build.log' | { grep -v assword || true; }
echo
echo "Запущено. Следить: scripts/phone-ssh 'cat ~/logs/emulators-build.status; tail -5 ~/logs/emulators-build.log'"
echo "Готово, когда в status появится строка FINISHED."
