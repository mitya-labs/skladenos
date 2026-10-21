#!/usr/bin/env bash
# Сборка deb-пакета skladenOS в Docker (образ skladenos-kbuild: dpkg-dev, debhelper, fakeroot; см. build/kernel/Dockerfile).
#   packages/build.sh skladenos-config     → out/packages/skladenos-config_*_all.deb
# Проверка: dpkg-deb -c / -I на готовом пакете (в том же контейнере) и lintian, если он доступен.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; PKG="${1:?имя пакета из packages/}"
[ -d "$R/packages/$PKG/debian" ] || { echo "нет packages/$PKG/debian" >&2; exit 1; }
mkdir -p "$R/out/packages"
docker build -q -t skladenos-kbuild "$R/build/kernel" >/dev/null
docker run --rm -v "$R/packages/$PKG":/pkg:ro -v "$R/out/packages":/out skladenos-kbuild bash -c '
  set -e; cp -a /pkg /build && cd /build
  dpkg-buildpackage -b -uc -us >/tmp/build.log 2>&1 || { tail -40 /tmp/build.log; exit 1; }
  cp -v ../*.deb /out/
  for d in /out/'"$PKG"'_*.deb; do echo "== $d"; dpkg-deb -I "$d" | sed -n 1,14p; echo "-- содержимое:"; dpkg-deb -c "$d" | awk "{print \$1, \$6, \$7, \$8}"; done'
