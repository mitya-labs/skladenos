#!/usr/bin/env bash
# PNG-иконки skladenOS из icon.svg (нужен ImageMagick) и раскладка в hicolor. Запуск после make-logo.py:
#   tools/make-icons.sh
# © 2026 Dmitrii Trifonov. All rights reserved.
set -euo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)/files/usr/share"
SVG="$D/skladenos/logo/icon.svg"
install -d "$D/icons/hicolor/scalable/apps"; cp "$SVG" "$D/icons/hicolor/scalable/apps/skladenos.svg"
for n in 64 128 512; do
  install -d "$D/icons/hicolor/${n}x${n}/apps"
  magick -background none -density 384 "$SVG" -resize "${n}x${n}" "$D/icons/hicolor/${n}x${n}/apps/skladenos.png"
done
echo "ok"; find "$D/icons" -type f | sed "s#$D/##" | sort
