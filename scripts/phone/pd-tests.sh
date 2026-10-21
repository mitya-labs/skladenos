#!/bin/sh
# Серия тестов PD (PLAN 4б.4) по шагам: подсказывает, что воткнуть, ждёт Enter, снимает снимок pd-load.sh.
# Модули уже должны быть загружены (sudo ~/pd/pd-load.sh). Запуск с Мака:
#   ssh -t mobian@mobian.local 'sudo ~/pd/pd-tests.sh'
# Всё пишется в /tmp/pd-test.txt. Шаг можно пропустить: ввести s и Enter.
D=$(dirname "$0")
[ "$(id -u)" = 0 ] || { echo "нужен sudo"; exit 1; }
[ -d /sys/class/typec/port0 ] || { echo "нет /sys/class/typec/port0 — сначала sudo ~/pd/pd-load.sh"; exit 1; }

short() {
  printf '   роль: %s | питание: %s | режим: %s | usb_role: %s | вход %s мВ, %s мА\n' \
    "$(cat /sys/class/typec/port0/data_role)" "$(cat /sys/class/typec/port0/power_role)" \
    "$(cat /sys/class/typec/port0/power_operation_mode 2>/dev/null)" "$(cat /sys/class/usb_role/*/role)" \
    "$(($(cat /sys/class/power_supply/pmi8998-charger/voltage_now) / 1000))" \
    "$(($(cat /sys/class/power_supply/pmi8998-charger/current_now) / 1000))"
}

step() {  # $1 метка, $2 подсказка
  echo; echo ">>> $2"; printf '    Enter — снять снимок, s — пропустить: '
  read a; [ "$a" = s ] && { echo "    пропущено"; echo "=== $1: пропущено" >> /tmp/pd-test.txt; return 1; }
  sleep 5; "$D/pd-load.sh" "$1" > /dev/null; echo "    снимок «$1» записан"; short
  return 0
}

step mac        "Шаг 1/5. Мак (кабель как сейчас)"
step steamdeck  "Шаг 2/5. Блок Steam Deck напрямую"
step hub        "Шаг 3/5. Хаб БЕЗ блока питания (за ним клавиатура/флешка)"
if step hub-pd  "Шаг 4/5. Хаб С блоком питания в PD-порту"; then
  echo ">>> Шаг 5/5. DR_Swap: прошу роль host"
  echo host > /sys/class/typec/port0/data_role 2>&1 && echo "    запрос принят" || echo "    запрос отклонён (см. лог)"
  sleep 3; "$D/pd-load.sh" hub-pd-drswap > /dev/null; echo "    снимок «hub-pd-drswap» записан"; short
  echo "    устройства за хабом:"; lsusb 2>/dev/null | grep -v 'root hub' | sed 's/^/      /'
fi
echo; echo "Готово. Лог: /tmp/pd-test.txt"
