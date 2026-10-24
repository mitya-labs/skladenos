#!/usr/bin/env bash
# Собирает apt-репозиторий skladenOS из out/packages/*.deb → out/repo/ (reprepro в Docker, подпись ключом из repo/make-key.sh).
#   repo/build.sh                 # все .deb из out/packages/ (повторный запуск обновляет версии)
#   repo/build.sh --test-key      # подписать одноразовым ключом (только проверка репозитория, ключ в out/test-gnupg; НЕ для публикации)
#   repo/build.sh --serve [порт]  # после сборки отдать out/repo по http (по умолчанию 8000) для проверки с телефона
# non-free: пакеты Section: non-free (skladenos-artwork) и эмуляторы с несвободными частями; остальные — main.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$R/out/repo"; mkdir -p "$OUT"
TEST=0; SERVE=""
while [ $# -gt 0 ]; do case "$1" in --test-key) TEST=1 ;; --serve) SERVE="${2:-8000}"; [ $# -gt 1 ] && shift ;; esac; shift; done
if [ "$TEST" = 1 ]; then GH="$R/out/test-gnupg"; else GH="${SKLADENOS_GNUPGHOME:-$HOME/.skladenos-repo-gnupg}"; fi
mkdir -p "$GH"; chmod 700 "$GH"
docker build -q -t skladenos-repo "$R/repo" >/dev/null
docker run --rm $([ -t 0 ] && echo -it) -v "$R/repo/conf":/conf:ro -v "$R/out/packages":/debs:ro -v "$OUT":/out -v "$GH":/gnupg-src:ro -e TEST="$TEST" skladenos-repo bash -ec '
  # gpg-agent не умеет сокеты в каталоге, смонтированном с Мака: работаем с копией ключа внутри контейнера
  export GNUPGHOME=/tmp/gnupg; mkdir -p $GNUPGHOME && cp -a /gnupg-src/. $GNUPGHOME/ 2>/dev/null; chmod 700 $GNUPGHOME
  if [ "$TEST" = 1 ] && ! gpg --list-secret-keys 2>/dev/null | grep -q sec; then
    gpg --batch --passphrase "" --quick-generate-key "skladenOS TEST (не для публикации)" ed25519 sign 1d
  fi
  [ "$(gpg --list-secret-keys 2>/dev/null | grep -c sec)" -ge 1 ] || { echo "нет ключа подписи: repo/make-key.sh" >&2; exit 1; }
  mkdir -p /out/conf && cp /conf/* /out/conf/
  [ "$TEST" = 1 ] && sed -i /ask-passphrase/d /out/conf/options
  cd /out
  for d in /debs/*.deb; do
    sec=main; dpkg-deb -f "$d" Section | grep -q non-free && sec=non-free
    reprepro -b /out --component "$sec" includedeb skladenos "$d"
  done
  gpg --export > /out/skladenos-archive-keyring.gpg
  reprepro -b /out export
  ls -R /out/dists | head -30
'
echo "репозиторий: $OUT"
[ -n "$SERVE" ] && { echo "http://$(ipconfig getifaddr en0 2>/dev/null || echo localhost):$SERVE/  (Ctrl+C — остановить)"; cd "$OUT" && exec python3 -m http.server "$SERVE"; }
exit 0
