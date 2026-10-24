#!/usr/bin/env bash
# Выкладывает публичный репозиторий (out/repo-public, собранный `repo/build.sh --public`) в рабочую копию сайта mitya-labs.github.io/apt.
# Ничего не коммитит и не пушит: после запуска смотрите `git -C <сайт> status` и делайте commit/push сами.
#   repo/publish.sh [путь_к_сайту]      # по умолчанию ~/Developer/os/mitya-labs.github.io
# Уходит только dists/, pool/ и открытый ключ (conf/ и db/ reprepro остаются у вас).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
SITE="${1:-$HOME/Developer/os/mitya-labs.github.io}"; SRC="$R/out/repo-public"
[ -d "$SITE/.git" ] || { echo "нет репозитория сайта: $SITE" >&2; exit 1; }
[ -f "$SRC/dists/garmon/InRelease" ] || { echo "нет $SRC/dists/garmon/InRelease: repo/build.sh --public" >&2; exit 1; }
if find "$SRC/pool" -name 'skladenos-emu-pumpkinos*' | grep -q .; then echo "в публичном репозитории PumpkinOS: так нельзя" >&2; exit 1; fi
mkdir -p "$SITE/apt"
rsync -a --delete "$SRC/dists" "$SRC/pool" "$SRC/skladenos-archive-keyring.gpg" "$SITE/apt/"
cp "$R/repo/index.html" "$SITE/apt/index.html"
echo "выложено в $SITE/apt:"; du -sh "$SITE/apt"; git -C "$SITE" status --short | head -20
echo "дальше: git -C $SITE add apt && git -C $SITE commit && git -C $SITE push (по вашему решению)"
