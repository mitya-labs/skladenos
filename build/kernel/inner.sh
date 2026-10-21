#!/usr/bin/env bash
# Выполняется ВНУТРИ контейнера skladenos-kbuild (запускает build/kernel/build.sh).
#   /src — том с деревом ядра, /patches — patches/pmi8998-typec (ro), /kb — build/kernel (ro), /out — результат.
# $1 = check | deb:  check — клон тега + все патчи (Mobian + наши), без компиляции; deb — ещё и dpkg-buildpackage.
set -euo pipefail
MODE="${1:-check}"
. /kb/UPSTREAM
git config --global --add safe.directory /src
cd /src
if [ ! -d .git ]; then git init -q . && git remote add origin "$REPO"; fi
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then git fetch -q --depth=1 origin "tag" "$TAG"; fi
git checkout -q -f "tags/$TAG"; git clean -qfdx
echo "[1/4] серия Mobian ($(grep -vc '^#\|^$' debian/patches/series) патчей, $TAG)"
while read -r f; do
  case "$f" in ''|\#*) continue;; esac
  patch -p1 -s --no-backup-if-mismatch < "debian/patches/$f" || { echo "FAIL mobian $f"; exit 1; }
done < debian/patches/series
echo "[2/4] патчи skladenOS (taygoth v1 + beryllium + PD; 0006 правит только MAINTAINERS и не нужен)"
for p in $(ls /patches/*.diff | grep -v 0006) /patches/pd/*.diff; do
  echo "  apply $(basename "$p")"; patch -p1 -s --no-backup-if-mismatch -F3 < "$p" || { echo "FAIL $p"; exit 1; }
done
echo "[3/4] конфиг: TYPEC_QCOM_PMI8998=m (TCPM и QCOM_PMIC уже =m), DAMON_STAT по умолчанию выкл."
grep -q '^CONFIG_TYPEC_QCOM_PMI8998' debian/config/sdm845.config || echo 'CONFIG_TYPEC_QCOM_PMI8998=m' >> debian/config/sdm845.config
# DAMON_STAT по умолчанию включён в Mobian 7.2: kdamond ест 10-40% ядра (STATE п.138) — выключаем в конфиге вместо tmpfiles
grep -q 'DAMON_STAT_ENABLED_DEFAULT' debian/config/sdm845.config || echo '# CONFIG_DAMON_STAT_ENABLED_DEFAULT is not set' >> debian/config/sdm845.config
if [ "$MODE" = check ]; then echo "[4/4] check: патчи и конфиг применены, сборка пропущена"; exit 0; fi
echo "[4/4] dpkg-buildpackage -b (долго: полная сборка ядра и модулей)"
VER="$(sed -n '1s/.*(\(.*\)).*/\1/p' debian/changelog.in 2>/dev/null || true)"
dpkg-buildpackage -b -uc -us -d -j"$(nproc)" 2>&1 | tail -n 40
mkdir -p /out && cp -v ../linux-*.deb ../linux-*.buildinfo ../linux-*.changes /out/ 2>/dev/null || true
ls -la /out
