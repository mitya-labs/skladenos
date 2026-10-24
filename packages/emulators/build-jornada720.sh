#!/usr/bin/env bash
# QEMU с машиной HP Jornada 720 (форк DmitriiTrifonov/qemu-jornada720) → packages/skladenos-emu-jornada720/files/.
#   packages/emulators/build-jornada720.sh            # ~10-20 мин в Docker (arm64); затем: packages/build.sh skladenos-emu-jornada720
# Переменные: QEMU_TAG (v11.1.2) — база QEMU, на которую ложатся патчи; J720_REF (main) — ветка/коммит форка; JOBS.
# Кэш клонов и сборки: out/emulators/ (в git не попадает). Результат кладётся в files/ пакета (в .gitignore).
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
QEMU_TAG="${QEMU_TAG:-v11.1.2}"; J720_REF="${J720_REF:-main}"; JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
W="$R/out/emulators"; mkdir -p "$W"
docker build -q -t skladenos-emubuild "$R/packages/emulators" >/dev/null
echo "[$(date +%H:%M)] QEMU $QEMU_TAG + qemu-jornada720@$J720_REF, JOBS=$JOBS"
docker run --rm -v "$W":/work -e QEMU_TAG="$QEMU_TAG" -e J720_REF="$J720_REF" -e JOBS="$JOBS" skladenos-emubuild bash -ec '
  cd /work
  [ -d j720 ] || git clone -q https://github.com/DmitriiTrifonov/qemu-jornada720.git j720
  git -C j720 fetch -q origin && git -C j720 checkout -q "$J720_REF" && { git -C j720 merge -q --ff-only "origin/$J720_REF" 2>/dev/null || true; }
  git -C j720 rev-parse HEAD > j720.rev
  rm -rf qemu-src build dest
  git clone -q --depth 1 -b "$QEMU_TAG" https://gitlab.com/qemu-project/qemu.git qemu-src
  ln -s ../../../j720/src/hw/arm/jornada720.c qemu-src/hw/arm/jornada720.c
  cd qemu-src && for p in ../j720/patches/0*.patch; do git apply "$p" && echo "применён $(basename $p)"; done && cd ..
  mkdir build && cd build
  ../qemu-src/configure --target-list=arm-softmmu --enable-sdl --enable-slirp --disable-docs --disable-tools --disable-guest-agent \
      --prefix=/usr/lib/skladenos/jornada720 --without-default-features --enable-sdl --enable-slirp >/dev/null
  ninja -j"$JOBS" qemu-system-arm
  DESTDIR=/work/dest ninja install >/dev/null
  strip /work/dest/usr/lib/skladenos/jornada720/bin/qemu-system-arm
  ls -la /work/dest/usr/lib/skladenos/jornada720/bin /work/dest/usr/lib/skladenos/jornada720/share/qemu | head -20
'
# раскладка пакета: бинарник QEMU и данные из dest/, скрипты запуска из форка (с двумя правками путей)
B="$R/packages/skladenos-emu-jornada720/build"; L="$B/usr/lib/skladenos/jornada720"
rm -rf "$B"; mkdir -p "$B"; cp -a "$W/dest/." "$B/"
# от установки QEMU нужен только бинарник и keymaps: прошивки других машин (edk2, bios, dtb) ~320 МБ не нужны
rm -rf "$L/include" "$L/lib"
find "$L/share/qemu" -mindepth 1 -maxdepth 1 ! -name keymaps -exec rm -rf {} +
cp "$W"/j720/{run.sh,j720-cf.py,j720-save.py,j720-router.php,frogfind-setup.sh} "$L/"
python3 - "$L/run.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
for old, new in (("QEMU=./build/qemu-system-arm", "QEMU=./bin/qemu-system-arm"),
                 ("ROM=roms/jornada720.bin", 'ROM=${J720_ROM:-$HOME/roms/jornada720.bin}')):
    assert old in s, old
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
D="$B/usr/share/doc/skladenos-emu-jornada720"; mkdir -p "$D"
cp "$W/j720/LICENSE" "$D/LICENSE.qemu-jornada720"
printf 'qemu-jornada720 %s\nQEMU %s\n' "$(cat "$W/j720.rev")" "$QEMU_TAG" > "$D/SOURCE"
echo "[$(date +%H:%M)] готово: $B (ревизия форка $(cat "$W/j720.rev")); дальше: packages/build.sh skladenos-emu-jornada720"
