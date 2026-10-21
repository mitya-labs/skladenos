# packages — deb-пакеты skladenOS

Всё, что раньше делали скрипты `scripts/*-setup/-install` на живом телефоне, переезжает в пакеты: образ собирается из них воспроизводимо.

| Пакет | Что | Статус |
|---|---|---|
| `skladenos-artwork` | обои «Skladen v2.1» и логотип — **все права защищены** (`assets/NOTICE.md`), `Section: non-free` | собран |
| `skladenos-config` | слой A — системные настройки: профиль устройства SXMO, ADSP/SLPI/звук, USB-гаджет, Wi-Fi powersave, вырез, планы питания, SXMO по умолчанию, шимы `superctl`/`doas`, `phone-nosleep`, `phone-usb`, `sxmo-safe-area` | собран, ставится в чистом Debian (smoke-тест) |
| `skladenos-config` | слой B — `skladenos-apply`: пользовательские настройки SXMO в `~/.config/sxmo` (sway с баром под вырез, хуки статус-бара/поворота/suspend, меню Scripts, клавиатуры, виджет часов), собираются из штатных шаблонов sxmo-utils; юнит `skladenos-apply.service` + postinst | собран и проверен тестом `packages/test-apply.sh` на настоящем sxmo-utils; **не проверен на телефоне**. Не сделаны: иконки Nerd Font |

Сборка: `packages/build.sh skladenos-config` → `out/packages/*.deb` (нужен Docker). Тест слоя B: `packages/test-apply.sh` (собрать нужно оба пакета: `skladenos-config` зависит от `skladenos-artwork`).
Ядро собирается отдельно: `build/kernel/build.sh` (см. `build/kernel/UPSTREAM`).
Что не переносится в пакет: `apt-mark hold` (версии фиксирует сборка образа), часовой пояс и пользователь (личное), прошивки Qualcomm (`droid-juicer` извлекает их на самом телефоне).
