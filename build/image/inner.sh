#!/usr/bin/env bash
# Выполняется ВНУТРИ контейнера debian:stable-slim (--privileged, arm64); запускает build/image/build.sh build.
# /in/{rootfs.img,boot-src.img,debs/,scripts/} — вход (ro), /out — результат. Env: UUID VARIANT IMG_USER IMG_HOSTNAME SSH EXTRA_PKGS LABEL GIT_REV.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
say() { echo; echo "=== [$(date +%H:%M)] $*"; }

say "[1/8] инструменты (apt в контейнере)"
apt-get update -qq
apt-get install -y -qq --no-install-recommends zstd tar e2fsprogs android-sdk-libsparse-utils mkbootimg gzip python3-minimal ca-certificates util-linux file >/dev/null

W=/work; MNT=/mnt/src
mkdir -p $W $MNT

say "[2/8] rootfs.img (sparse) -> raw (~8 ГБ, ~1 мин)"
simg2img /in/rootfs.img /src.img
have=$(dumpe2fs -h /src.img 2>/dev/null | awk -F': *' '/^Filesystem UUID/{print $2}')
[ "$have" = "$UUID" ] || { echo "UUID rootfs $have != ожидаемый $UUID" >&2; exit 1; }
echo "UUID корня: $UUID, label: $(dumpe2fs -h /src.img 2>/dev/null | awk -F': *' '/^Filesystem volume name/{print $2}')"

say "[3/8] копия в $W (loop-mount ro, tar с xattrs/ACL, ~2-3 мин)"
if ! mount -o loop,ro /src.img $MNT 2>/dev/null; then
  # в Docker Desktop /dev/loop* может не быть
  for i in 0 1 2 3 4 5 6 7; do [ -b /dev/loop$i ] || mknod /dev/loop$i b 7 $i 2>/dev/null || true; done
  mount -o loop,ro /src.img $MNT
fi
tar --xattrs --acls --numeric-owner -C $MNT -cf - . | tar --xattrs --acls --numeric-owner -xpf - -C $W
umount $MNT; rm -f /src.img
echo "занято: $(du -sm --apparent-size $W | cut -f1) МБ"; cat $W/etc/os-release | sed -n 1,3p

say "[4/8] chroot: установка ядра, skladenos-*, зависимостей (нужна сеть; репозиторий Mobian иногда душит скорость)"
mkdir -p $W/tmp/skl-debs; cp /in/debs/*.deb $W/tmp/skl-debs/
cp /in/scripts/chroot-stage.sh $W/tmp/chroot-stage.sh
[ -L $W/etc/resolv.conf ] || [ -f $W/etc/resolv.conf ] && mv -T $W/etc/resolv.conf $W/etc/resolv.conf.skl-orig
cp /etc/resolv.conf $W/etc/resolv.conf
mount -t proc proc $W/proc; mount -t sysfs sys $W/sys; mount --rbind /dev $W/dev; mount --make-rslave $W/dev
cleanup() { umount -R $W/dev $W/sys $W/proc 2>/dev/null || true; }
trap cleanup EXIT
chroot $W env IMG_USER="$IMG_USER" IMG_HOSTNAME="$IMG_HOSTNAME" SSH="$SSH" EXTRA_PKGS="$EXTRA_PKGS" LABEL="$LABEL" GIT_REV="$GIT_REV" VARIANT="$VARIANT" /bin/bash /tmp/chroot-stage.sh
cleanup; trap - EXIT
rm -f $W/etc/resolv.conf; [ -e $W/etc/resolv.conf.skl-orig ] || [ -L $W/etc/resolv.conf.skl-orig ] && mv -T $W/etc/resolv.conf.skl-orig $W/etc/resolv.conf
rm -rf $W/tmp/skl-debs $W/tmp/chroot-stage.sh
KREL=$(cat $W/etc/skladenos-kernel-release)
cp $W/var/lib/skladenos-manifest.txt /out/MANIFEST.txt

say "[5/8] проверки содержимого rootfs"
fail=0
chk() { if eval "$2"; then echo "  ok:  $1"; else echo "  НЕТ: $1" >&2; fail=1; fi; }
chk "ядро $KREL: vmlinuz" "[ -s $W/boot/vmlinuz-$KREL ]"
chk "ядро $KREL: initrd" "[ -s $W/boot/initrd.img-$KREL ]"
chk "ядро $KREL: модули" "[ -d $W/lib/modules/$KREL ]"
chk "dtb beryllium-$VARIANT" "[ -s $W/usr/lib/linux-image-$KREL/qcom/sdm845-xiaomi-beryllium-$VARIANT.dtb ]"
chk "PD: в dtb узел qcom,pmi8998-tcpm (патч 0010)" "grep -aq 'qcom,pmi8998-tcpm' $W/usr/lib/linux-image-$KREL/qcom/sdm845-xiaomi-beryllium-$VARIANT.dtb"
chk "PD: модуль qcom_pmic_tcpm и зависимости tcpm, aux-hpd-bridge" "grep -E '^kernel/drivers/usb/typec/tcpm/qcom/qcom_pmic_tcpm\.ko(\.xz)?:' $W/lib/modules/$KREL/modules.dep | grep -q tcpm.ko && grep -q aux-hpd-bridge $W/lib/modules/$KREL/modules.dep"
chk "нет лишних ядер в /lib/modules" "[ \$(ls $W/lib/modules | wc -l) = 1 ]"
chk "skladenos-apply" "[ -x $W/usr/bin/skladenos-apply ]"
chk "профиль устройства SXMO" "[ -f $W/usr/bin/sxmo_deviceprofile_xiaomi,beryllium-$VARIANT.sh ]"
chk "маска rmtfs-dir" "[ \"\$(readlink $W/etc/systemd/system/rmtfs-dir.service)\" = /dev/null ]"
chk "adsp-start.service" "[ -f $W/usr/lib/systemd/system/adsp-start.service ]"
chk "обои и шрифт (skladenos-wallpapers, skladenos-fonts)" "grep -q \"^skladenos-wallpapers \" $W/var/lib/skladenos-manifest.txt && grep -q \"^skladenos-fonts \" $W/var/lib/skladenos-manifest.txt"
chk "мастер первой загрузки (skladenos-firstboot, python3-textual)" "grep -q \"^skladenos-firstboot \" $W/var/lib/skladenos-manifest.txt && grep -q \"^python3-textual \" $W/var/lib/skladenos-manifest.txt && [ -f $W/etc/sway/config.d/60-skladenos-firstboot.conf ] && [ ! -e $W/var/lib/skladenos/firstboot-done ]"
chk "sxmo-utils, jq, sudo, swaybg, network-manager" "for p in sxmo-utils jq sudo swaybg network-manager; do grep -q \"^\$p \" $W/var/lib/skladenos-manifest.txt || exit 1; done"
chk "sxmo.service включён" "[ -L $W/etc/systemd/system/graphical.target.wants/sxmo.service ] || ls $W/etc/systemd/system/*.wants/sxmo.service >/dev/null 2>&1"
chk "skladenos-apply.service включён" "ls $W/etc/systemd/system/*.wants/skladenos-apply.service >/dev/null 2>&1"
chk "пользователь $IMG_USER (uid 1000)" "grep -q '^$IMG_USER:[^:]*:1000:' $W/etc/passwd"
chk "пароль $IMG_USER задан" "awk -F: '\$1==\"$IMG_USER\"{exit !(\$2 ~ /^\\\$/)}' $W/etc/shadow"
chk "нет пользователя mobian (если IMG_USER другой)" "[ \"$IMG_USER\" = mobian ] || ! grep -q '^mobian:' $W/etc/passwd"
chk "имя хоста $IMG_HOSTNAME" "[ \"\$(cat $W/etc/hostname)\" = \"$IMG_HOSTNAME\" ] && grep -q \"^127.0.1.1[[:space:]]$IMG_HOSTNAME\" $W/etc/hosts"
chk "группа $IMG_USER, домашний каталог принадлежит $IMG_USER" "grep -q '^$IMG_USER:' $W/etc/group && [ -d $W/home/$IMG_USER ] && [ \"\$(stat -c %u:%g $W/home/$IMG_USER)\" = 1000:\$(awk -F: '\$1==\"$IMG_USER\"{print \$4}' $W/etc/passwd) ]"
chk "$IMG_USER в группах sudo, audio, video, dialout, netdev, clock" "for g in sudo audio video dialout netdev clock; do grep -q \"^\$g:.*[:,]$IMG_USER\(,\|\$\)\" $W/etc/group || exit 1; done"
chk "sudoers skladenos-config на группе (не на имени)" "grep -q '^%sudo ' $W/etc/sudoers.d/sxmo-rtcwake && ! grep -rq '^mobian ' $W/etc/sudoers.d"
chk "sshd: политика пароля только из локальных сетей" "[ -f $W/etc/ssh/sshd_config.d/10-skladenos.conf ] && [ ! -e $W/var/lib/skladenos/firstboot-done ]"
chk "skladenos-sshd-policy.path включён" "ls $W/etc/systemd/system/*.wants/skladenos-sshd-policy.path >/dev/null 2>&1"
chk "fstab: корень по UUID $UUID" "grep -q 'UUID=$UUID' $W/etc/fstab"
chk "fstab: x-systemd.growfs" "grep -q growfs $W/etc/fstab"
chk "machine-id сброшен" "[ ! -s $W/etc/machine-id ] || grep -q uninitialized $W/etc/machine-id"
chk "нет ssh host-ключей" "! ls $W/etc/ssh/ssh_host_* >/dev/null 2>&1"
chk "нет прошивок droid-juicer / status.json" "[ ! -e $W/var/lib/droid-juicer/status.json ]"
chk "hold ядра" "grep -q 'linux-image-7.2-sdm845' $W/var/lib/skladenos-holds.txt"
chk "hold sxmo-utils, sway, swaybg, foot" "for p in sxmo-utils sway swaybg foot; do grep -qx \"\$p\" $W/var/lib/skladenos-holds.txt || exit 1; done"
chk "apt-репозиторий skladenOS (ключ и источник garmon)" "[ -s $W/usr/share/keyrings/skladenos-archive-keyring.gpg ] && grep -q '^Suites: garmon' $W/etc/apt/sources.list.d/skladenos.sources && ! grep -q '^Enabled: no' $W/etc/apt/sources.list.d/skladenos.sources"
chk "fastfetch: конфиг и логотип skladenOS" "[ -x $W/usr/bin/fastfetch ] && [ -s $W/etc/xdg/fastfetch/config.jsonc ] && [ -s $W/usr/share/skladenos/fastfetch/logo.txt ]"
chk "хуки zz-qcom-bootimg вернули права на запуск (для обновлений ядра на телефоне)" "[ ! -e $W/etc/kernel/postinst.d/zz-qcom-bootimg ] || [ -x $W/etc/kernel/postinst.d/zz-qcom-bootimg ]"
[ $fail = 0 ] || { echo "проверки rootfs не прошли" >&2; exit 1; }

say "[6/8] boot.img (mkbootimg: ядро $KREL + dtb $VARIANT + initrd; cmdline из оригинала Mobian, с rw)"
T=/boot-tmp; mkdir -p $T; unpack_bootimg --boot_img /in/boot-src.img --out $T >/dev/null
CMD=$(unpack_bootimg --boot_img /in/boot-src.img --out $T | sed -n 's/^command line args: //p')
case "$CMD" in *"mobile.root=UUID=$UUID "*) ;; *) echo "cmdline не содержит UUID корня: $CMD" >&2; exit 1 ;; esac
case "$CMD" in *" rw "*) ;; *) echo "в cmdline оригинала нет rw: $CMD" >&2; exit 1 ;; esac
CMD=$(echo "$CMD" | sed "s/mobile\.variant=[a-z]*/mobile.variant=$VARIANT/")
MK() { mkbootimg --kernel "$1" --ramdisk "$2" --base 0x10000000 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 --pagesize 4096 --header_version 0 --cmdline "$3" -o "$4"; }
# проверка параметров: репак оригинала (без смены variant) должен совпасть побайтно
ORIGCMD=$(unpack_bootimg --boot_img /in/boot-src.img --out $T | sed -n 's/^command line args: //p')
MK $T/kernel $T/ramdisk "$ORIGCMD" $T/check.img
if cmp -s $T/check.img /in/boot-src.img; then echo "репак оригинала идентичен (параметры заголовка верны)"; else echo "ВНИМАНИЕ: репак оригинала не идентичен — параметры заголовка проверить (padding/version)" >&2; fi
V=$W/boot/vmlinuz-$KREL; D=$W/usr/lib/linux-image-$KREL/qcom/sdm845-xiaomi-beryllium-$VARIANT.dtb
file -L $V | grep -q -i 'gzip' || { echo "vmlinuz не gzip (Image.gz ожидался): $(file -L $V)" >&2; exit 1; }
cat $V $D > $T/kernel.new
MK $T/kernel.new $W/boot/initrd.img-$KREL "$CMD" /out/boot.img
ls -l /out/boot.img; [ $(stat -c %s /out/boot.img) -lt $((60*1024*1024)) ] || { echo "boot.img >60 МиБ — не влезет в раздел boot" >&2; exit 1; }
unpack_bootimg --boot_img /out/boot.img --out $T/v | sed -n 's/^command line args: /cmdline: /p'
case "$(unpack_bootimg --boot_img /out/boot.img --out $T/v)" in *" rw "*"$UUID"*|*"$UUID"*" rw "*) echo "ok: rw и UUID в cmdline" ;; *) echo "в итоговом boot.img нет rw/UUID" >&2; exit 1 ;; esac

say "[7/8] mke2fs -d (UUID $UUID), e2fsck"
used_mb=$(du -sm --apparent-size $W | cut -f1)
size_mb=$(( used_mb * 5 / 4 + 1024 )); [ $size_mb -lt 8192 ] && size_mb=8192
echo "занято ${used_mb} МБ, ФС ${size_mb} МБ (x-systemd.growfs растянет на раздел при первой загрузке)"
truncate -s ${size_mb}M /root.img
mke2fs -q -t ext4 -U "$UUID" -L rootfs -d $W /root.img
e2fsck -fn /root.img
dumpe2fs -h /root.img 2>/dev/null | grep -E 'Filesystem UUID|volume name|Block count|Free blocks'

say "[8/8] img2simg"
img2simg /root.img /out/userdata.simg
ls -la /out
