#!/bin/bash
# Выполняется ВНУТРИ chroot (rootfs Mobian), запускается build/image/inner.sh. Env: SSH EXTRA_PKGS LABEL GIT_REV VARIANT.
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
HOLD="rmtfs tqftpserv qrtr-tools alsa-ucm-conf droid-juicer firmware-qcom-soc firmware-qcom-dsp qbootctl"
for p in $HOLD; do dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" || true; done

say "apt-get update"
apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 update

say "установка ядра, skladenos-*, зависимостей"
# никакого full-upgrade: только то, что нужно нашим пакетам (залоченное не обновится)
apt-get install -y -o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  "$KDEB" $D/skladenos-wallpapers_*.deb $D/skladenos-fonts_*.deb $D/skladenos-config_*.deb $D/skladenos-artwork_*.deb \
  sxmo-utils jq sudo swaybg network-manager python3 openssh-server $EXTRA_PKGS

say "удаление ядра 6.12 (в boot будет только 7.2)"
OLD=$(dpkg-query -W -f='${Package}\n' 'linux-image-6.*' 'linux-image-sdm845' 2>/dev/null | tr '\n' ' ' || true)
if [ -n "$OLD" ]; then apt-mark unhold $OLD >/dev/null 2>&1 || true; apt-get purge -y $OLD; fi
apt-get autoremove -y --purge || true
apt-mark hold "$KPKG"
[ -f /boot/initrd.img-$KREL ] || update-initramfs -c -k $KREL
ls -la /boot

say "пользователь mobian и пароль по умолчанию 1234"
if ! getent passwd mobian >/dev/null; then
  useradd -m -u 1000 -s /bin/bash -G sudo,audio,video,plugdev,dialout,input,netdev,clock mobian 2>/dev/null || useradd -m -u 1000 -s /bin/bash mobian
  echo 'mobian:1234' | chpasswd
  echo "ВНИМАНИЕ: пользователя mobian в образе не было — создан"
fi
awk -F: '$1=="mobian"{exit !($2 ~ /^\$/)}' /etc/shadow || { echo 'mobian:1234' | chpasswd; echo "пароль mobian не был задан — выставлен 1234"; }
getent group clock >/dev/null && usermod -aG clock mobian || true
/usr/bin/skladenos-apply --if-needed || echo "skladenos-apply в chroot не отработал (применится на первой загрузке)"
chown -R mobian:mobian /home/mobian 2>/dev/null || true

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
