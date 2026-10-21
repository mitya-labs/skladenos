# packages — deb-пакеты skladenOS

Всё, что раньше делали скрипты `scripts/*-setup/-install` на живом телефоне, переезжает в пакеты: образ собирается из них воспроизводимо.

| Пакет | Что | Статус |
|---|---|---|
| `skladenos-config` | слой A — системные настройки: профиль устройства SXMO, ADSP/SLPI/звук, USB-гаджет, Wi-Fi powersave, вырез, планы питания, SXMO по умолчанию, шимы `superctl`/`doas`, `phone-nosleep`, `phone-usb`, `sxmo-safe-area` | собран, ставится в чистом Debian (smoke-тест) |
| `skladenos-config` | слой B — пользовательские настройки SXMO (sway, хуки статус-бара/поворота, меню Scripts, иконки, клавиатуры) | в работе, см. `STATE.md` |

Сборка: `packages/build.sh skladenos-config` → `out/packages/*.deb` (нужен Docker).
Ядро собирается отдельно: `build/kernel/build.sh` (см. `build/kernel/UPSTREAM`).
Что не переносится в пакет: `apt-mark hold` (версии фиксирует сборка образа), часовой пояс и пользователь (личное), прошивки Qualcomm (`droid-juicer` извлекает их на самом телефоне).
