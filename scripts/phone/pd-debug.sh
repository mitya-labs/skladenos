#!/bin/sh
# Отладка цикла Soft_Reset (STATE п.125): включает dynamic debug qcom_pmic_tcpm, ждёт подключения источника,
# пишет dmesg, лог TCPM, счётчики IRQ и регистры Type-C/PDPHY в /tmp/pd-debug.txt.
# Запуск: ssh -t mobian@mobian.local 'sudo ~/pd/pd-debug.sh'
[ "$(id -u)" = 0 ] || { echo "нужен sudo"; exit 1; }
OUT=/tmp/pd-debug.txt; R=/sys/kernel/debug/regmap/0-02/registers
regs() { grep -E '^(130[b-f]|135[89a]|136[78]|17(4[0-9a-f]|1[0-9]|80|81|82|83)):' $R | tr '\n' ' '; echo; }
irqs() { grep -E 'type-c-change|sig-|msg-' /proc/interrupts | awk '{print $NF"="$2}' | tr '\n' ' '; echo; }
echo 'module qcom_pmic_tcpm +p' > /sys/kernel/debug/dynamic_debug/control
echo ">>> Выньте кабель, подождите 3 с и нажмите Enter"; read a
dmesg -C
{ echo "=== $(date +%T) до подключения"; irqs; regs; } > $OUT
echo ">>> Воткните блок Steam Deck (напрямую) и нажмите Enter; дальше 15 с сбора"; read a
for i in 1 2 3; do sleep 5; { echo "=== $(date +%T) +$((i*5))с"; irqs; regs; } >> $OUT; done
{ echo "--- dmesg"; dmesg; echo "--- tcpm"; cat /sys/kernel/debug/usb/tcpm-*/log 2>/dev/null || cat /sys/kernel/debug/usb/tcpm-*/* ; } >> $OUT 2>&1
echo 'module qcom_pmic_tcpm -p' > /sys/kernel/debug/dynamic_debug/control
chmod 644 $OUT; echo "Готово: $OUT ($(wc -l < $OUT) строк)"
