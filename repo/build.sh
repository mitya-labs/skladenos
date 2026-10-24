#!/usr/bin/env bash
# Собирает apt-репозиторий skladenOS из out/packages/*.deb → out/repo/ (reprepro в Docker, подпись ключом из repo/make-key.sh).
#   repo/build.sh                 # все .deb из out/packages/ (повторный запуск обновляет версии)
#   repo/build.sh --test-key      # подписать одноразовым ключом (только проверка репозитория, ключ в out/test-gnupg; НЕ для публикации)
#   repo/build.sh --serve [порт]  # после сборки отдать out/repo по http (по умолчанию 8000) для проверки с телефона
#   repo/build.sh --public        # публичный вариант → out/repo-public/: без skladenos-emu-pumpkinos (лицензия Palm SDK, STATE п.158); публикует repo/publish.sh
# non-free: пакеты Section: non-free (skladenos-artwork) и эмуляторы с несвободными частями; остальные — main.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
TEST=0; SERVE=""; PUBLIC=0
while [ $# -gt 0 ]; do case "$1" in --test-key) TEST=1 ;; --public) PUBLIC=1 ;; --serve) SERVE="${2:-8000}"; [ $# -gt 1 ] && shift ;; esac; shift; done
if [ "$PUBLIC" = 1 ]; then OUT="$R/out/repo-public"; else OUT="$R/out/repo"; fi; mkdir -p "$OUT"
if [ "$TEST" = 1 ]; then GH="$R/out/test-gnupg"; else GH="${SKLADENOS_GNUPGHOME:-$HOME/.skladenos-repo-gnupg}"; fi
mkdir -p "$GH"; chmod 700 "$GH"
docker build -q -t skladenos-repo "$R/repo" >/dev/null
docker run --rm $([ -t 0 ] && echo -it) -v "$R/repo/conf":/conf:ro -v "$R/out/packages":/debs:ro -v "$OUT":/out -v "$GH":/gnupg-src -e TEST="$TEST" -e PUBLIC="$PUBLIC" skladenos-repo bash -ec '
  # gpg-agent не умеет сокеты в каталоге, смонтированном с Мака: работаем с копией ключа внутри контейнера
  export GNUPGHOME=/tmp/gnupg; mkdir -p $GNUPGHOME && for f in pubring.kbx trustdb.gpg private-keys-v1.d openpgp-revocs.d; do [ -e /gnupg-src/$f ] && cp -a /gnupg-src/$f $GNUPGHOME/; done; chmod 700 $GNUPGHOME
  if [ "$TEST" = 1 ]; then
    # тестовый ключ одноразовый, но стабильный между сборками: секретная часть лежит в out/test-gnupg/secret.asc
    if [ -f /gnupg-src/secret.asc ]; then gpg --batch --import /gnupg-src/secret.asc 2>/dev/null
    else
      gpg --batch --passphrase "" --quick-generate-key "skladenOS TEST (не для публикации)" ed25519 sign 30d
      gpg --batch --export-secret-keys --armor > /gnupg-src/secret.asc
    fi
  fi
  [ "$(gpg --list-secret-keys 2>/dev/null | grep -c sec)" -ge 1 ] || { echo "нет ключа подписи: repo/make-key.sh" >&2; exit 1; }
  mkdir -p /out/conf && cp /conf/* /out/conf/
  [ "$TEST" = 1 ] && sed -i /ask-passphrase/d /out/conf/options
  cd /out
  for d in /debs/*.deb; do
    [ "$PUBLIC" = 1 ] && case "$(basename $d)" in skladenos-emu-pumpkinos_*) echo "пропускаю (не для публикации): $d"; continue ;; esac
    sec=main; dpkg-deb -f "$d" Section | grep -q non-free && sec=non-free
    reprepro -b /out --component "$sec" includedeb garmon "$d"
  done
  gpg --export > /out/skladenos-archive-keyring.gpg
  reprepro -b /out export
  ls -R /out/dists | head -30
'
echo "репозиторий: $OUT"
[ -n "$SERVE" ] && { echo "http://$(ipconfig getifaddr en0 2>/dev/null || echo localhost):$SERVE/  (Ctrl+C — остановить)"; cd "$OUT" && exec python3 -m http.server "$SERVE"; }
exit 0
