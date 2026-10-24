#!/bin/bash
# Выполняется ВНУТРИ chroot (rootfs Mobian), запускается build/image/inner.sh. Env: IMG_USER SSH EXTRA_PKGS LABEL GIT_REV VARIANT.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
D=/tmp/skl-debs
say() { echo "--- chroot [$(date +%H:%M)] $*"; }

# службы в chroot не стартуем; хуки сборки boot-образа Mobian (zz-qcom-bootimg пишет в раздел boot телефона) на время отключаем:
# boot.img собирает inner.sh, а на телефоне хуки вернутся и будут работать при обновлениях ядра
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
HOOKS=$(ls /etc/kernel/*.d/zz-qcom-bootimg 2>/dev/null || true)
for h in $HOOKS; do chmod -x "$h"; done
trap 'for h in $HOOKS; do chmod +x "$h"; done; rm -f /usr/sbin/policy-rc.d' EXIT
echo "хуки bootimg: ${HOOKS:-нет}"

# initramfs-tools с MODULES=dep собрал бы initrd под железо Docker-VM, а не телефона
for c in /etc/initramfs-tools/initramfs.conf /etc/initramfs-tools/conf.d/*; do
  [ -f "$c" ] && grep -q '^MODULES=dep' "$c" && { echo "ВНИМАНИЕ: $c: MODULES=dep -> most (на время сборки)"; sed -i 's/^MODULES=dep/MODULES=most/' "$c"; }
done

KDEB=$(ls $D/linux-image-7.2-sdm845_*.deb); KPKG=linux-image-7.2-sdm845; KREL=7.2-sdm845
say "apt-mark hold версий (testing ломается апгрейдами; STATE п.13, scripts/mobian-postinstall)"
# ядро 6.12 уходит (заменяется нашим 7.2), поэтому в список не входит
# sxmo-utils, sway, swaybg и foot: патчи skladenos-apply рассчитаны на sxmo-utils 1.12, мастер и touch-nudge отлажены на sway 1.12 / foot 1.28;
# обновлять осознанно после packages/test-apply.sh (apt upgrade их не трогает)
HOLD="rmtfs tqftpserv qrtr-tools alsa-ucm-conf droid-juicer firmware-qcom-soc firmware-qcom-dsp qbootctl sxmo-utils sway swaybg foot"
for p in $HOLD; do dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" || true; done

say "пользователь $IMG_USER (uid 1000) и пароль по умолчанию 1234"
# делаем до установки пакетов: postinst skladenos-config и skladenos-apply берут uid 1000 и должны видеть уже новое имя.
# В rootfs Mobian пользователь mobian (uid 1000) — переименовываем, а не создаём заново: сохраняются группы, ключи, настройки Phosh/dconf.
GROUPS_WANT="sudo,audio,video,plugdev,dialout,input,netdev,clock"
OLDU=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -z "$OLDU" ]; then
  useradd -m -u 1000 -s /bin/bash "$IMG_USER"
  echo "ВНИМАНИЕ: пользователя с uid 1000 в образе не было — создан $IMG_USER"
elif [ "$OLDU" != "$IMG_USER" ]; then
  OLDG=$(getent group "$(id -g "$OLDU")" | cut -d: -f1)
  usermod -l "$IMG_USER" -d "/home/$IMG_USER" -m "$OLDU"
  # primary group: имя как у пользователя (usermod -l группу не трогает)
  [ "$OLDG" = "$OLDU" ] && groupmod -n "$IMG_USER" "$OLDG"
  # остатки старого имени в конфигах (не трогаем hostname и репозитории): sudoers, greetd, AccountsService, polkit/getty автологин
  for f in /etc/sudoers.d/*; do [ -f "$f" ] && sed -i "s/^$OLDU\\([[:space:]]\\)/$IMG_USER\\1/" "$f"; done
  for f in /etc/greetd/*.toml; do [ -f "$f" ] && sed -i "s/^\\(user[[:space:]]*=[[:space:]]*\\)\"$OLDU\"/\\1\"$IMG_USER\"/" "$f"; done
  sed -i "s/^$OLDU:/$IMG_USER:/" /etc/subuid /etc/subgid 2>/dev/null || true
  [ -f "/var/lib/AccountsService/users/$OLDU" ] && mv "/var/lib/AccountsService/users/$OLDU" "/var/lib/AccountsService/users/$IMG_USER"
  echo "переименован $OLDU -> $IMG_USER (группа $OLDG, домашний каталог /home/$IMG_USER)"
  echo "остатки '$OLDU' в /etc (для справки):"; grep -rIlw "$OLDU" /etc 2>/dev/null | grep -v -e '^/etc/\(hostname\|hosts\|apt/\|passwd-\|shadow-\|group-\|gshadow-\)' || true
fi
getent group clock >/dev/null || groupadd -r clock
for g in $(echo "$GROUPS_WANT" | tr , ' '); do getent group "$g" >/dev/null && usermod -aG "$g" "$IMG_USER" || true; done
echo "$IMG_USER:1234" | chpasswd
# имя хоста (в rootfs Mobian — mobian): /etc/hostname и 127.0.1.1 в /etc/hosts
IMG_HOSTNAME="${IMG_HOSTNAME:-$IMG_USER}"
OLDH=$(cat /etc/hostname 2>/dev/null || echo mobian)
echo "$IMG_HOSTNAME" > /etc/hostname
if grep -q "^127.0.1.1" /etc/hosts; then sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$IMG_HOSTNAME/" /etc/hosts; else printf '127.0.1.1\t%s\n' "$IMG_HOSTNAME" >> /etc/hosts; fi
sed -i "s/\b$OLDH\b/$IMG_HOSTNAME/g" /etc/hosts
echo "имя хоста: $OLDH -> $IMG_HOSTNAME"
mkdir -p /var/lib/skladenos

say "apt-get update"
apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 update

say "установка ядра, skladenos-*, зависимостей"
# никакого full-upgrade: только то, что нужно нашим пакетам (залоченное не обновится)
apt-get install -y -o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  "$KDEB" $D/skladenos-wallpapers_*.deb $D/skladenos-fonts_*.deb $D/skladenos-config_*.deb $D/skladenos-artwork_*.deb $D/skladenos-firstboot_*.deb $D/skladenos-archive-keyring_*.deb \
  sxmo-utils jq sudo swaybg network-manager python3 openssh-server $EXTRA_PKGS

say "удаление ядра 6.12 (в boot будет только 7.2)"
OLD=$(dpkg-query -W -f='${Package}\n' 'linux-image-6.*' 'linux-image-sdm845' 2>/dev/null | tr '\n' ' ' || true)
if [ -n "$OLD" ]; then apt-mark unhold $OLD >/dev/null 2>&1 || true; apt-get purge -y $OLD; fi
apt-get autoremove -y --purge || true
apt-mark hold "$KPKG"
[ -f /boot/initrd.img-$KREL ] || update-initramfs -c -k $KREL
ls -la /boot

/usr/bin/skladenos-apply --user "$IMG_USER" --if-needed || echo "skladenos-apply в chroot не отработал (применится на первой загрузке)"
chown -R "$IMG_USER:$IMG_USER" "/home/$IMG_USER" 2>/dev/null || true

say "первый запуск: службы"
systemctl enable skladenos-apply.service adsp-start.service 2>&1 | tail -2 || true
# SSH: ключи хоста генерируются на первой загрузке, у каждого образа свои
cat > /etc/systemd/system/skladenos-ssh-hostkeys.service <<'EOS'
[Unit]
Description=skladenOS: сгенерировать ssh host-ключи при первой загрузке
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key
Before=ssh.service sshd.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOS
systemctl enable skladenos-ssh-hostkeys.service
if [ "$SSH" = 1 ]; then systemctl enable ssh.service; else systemctl disable ssh.service 2>/dev/null || true; fi
# SXMO по умолчанию: postinst skladenos-config уже сделал; на всякий случай
systemctl enable sxmo.service 2>/dev/null || true

say "метка образа"
cat > /etc/skladenos-image-release <<EOS
SKLADENOS_IMAGE=$LABEL
SKLADENOS_GIT=$GIT_REV
SKLADENOS_KERNEL=$(dpkg-query -W -f='${Version}' $KPKG)
SKLADENOS_PANEL=$VARIANT
SKLADENOS_BASE=mobian-sdm845-phosh-20260927
EOS
echo "$KREL" > /etc/skladenos-kernel-release
dpkg-query -W -f='${Package} ${Version}\n' > /var/lib/skladenos-manifest.txt
apt-mark showhold > /var/lib/skladenos-holds.txt

say "чистка"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/cache/debconf/*-old /var/lib/dpkg/*-old
# машинный id — на первой загрузке (как в исходном образе Mobian)
: > /etc/machine-id; echo uninitialized > /etc/machine-id; rm -f /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
# droid-juicer должен отработать на телефоне: прошивки в образ не кладём
rm -f /var/lib/droid-juicer/status.json
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /var/log/journal/* /tmp/* /var/tmp/* /root/.bash_history /root/.cache /home/*/.bash_history 2>/dev/null || true
# скрытые остатки: файл manifest оставляем (нужен inner.sh, удалим там не будем — маленький)
sync
say "готово (chroot)"
