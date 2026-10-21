#!/bin/sh
# Сборка эмуляторов НА ТЕЛЕФОНЕ (запускают extras/emulators/build-emulators.sh и extras/emulators/rebuild-emulators.sh с Мака, в фоне). Последовательно:
#   1. QEMU с патчами HP Jornada 720 → ~/Developer/qemu-jornada720/build/qemu-system-arm
#   2. PumpkinOS (make в src, БЕЗ -j: при -j4 libscriptlua линкуется раньше libpit)  → ~/PumpkinOS/pumpkin
#   3. WindEmu (Qt5, qmake, ветка pmos, сборка в дереве) → ~/Developer/WindEmu/WindQt/WindQt
#      порядок: sub-WindCore, потом остальное; GCC 16: в WindCore/arm710.h мог не хватать <functional>/<utility> — добавляем, если нет (идемпотентно)
# Шаг независим от остальных. Идемпотентно: повторный запуск докомпилирует. Итог шага — по наличию бинарника, а не по коду возврата.
# Лог: ~/logs/emulators-build.log, итоги: ~/logs/emulators-build.status (строки «имя OK|FAIL», в конце FINISHED).
JOBS="${JOBS:-4}"
LOG="$HOME/logs/emulators-build.log"
ST="$HOME/logs/emulators-build.status"
mkdir -p "$HOME/logs"
: > "$ST"
exec >> "$LOG" 2>&1
step() { echo; echo "=== $(date +%H:%M:%S) $*"; }
res() { echo "$1 $2" >> "$ST"; echo "=== $(date +%H:%M:%S) $1: $2"; }

step "QEMU (jornada720)"
(
  cd "$HOME/Developer/qemu-jornada720" &&
  { [ -d qemu-src ] || git clone --depth 1 https://gitlab.com/qemu-project/qemu.git qemu-src; } &&
  { [ -e qemu-src/hw/arm/jornada720.c ] || ln -s ../../../src/hw/arm/jornada720.c qemu-src/hw/arm/jornada720.c; } &&
  { [ -e qemu-src/.j720-patched ] || { cd qemu-src && for p in ../patches/0*.patch; do git apply "$p" && echo "применён $p" || exit 1; done && touch .j720-patched && cd ..; }; } &&
  mkdir -p build && cd build &&
  { [ -f build.ninja ] || ../qemu-src/configure --target-list=arm-softmmu --enable-sdl --enable-slirp; } &&
  ninja -j"$JOBS" qemu-system-arm
)
[ -x "$HOME/Developer/qemu-jornada720/build/qemu-system-arm" ] && res qemu OK || res qemu FAIL

step "PumpkinOS"
( cd "$HOME/PumpkinOS/src" && make )
[ -x "$HOME/PumpkinOS/pumpkin" ] && res pumpkinos OK || res pumpkinos FAIL

step "WindEmu (Qt5, ветка pmos)"
# Ветка pmos форка DmitriiTrifonov/WindEmu: поддержка Linux, сохранение состояния, слот CF, русская раскладка, звук ALSA, run.sh, run-sway.sh.
# (master — оригинал Treeki, только macOS: моя первая сборка с master была ошибкой, STATE п.108.) Собираем в дереве: run.sh ждёт WindQt/WindQt.
(
  cd "$HOME/Developer/WindEmu" &&
  { [ "$(git branch --show-current)" = pmos ] || { git checkout -q -- . && rm -rf build run-sway.sh && git fetch -q --depth 1 origin pmos && git checkout -q -B pmos FETCH_HEAD; }; } &&
  { grep -q '<functional>' WindCore/arm710.h || sed -i 's|^#include <variant>|#include <variant>\n#include <functional>\n#include <utility>|' WindCore/arm710.h; } &&
  python3 - <<'PY' &&
# Кнопки-символы Psion (compact layout): Qt5 не берёт Symbola/Noto Sans Symbols2 как запасной шрифт и рисует квадратики (STATE п.110).
# Явный список шрифтов для кнопок; 🧮 (U+1F9EE) и 🧩 (U+1F9E9) есть только в цветном Noto Color Emoji → заменены на 🖩 (U+1F5A9) и ⚙ (U+2699).
p = "WindQt/pdascreenwindow.cpp"
s = open(p, encoding="utf-8").read()
if "setFamilies" not in s:
    old = "font.setPointSizeF(font.pointSizeF() * 1.6);"
    assert old in s
    s = s.replace(old, old + '\n\t\t\t\tfont.setFamilies({"Symbola", "Noto Sans Symbols2", "DejaVu Sans"});', 1)
    s = s.replace("\U0001F9EE", "\U0001F5A9").replace("\U0001F9E9", "\u2699")
    open(p, "w", encoding="utf-8").write(s)
    print("WindEmu: патч символов применён")
PY
  { [ -f Makefile ] || qmake WindEmu.pro; } &&
  make -j"$JOBS" sub-WindCore &&
  make -j"$JOBS"
)
[ -x "$HOME/Developer/WindEmu/WindQt/WindQt" ] && res windemu OK || res windemu FAIL

step "ГОТОВО"
echo FINISHED >> "$ST"
