#!/usr/bin/env bash
# Ядро skladenOS: Mobian qcom-linux (тег из build/kernel/UPSTREAM) + наши патчи → linux-image-7.2-sdm845_*.deb.
#   build/kernel/build.sh check   — клон тега + наложение патчей, без компиляции (~3 мин)
#   build/kernel/build.sh deb     — полная сборка пакета в Docker (десятки минут, ~10-15 ГБ диска); результат в out/kernel/
# Дерево ядра живёт в Docker-томе skladenos-ksrc (не в репо). Удалить: docker volume rm skladenos-ksrc
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-check}"; mkdir -p "$R/out/kernel"
docker build -q -t skladenos-kbuild "$R/build/kernel" >/dev/null
docker volume inspect skladenos-ksrc >/dev/null 2>&1 || docker volume create skladenos-ksrc >/dev/null
docker run --rm -v skladenos-ksrc:/src -v "$R/patches/pmi8998-typec":/patches:ro -v "$R/build/kernel":/kb:ro -v "$R/out/kernel":/out \
  skladenos-kbuild bash /kb/inner.sh "$MODE"
