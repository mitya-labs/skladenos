#!/usr/bin/env bash
# PumpkinOS (Palm OS, ветка pmOS форка DmitriiTrifonov/PumpkinOS, Wayland) → packages/skladenos-emu-pumpkinos/build/.
#   packages/emulators/build-pumpkinos.sh             # ~10-25 мин в Docker (arm64); затем: packages/build.sh skladenos-emu-pumpkinos
# Переменные: PUMPKIN_REF (pmOS) — ветка/коммит форка. make БЕЗ -j: при -j4 libscriptlua линкуется раньше libpit (STATE п.105).
# Кэш: out/emulators/pumpkinos (в git не попадает). Дерево PumpkinOS запускается из своего каталога и пишет в него (vfs/, лог),
# поэтому в пакете оно лежит только для чтения, а лаунчер skladenos-pumpkinos копирует его в ~/.local/share/skladenos/pumpkinos.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
PUMPKIN_REF="${PUMPKIN_REF:-pmOS}"
W="$R/out/emulators"; mkdir -p "$W"
docker build -q -t skladenos-emubuild "$R/packages/emulators" >/dev/null
echo "[$(date +%H:%M)] PumpkinOS@$PUMPKIN_REF"
docker run --rm -v "$W":/work -e PUMPKIN_REF="$PUMPKIN_REF" skladenos-emubuild bash -ec '
  cd /work
  [ -d pumpkinos ] || git clone -q https://github.com/DmitriiTrifonov/PumpkinOS.git pumpkinos
  cd pumpkinos
  git fetch -q origin && git checkout -q -f "$PUMPKIN_REF" && { git merge -q --ff-only "origin/$PUMPKIN_REF" 2>/dev/null || true; }
  git clean -fdxq && git rev-parse HEAD > ../pumpkinos.rev
  ( cd src && make )
  ls -la pumpkin bin | head
'
B="$R/packages/skladenos-emu-pumpkinos/build"; L="$B/usr/lib/skladenos/pumpkinos"
rm -rf "$B"; mkdir -p "$L" "$B/usr/share/doc/skladenos-emu-pumpkinos"
( cd "$W/pumpkinos" && tar --exclude=./src --exclude=./.git --exclude=./screenshots --exclude=./docker --exclude=./lib32 -cf - . ) | tar -xf - -C "$L"
rm -f "$L"/pumpkin.bat "$L"/pumpkin32.bat "$L"/pumpkin.vbs "$L"/pumpkin.wine "$L"/pumpkin_rpi.sh
cp "$W/pumpkinos/LICENSE" "$B/usr/share/doc/skladenos-emu-pumpkinos/LICENSE.PumpkinOS"
printf 'PumpkinOS (форк DmitriiTrifonov, ветка %s) %s\n' "$PUMPKIN_REF" "$(cat "$W/pumpkinos.rev")" > "$B/usr/share/doc/skladenos-emu-pumpkinos/SOURCE"
du -sh "$L"
echo "[$(date +%H:%M)] готово: $B; дальше: packages/build.sh skladenos-emu-pumpkinos"
