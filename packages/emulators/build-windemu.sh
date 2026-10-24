#!/usr/bin/env bash
# WindEmu (эмулятор Psion 5mx, Qt5, ветка pmos форка DmitriiTrifonov/WindEmu) → packages/skladenos-emu-psion/build/.
#   packages/emulators/build-windemu.sh               # ~5-10 мин в Docker (arm64); затем: packages/build.sh skladenos-emu-psion
# Переменные: WINDEMU_REF (pmos) — ветка/коммит форка; JOBS. Кэш: out/emulators/windemu (в git не попадает).
# Правки при сборке (STATE п.108, п.110), как в прежнем extras/emulators/phone/build-emulators-on-phone.sh:
#   GCC 16: в WindCore/arm710.h добавить <functional>/<utility>; кнопки-символы Psion: явные шрифты вместо цветных эмодзи.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
WINDEMU_REF="${WINDEMU_REF:-pmos}"; JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
W="$R/out/emulators"; mkdir -p "$W"
docker build -q -t skladenos-emubuild "$R/packages/emulators" >/dev/null
echo "[$(date +%H:%M)] WindEmu@$WINDEMU_REF, JOBS=$JOBS"
docker run --rm -v "$W":/work -e WINDEMU_REF="$WINDEMU_REF" -e JOBS="$JOBS" skladenos-emubuild bash -ec '
  cd /work
  [ -d windemu ] || git clone -q https://github.com/DmitriiTrifonov/WindEmu.git windemu
  cd windemu
  git fetch -q origin && git checkout -q -f "$WINDEMU_REF" && { git merge -q --ff-only "origin/$WINDEMU_REF" 2>/dev/null || true; }
  git clean -fdxq && git rev-parse HEAD > ../windemu.rev
  grep -q "<functional>" WindCore/arm710.h || sed -i "s|^#include <variant>|#include <variant>\n#include <functional>\n#include <utility>|" WindCore/arm710.h
  python3 - <<PY
p = "WindQt/pdascreenwindow.cpp"
s = open(p, encoding="utf-8").read()
if "setFamilies" not in s:
    old = "font.setPointSizeF(font.pointSizeF() * 1.6);"
    assert old in s
    s = s.replace(old, old + "\n\t\t\t\tfont.setFamilies({\"Symbola\", \"Noto Sans Symbols2\", \"DejaVu Sans\"});", 1)
    s = s.replace("\U0001F9EE", "\U0001F5A9").replace("\U0001F9E9", "⚙")
    open(p, "w", encoding="utf-8").write(s)
    print("патч символов применён")
PY
  qmake WindEmu.pro
  make -j"$JOBS" sub-WindCore
  make -j"$JOBS"
  strip WindQt/WindQt
  ls -la WindQt/WindQt
'
B="$R/packages/skladenos-emu-psion/build"; L="$B/usr/lib/skladenos/windemu"
rm -rf "$B"; mkdir -p "$L/WindQt" "$B/usr/share/doc/skladenos-emu-psion"
cp "$W/windemu/WindQt/WindQt" "$L/WindQt/WindQt"
cp "$W/windemu/run.sh" "$W/windemu/run-sway.sh" "$L/"; cp -a "$W/windemu/extras" "$L/extras"
cp "$W/windemu/LICENSE" "$B/usr/share/doc/skladenos-emu-psion/LICENSE.WindEmu"
printf 'WindEmu (форк DmitriiTrifonov, ветка %s) %s\n' "$WINDEMU_REF" "$(cat "$W/windemu.rev")" > "$B/usr/share/doc/skladenos-emu-psion/SOURCE"
echo "[$(date +%H:%M)] готово: $B; дальше: packages/build.sh skladenos-emu-psion"
