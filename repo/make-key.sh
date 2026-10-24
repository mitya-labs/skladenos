#!/usr/bin/env bash
# Создаёт ключ подписи apt-репозитория skladenOS (один раз, на Маке). Секретный ключ остаётся в $SKLADENOS_GNUPGHOME
# (по умолчанию ~/.skladenos-repo-gnupg), в git и в образ не попадает; открытая часть — repo/skladenos-archive-keyring.gpg.
#   repo/make-key.sh                # спросит парольную фразу (рекомендуется), срок 5 лет
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="${SKLADENOS_GNUPGHOME:-$HOME/.skladenos-repo-gnupg}"
command -v gpg >/dev/null || { echo "нет gpg: brew install gnupg" >&2; exit 1; }
[ -d "$GNUPGHOME" ] && { echo "уже есть $GNUPGHOME — ключ создан" >&2; exit 1; }
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --quick-generate-key "skladenOS archive <53140442+DmitriiTrifonov@users.noreply.github.com>" ed25519 sign 5y
gpg --export > "$R/repo/skladenos-archive-keyring.gpg"
gpg --list-keys --keyid-format long
echo "Открытый ключ: repo/skladenos-archive-keyring.gpg (его кладёт в образ пакет skladenos-archive-keyring)."
echo "Резервную копию секретного ключа сделайте сами: gpg --export-secret-keys --armor > ... (хранить вне репозитория)."
