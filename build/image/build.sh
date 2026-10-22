#!/usr/bin/env bash
# Сборка прошиваемого образа skladenOS: официальный rootfs Mobian + наши deb + наше ядро → boot.img и userdata.simg.zst.
#   build/image/build.sh check [метка]   — быстрая проверка предпосылок (секунды, ничего тяжёлого)
#   build/image/build.sh build [метка]   — полная сборка в Docker (--privileged, arm64): ~25-40 мин, ~25 ГБ диска в Docker-VM
# Метка по умолчанию — дата-время (YYYYMMDD-HHMM). Результат: out/image/<метка>/ в том же формате, что flash/ у scripts/snapshot-to-userdata:
#   boot.img (cmdline с `rw`), userdata.simg.zst, SHA256SUMS, FLASH.txt, MANIFEST.txt (пакеты), flash -> . (симлинк, чтобы
#   `scripts/snapshot-flash out/image/<метка>` работал без изменений: он ищет <каталог>/flash/).
# Прошивка (СТИРАЕТ телефон): scripts/snapshot-flash out/image/<метка>
# Переменные: VARIANT=ebbg|tianma (панель, по умолчанию ebbg), SSH=1|0 (включить sshd, по умолчанию 1; пароль mobian = 1234 как у Mobian),
#   EXTRA_PKGS="..." (доп. пакеты из репозиториев), FORCE=1 (не отказываться, если идёт сборка ядра), KEEP_WORK=1 (не удалять рабочие каталоги Docker — нет смысла, контейнер --rm).
# Что внутри (inner.sh → chroot-stage.sh): Mobian rootfs.img (sparse) → raw → копия в каталог → chroot: apt-mark hold версий, установка
#   ядра 7.2 + skladenos-* + зависимостей (sxmo-utils, jq, …) → чистка → mke2fs -d (UUID корня тот же, что в cmdline Mobian) → e2fsck → img2simg;
#   boot.img собирается mkbootimg: наше ядро (vmlinuz + dtb beryllium-<вариант>) + новый initrd + cmdline Mobian с `rw`.
# Не кладём в образ: прошивки Qualcomm (droid-juicer извлекает их сам на телефоне при первой загрузке), часовой пояс, личные ключи/сети.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-check}"; LABEL="${2:-$(date +%Y%m%d-%H%M)}"
VARIANT="${VARIANT:-ebbg}"; SSH="${SSH:-1}"; EXTRA_PKGS="${EXTRA_PKGS:-}"
case "$VARIANT" in ebbg|tianma) ;; *) echo "VARIANT: ebbg или tianma" >&2; exit 2 ;; esac

MOB="$R/images/mobian"; STAMP=mobian-sdm845-phosh-20260927
ROOTFS="$MOB/$STAMP.rootfs.img"
BOOT_SRC="$MOB/boot-beryllium-$VARIANT-rw.img"        # оригинал Mobian с rw (scripts/make-boot-rw): источник cmdline и параметров заголовка
IMG=debian:stable-slim                                   # тот же образ, что у scripts/snapshot-to-userdata

ok=1
bad() { echo "  НЕТ: $*" >&2; ok=0; }
good() { echo "  ok:  $*"; }

# версия из deb без dpkg-deb (на Маке его нет): control.tar.{xz,zst,gz} внутри ar-архива
deb_field() { # файл поле
  local m c
  for m in control.tar.xz control.tar.zst control.tar.gz; do
    c=$(ar p "$1" "$m" 2>/dev/null | tar -xOf - ./control 2>/dev/null) && [ -n "$c" ] && { printf '%s\n' "$c" | sed -n "s/^$2: //p" | head -1; return; }
  done
}
newest() { ls -1 "$@" 2>/dev/null | sort -V | tail -1; }

KDEB="$(newest "$R"/out/kernel/linux-image-7.2-sdm845_*.deb || true)"
PKGS=()
for p in skladenos-config skladenos-wallpapers skladenos-fonts skladenos-artwork; do
  d="$(newest "$R"/out/packages/${p}_*.deb || true)"; PKGS+=("$d")
done

check() {
  echo "== skladenOS image: проверка предпосылок ($(date +%H:%M))"
  [ -f "$ROOTFS" ] && good "rootfs: $(basename "$ROOTFS") ($(du -h "$ROOTFS" | cut -f1))" || bad "нет $ROOTFS (images -> ../poco-f1-mainline/images)"
  if [ -f "$ROOTFS" ]; then
    python3 - "$ROOTFS" "$BOOT_SRC" <<'E' || ok=0
import struct, sys, uuid, re
f = open(sys.argv[1], "rb"); h = f.read(28)
m, _, _, fh, ch, bs, tb, tc, _ = struct.unpack("<IHHHHIIII", h)
if m != 0xED26FF3A: print("  НЕТ: rootfs не Android sparse (magic %#x)" % m); sys.exit(1)
f.seek(fh); t, _, sz, tsz = struct.unpack("<HHII", f.read(12))
d = f.read(sz * bs); sb = d[1024:2048]
if sb[0x38:0x3a] != b"\x53\xef": print("  НЕТ: в первом чанке нет ext4 superblock"); sys.exit(1)
u = uuid.UUID(bytes=sb[0x68:0x78]); print("  ok:  rootfs sparse %d блоков по %d, ext4 UUID %s, label %s" % (tb, bs, u, sb[0x78:0x88].rstrip(b"\0").decode()))
try: b = open(sys.argv[2], "rb").read()
except OSError: print("  НЕТ: нет %s (scripts/make-boot-rw)" % sys.argv[2]); sys.exit(1)
mm = re.search(rb"mobile\.root=UUID=([0-9a-f-]+) ", b)
if not mm or mm.group(1).decode() != str(u): print("  НЕТ: UUID в cmdline boot (%s) != UUID rootfs" % (mm and mm.group(1))); sys.exit(1)
print("  ok:  UUID корня в cmdline оригинального boot совпадает; ' rw ' в нём: %s" % (b" rw quiet splash" in b))
if b" rw quiet splash" not in b: sys.exit(1)
E
  fi
  if [ -n "$KDEB" ]; then
    kv=$(deb_field "$KDEB" Version); good "ядро: $(basename "$KDEB") (Version $kv)"
    . "$R/build/kernel/UPSTREAM"; want="${TAG#mobian/sdm845-}"
    [ "$kv" = "$want" ] && good "версия ядра совпадает с build/kernel/UPSTREAM ($want)" || bad "ядро $kv != UPSTREAM $want (старый deb?)"
  else bad "нет out/kernel/linux-image-7.2-sdm845_*.deb (build/kernel/build.sh deb; сейчас может ещё собираться)"; fi
  for d in "${PKGS[@]}"; do
    if [ -n "$d" ]; then
      n=$(deb_field "$d" Package); src="$R/packages/$n"
      if [ -n "$(find "$src" -type f -newer "$d" 2>/dev/null | head -1)" ]; then bad "$(basename "$d") старше исходников packages/$n — пересобрать: packages/build.sh $n"
      else good "$(basename "$d") ($(deb_field "$d" Version))"; fi
    else bad "нет deb одного из skladenos-* в out/packages (packages/build.sh <имя>)"; fi
  done
  for f in inner.sh chroot-stage.sh; do [ -f "$R/build/image/$f" ] && good "$f" || bad "нет build/image/$f"; done
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    good "docker: $(docker --version | cut -d, -f1), архитектура VM: $(docker info --format '{{.Architecture}}')"
    docker image inspect "$IMG" >/dev/null 2>&1 && good "образ $IMG уже скачан" || echo "  инфо: $IMG будет скачан при сборке (~30 МБ)"
    run=$(docker ps --filter ancestor=skladenos-kbuild --format '{{.ID}} {{.Status}}')
    [ -z "$run" ] && good "сборка ядра в Docker сейчас не идёт" || echo "  ВНИМАНИЕ: идёт контейнер skladenos-kbuild ($run) — build откажется без FORCE=1"
  else bad "docker недоступен (демон не запущен?)"; fi
  command -v zstd >/dev/null && good "zstd на Маке" || bad "нет zstd (brew install zstd)"
  command -v shasum >/dev/null && good "shasum" || bad "нет shasum"
  avail=$(df -g "$R" | awk 'NR==2{print $4}'); [ "${avail:-0}" -ge 20 ] && good "свободно на Маке ${avail} ГБ (нужно ~15: simg 9 ГБ + zst 3 ГБ)" || bad "на Маке свободно ${avail} ГБ (<20)"
  echo "  метка: $LABEL, панель: $VARIANT, ssh: $SSH -> out/image/$LABEL/"
  [ "$ok" = 1 ] && echo "== предпосылки в порядке" || { echo "== ЕСТЬ ПРОБЛЕМЫ (см. НЕТ выше)" >&2; return 1; }
}

case "$MODE" in
check) check ;;
build)
  check
  if docker ps --filter ancestor=skladenos-kbuild -q | grep -q . && [ "${FORCE:-0}" != 1 ]; then
    echo "идёт сборка ядра (контейнер skladenos-kbuild): дождитесь или FORCE=1" >&2; exit 1; fi
  OUT="$R/out/image/$LABEL"; [ ! -e "$OUT" ] || { echo "$OUT уже существует" >&2; exit 1; }
  mkdir -p "$OUT" "$R/logs"; LOG="$R/logs/image-build-$LABEL.log"
  KV=$(deb_field "$KDEB" Version)
  # пакеты в одну папку (контейнер видит её ro)
  STAGE="$(mktemp -d "$R/out/.image-stage.XXXX")"; trap 'rm -rf "$STAGE"' EXIT
  mkdir -p "$STAGE/debs"; cp "$KDEB" "${PKGS[@]}" "$STAGE/debs/"
  UUID=$(python3 - "$ROOTFS" <<'E'
import struct,sys,uuid
f=open(sys.argv[1],"rb"); h=f.read(28); fh=struct.unpack("<IHHHHIIII",h)[3]; bs=struct.unpack("<IHHHHIIII",h)[5]
f.seek(fh); t,_,sz,tsz=struct.unpack("<HHII",f.read(12)); print(uuid.UUID(bytes=f.read(sz*bs)[1024+0x68:1024+0x78]))
E
)
  echo "[~25-40 мин, $(date +%H:%M) → ~$(date -v+40M +%H:%M)] Docker: simg2img, копия, chroot (apt), mke2fs -d, e2fsck, img2simg, boot.img. Лог: $LOG"
  docker run --rm --privileged --platform linux/arm64 \
    -v "$ROOTFS:/in/rootfs.img:ro" -v "$BOOT_SRC:/in/boot-src.img:ro" -v "$STAGE/debs:/in/debs:ro" \
    -v "$R/build/image:/in/scripts:ro" -v "$OUT:/out" \
    -e UUID="$UUID" -e VARIANT="$VARIANT" -e SSH="$SSH" -e EXTRA_PKGS="$EXTRA_PKGS" -e LABEL="$LABEL" \
    -e GIT_REV="$(git -C "$R" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    "$IMG" bash /in/scripts/inner.sh 2>&1 | tee "$LOG"
  [ -f "$OUT/userdata.simg" ] && [ -f "$OUT/boot.img" ] || { echo "Docker не выдал boot.img/userdata.simg" >&2; exit 1; }

  grep -a -q -E 'init=/sbin/init rw ' "$OUT/boot.img" || { echo "В boot.img НЕТ rw — не прошивать!" >&2; exit 1; }
  echo "[~3-5 мин, $(date +%H:%M)] sha256 и сжатие userdata.simg (zstd -10)"
  ( cd "$OUT" && shasum -a 256 boot.img userdata.simg > SHA256SUMS
    zstd -q -T0 -10 -f --rm userdata.simg -o userdata.simg.zst
    shasum -a 256 userdata.simg.zst >> SHA256SUMS; cat SHA256SUMS
    zstd -dc userdata.simg.zst | shasum -a 256 | awk '{print $1}' | grep -q "$(awk '$2=="userdata.simg"{print $1}' SHA256SUMS)" \
      && echo "распаковка .zst совпадает с sha256 userdata.simg" || { echo "sha256 распаковки не сошёлся" >&2; exit 1; }
    ln -sfn . flash )
  CMD=$(grep -a -o -E 'mobile\.root=[^[:cntrl:]]*' "$OUT/boot.img" | head -1)
  cat > "$OUT/FLASH.txt" <<EOT
skladenOS $LABEL: Mobian $STAMP + ядро $KV + skladenos-* (git $(git -C "$R" rev-parse --short HEAD 2>/dev/null)), панель $VARIANT, UUID корня $UUID
cmdline в boot: $CMD
Проще всего: scripts/snapshot-flash out/image/$LABEL  (распакует, сверит, прошьёт; спросит подтверждение; каталог flash -> . для совместимости)
Вручную (телефон в fastboot, Vol− + Power; НЕ пробрасывать в виртуалку; сотрёт userdata):
  zstd -d userdata.simg.zst                 # ~9 ГБ на диске
  shasum -a 256 -c SHA256SUMS
  fastboot flash boot boot.img
  fastboot erase userdata
  fastboot -S 100M flash userdata userdata.simg
  fastboot reboot
  rm userdata.simg
Первая загрузка: ~1-3 мин; droid-juicer извлечёт прошивки и один раз перезагрузит телефон; пользователь mobian, пароль 1234.
EOT
  echo "Готово ($(date +%H:%M)): $OUT"; du -sh "$OUT"/* | grep -v flash
  ;;
*) echo "режимы: check | build" >&2; exit 2 ;;
esac
