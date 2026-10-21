#!/bin/sh
# Тест PD (PLAN 4б.4): после `fastboot boot images/kernels/boot-7.2-pd.img` грузит tcpm + наш qcom_pmic_tcpm.ko
# и собирает состояние в /tmp/pd-test.txt. Запуск: sudo ~/pd/pd-load.sh [снимок]  (без аргумента — загрузка + снимок)
OUT=/tmp/pd-test.txt
D=$(dirname "$0")
snap() {
  echo "=== $(date +%T) $1"
  find /proc/device-tree -path '*typec@1300/compatible' -exec sh -c 'printf "%s: " "$1"; tr "\0" " " < "$1"; echo' _ {} \;
  for f in /sys/class/typec/port0/data_role /sys/class/typec/port0/power_role /sys/class/typec/port0/power_operation_mode \
           /sys/class/usb_role/*/role /sys/class/power_supply/pmi8998-charger/voltage_now /sys/class/power_supply/pmi8998-charger/current_now; do
    [ -e "$f" ] && echo "$f: $(cat $f)"
  done
  ls /sys/class/typec/ /sys/class/usb_power_delivery/ 2>&1
  grep -E 'type-c-change|sig-|msg-' /proc/interrupts
  echo "--- tcpm log"; for f in /sys/kernel/debug/usb/tcpm-*; do if [ -d "$f" ]; then ls "$f"; cat "$f"/* 2>&1 | tail -80; else cat "$f" | tail -80; fi; done
  ls /sys/class/typec/port0-partner/ 2>&1 | tr '\n' ' '; echo
  for f in /sys/class/usb_power_delivery/pd*/source-capabilities/*/* ; do [ -f "$f" ] && echo "$f: $(cat $f)"; done 2>/dev/null | head -40
  echo "--- dmesg"; dmesg | grep -i -E 'tcpm|typec|pdphy|pmic_typec|vbus' | grep -v 'dependency cycle' | tail -30
  echo "--- dmesg warn/oops"; dmesg | grep -n -E 'WARNING:|Oops|BUG:|Call trace|cut here' | head
  N=$(dmesg | grep -n -m1 -E 'cut here|WARNING:' | cut -d: -f1); [ -n "$N" ] && dmesg | sed -n "$((N)),$((N+45))p" | grep -v 'Modules linked in'
}
if [ "$1" = reload ]; then  # заменить модуль без перезагрузки: sudo ~/pd/pd-load.sh reload
  { rmmod qcom_pmic_tcpm && insmod "$D/qcom_pmic_tcpm.ko" && echo "reload ok"; sleep 3; } >> $OUT 2>&1
fi
if [ -z "$1" ]; then
  { lsmod | grep -E 'tcpm|typec'
    modprobe tcpm && modprobe aux-hpd-bridge && insmod "$D/qcom_pmic_tcpm.ko" && echo "insmod ok"
    sleep 3; } >> $OUT 2>&1
fi
snap "${1:-after-load}" >> $OUT 2>&1
chmod 644 $OUT; tail -40 $OUT
