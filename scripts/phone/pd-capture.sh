#!/bin/sh
# Снимает свежий кусок лога TCPM (буфер переполняется и перестаёт писать) + dynamic debug qcom_pmic_tcpm.
# Запуск: ssh -t mobian@<phone-ip> 'sudo ~/pd/pd-capture.sh'  -> /tmp/pd-capture.txt
[ "$(id -u)" = 0 ] || { echo "нужен sudo"; exit 1; }
OUT=/tmp/pd-capture.txt; L=$(ls -d /sys/kernel/debug/usb/tcpm-*)/log
echo 'module qcom_pmic_tcpm +p' > /sys/kernel/debug/dynamic_debug/control
cat "$L" > /dev/null; dmesg -C; sleep 0.5
{ echo "=== tcpm"; cat "$L"; echo "=== dmesg"; dmesg; echo "=== regs"
  grep -E '^(130[b-e]|1368|174[0-9a-f]):' /sys/kernel/debug/regmap/0-02/registers | tr '\n' ' '; echo; } > $OUT 2>&1
echo 'module qcom_pmic_tcpm -p' > /sys/kernel/debug/dynamic_debug/control
chmod 644 $OUT; echo "Готово: $OUT ($(wc -l < $OUT) строк)"
