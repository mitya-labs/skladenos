# Архив плана: поиск причины сбоев pmOS (снят 2026-10-05)

Вынесено из `PLAN.md` 24.10. К этим разделам не возвращаемся: проект на Mobian + SXMO (ядро 7.2). Находки из этих сессий также в `STATE.md`.

## 0. Подготовка

- [ ] Обновить прошивку загрузчика до MIUI 12.0.3 Global (`firmware-update/*` из zip, [инструкция](https://wiki.lineageos.org/devices/beryllium/fw_update/)). Полным Mi Flash с «clean all and lock» не шить.
- [x] Узнать панель: `msm_drm.dsi_display0` в `/proc/cmdline` → **ebbg** (`dsi_ebbg_fhd_ft8719_video_display`).
- [ ] Linux-окружение для `pmbootstrap` на Mac: виртуалка (UTM / OrbStack), USB для fastboot проброшен в неё, либо `fastboot` с хоста (`brew install android-platform-tools`).
- [ ] Поставить **v25.12** (ядро 6.16.7), а не v26.06 / edge (7.1-rc1). Перезагружать только через `fastboot reboot` / `reboot`, не кнопкой.
- [ ] SSH по USB (`ssh user@172.16.42.1`) и по Wi-Fi. Ключ на телефоне, чтобы скрипты ходили без пароля.
- [ ] Постоянный журнал: `Storage=persistent` в `/etc/systemd/journald.conf` (если образ на systemd).

## 1. Классифицировать сбой

Вики смешивает три симптома. Для каждой неудачной загрузки определить, какой это:

| Код | Симптом | Как отличить |
|---|---|---|
| `BLACK` | экран чёрный, система жива | SSH по USB работает |
| `HANG` | система не загрузилась | нет USB-сети, после следующей загрузки в `journalctl -b -1` пусто или обрыв |
| `NOMODEM` | экран есть, нет модема / Wi-Fi | `nmcli dev`, `dmesg \| grep -i remoteproc` |
| `OK` | всё работает | |

- [ ] `scripts/boot-report` — unit на телефоне, через ~60 с после загрузки пишет в `/var/log/boot-stats.csv`: время, `uname -r`, cmdline, статус DSI (`/sys/class/drm/card*-DSI-1/{status,enabled}`), строки `dsi|panel|mdss` из `dmesg`, есть ли `wlan0` и модем.
- [ ] `scripts/collect` на Mac — забирает CSV и `journalctl -b -1` по SSH в `logs/<дата>/`.
- [ ] Набрать **20 загрузок** на текущей конфигурации (baseline). Записать долю `OK / BLACK / HANG / NOMODEM`.

## 2. Эксперименты с cmdline

Каждый вариант — 20 загрузок, результат в таблицу журнала. Cmdline меняется в `/etc/deviceinfo`, затем `sudo apk fix linux-postmarketos-qcom-sdm845` (или пересобрать boot.img через pmbootstrap).

- [ ] **A.** baseline v25.12 (6.16.7) против v26.06 (7.1-rc1). Если разница большая — это регрессия, переходим к шагу 4.
- [ ] **B.** `clk_ignore_unused pd_ignore_unused` — не гасить клоки и домены питания, которые держат splash загрузчика. Если `BLACK`/`HANG` пропадут — проблема в передаче дисплея от загрузчика.
- [ ] **C.** Больше задержки в консоли: `ignore_loglevel`, `initcall_debug`.
- [ ] **D.** Без обходного пути (убрать `console=ttyMSM0`, вернуть `quiet`) — для контроля, насколько он вообще помогает.

## 3. Видеть, что происходит при `HANG`

- [ ] Добавить в DT beryllium узел **ramoops** по образцу `sdm845-oneplus-common.dtsi`: свободный регион в reserved-memory, `record-size`, `console-size`, `pmsg-size`. Проверить, что регион не пересекается с другими. `CONFIG_PSTORE_RAM=y` уже включён.
- [ ] Проверить, что pstore выживает при тёплой перезагрузке: `echo c > /proc/sysrq-trigger` → после загрузки `/sys/fs/pstore/`.
- [ ] После `HANG` (долгое нажатие питания → загрузка) читать `/sys/fs/pstore/console-ramoops-0` и сохранять в `logs/`.
- [ ] Поискать UART на плате ([схемы Poco F1](https://www.mobilerdx.com/2021/01/xiaomi-pocophone-f1-schematics-diagram-service-manual.html)): если тест-пады доступны — это самый надёжный лог. Пайка — крайний вариант.

## 4. Найти регрессию (bisect)

Делать, только если шаг 2A показал заметную разницу между 6.16 и 7.1.

- [ ] Форк `sdm845-mainline/linux` перебазируется под каждую версию, поэтому бисект между тегами форка напрямую не работает. Варианты:
  - бисектить **upstream** `v6.16..v7.1-rc1`, накладывая на каждый шаг минимальный набор патчей форка, нужный для загрузки beryllium (DT панели EBBG, тачскрин и т.п. — для Tianma, скорее всего, хватит почти чистого upstream);
  - сначала проверить, загружается ли чистый upstream 7.1-rc1 на Tianma с нужным cmdline: если да, бисект становится обычным.
- [ ] Сборка ядра: `pmbootstrap build --src=<дерево> linux-postmarketos-qcom-sdm845`, загрузка без прошивки — `pmbootstrap flasher boot`.
- [ ] ~12–14 шагов, на каждом 10+ загрузок. Скрипт: собрать → `fastboot boot` → подождать → проверить по SSH → записать → повторить N раз.
- [ ] Результат (коммит + статистика) — в [drm/msm#46](https://gitlab.freedesktop.org/drm/msm/-/work_items/46) и в Matrix `#sdm845`.

## 5. Обходной путь для повседневной работы

Параллельно с 2–4, чтобы телефоном можно было пользоваться:

- [ ] Для `BLACK`: unit проверяет статус DSI и при сбое перепривязывает драйвер дисплея (`/sys/bus/platform/drivers/msm-mdss/{unbind,bind}`) или перезагружается. Сначала проверить вручную, переживает ли msm такую перепривязку.
- [ ] Для `HANG`: включить аппаратный watchdog (`CONFIG_QCOM_WDT=y` уже есть; `RuntimeWatchdogSec=` в systemd) — поможет, только если зависание случается после старта systemd.
- [ ] Свой оверлей в `pmaports/`: device-пакет с ramoops в DT и нужным cmdline, чтобы ничего не терялось при обновлениях.

## 6. Фикс (по результатам)

- [ ] Разобрать порядок включения DSI-хоста и панели: `prepare_prev_first` (с ним баг воспроизводится на OnePlus 6), тайминги reset в `panel-novatek-nt36672a.c` (`msleep(200)` вокруг reset), передача splash → msm DRM.
- [ ] Патч — в `patches/`, проверить на 20+ загрузках, отправить в dri-devel / linux-arm-msm (b4), CC мейнтейнерам SDM845.

## Журнал

| Дата | Ядро | Cmdline / изменение | Загрузок | OK | BLACK | HANG | NOMODEM | Заметки |
|---|---|---|---|---|---|---|---|---|
| 2026-10-02 | 6.16.7 | До установки: все 4 «варианта» boot.img оказались байт-в-байт одинаковыми; телефон жил только в initramfs (rootfs не прошит) | 5+ | 0 | — | — | — | NONET = нет rootfs + macOS не видит сеть без драйвера. NCM-гаджет Mac видит нативно (en20 = 172.16.42.2) |
| 2026-10-02 | 6.16.7 | Установлен pmOS v25.12 на userdata | 5+ | 0 | 1 | 4 | — | Итог: initramfs доходит до switch_root, systemd не стартует — ядро зависает намертво. Причина найдена: в прошитом rootfs libsystemd-core/shared несовместимы (битые файлы, хэши ≠ VM-чрут при тех же размерах/версии). Образ на диске Mac идентичен образу в VM |
| 2026-10-02 | 6.16.7 | Диагностические boot.img: ramoops@0x9d000000 + pmos.debug-shell + console=ttyGS0 (boot-diag.img, boot-console-diag.img, boot-sddebug.img в images/pmos-v25.12-ebbg-4k/) | — | — | — | — | — | ramoops: жёсткий ресет стирает RAM (pstore пуст после Power-долго). Тёплый ресет (sysrq-b) не проверен до конца. Telnet debug-shell работает, ACM-порт /dev/cu.usbmodempostmarketOS3 — консоль ядра видна на Mac |
| 2026-10-02 | 6.16.7 | Пересборка образа в VM | — | — | — | — | — | Найден баг сборки: Alpine VM ядро loop.max_part=0 → /dev/loop1p2 не создавался → pmbootstrap install падал (ERROR: File did not appear). Исправлено: loop.max_part=8 в GRUB VM + перезагрузка. Новый образ xiaomi-beryllium-v3.img собран 17:41, проверен: libsystemd-shared внутри — правильный хэш c3aa29d7 |

## Следующий шаг (при возврате) — СНЯТО, см. заметку вверху

- [x] Прошить исправленный образ (выполнено: rootfs цел, systemd грузится, SSH работает — mitya/<пароль>, ключ добавлен, doas nopass, journal persistent)
- [ ] Набрать 20 baseline-загрузок (шаг 1 плана): `scripts/boot-report` на телефоне + `scripts/collect` на Mac
- [ ] Эксперименты cmdline (шаг 2), в т.ч. оценить эффект `loglevel=8` (уже вшит в boot-v3-lvl.img)

## Ключевые находки 2026-10-02 (сессия восстановления)

- **Причина NONET/чёрных экранов до установки**: rootfs не был прошит вообще; на Mac нет RNDIS-драйвера (гаджет телефона — NCM, Mac видит его нативно как en20).
- **Причина зависания после установки**: битые файлы systemd в прошитом rootfs. Установлено, что образ был собран в VM с недособранным/битым содержимым; корневой баг сборки — `loop.max_part=0` в ядре Alpine VM → `pmbootstrap install` падал на `/dev/loop1p2` (исправлено: `loop.max_part=8` в GRUB VM).
- **Вторая причина порчи при прошивке**: загрузчик Xiaomi (ABL) побайтово портит FILL-чанки sparse-образа (~1.5% блоков, детерминированно: содержимое берётся со смещением +168 блоков). Плюс fastboot на macOS не читает файлы >2 ГБ. Обход: заливка raw-образа через `cat img | adb shell dd of=/dev/block/sda21` под TWRP (ядро 4.9 — чистый канал). Точечно битые блоки можно перезаписать dd с seek.
- **Warm-reboot (sysrq-b) теряет незаписанный кэш** — изменения в /etc (тень, ключи) пропадают; перед тёплым ресетом нужен sync/umount. Hard-reset (Power ~15с) стирает RAM → ramoops/pstore бесполезны для настоящих зависаний.
- **RAMOPS в dtb**: узел должен быть ВНУТРИ reserved-memory с compatible="ramoops" + reg (иначе «failed to locate DT /reserved-memory resource»). Регион 0x9d000000-0x9d400000 свободен.
- **Диагностический инструментарий** (images/pmos-v25.12-ebbg-4k/): boot-diag.img (ramoops+debug-shell), boot-console-diag.img (+ttyGS0 консоль на /dev/cu.usbmodem*, ACM не снимается при continue), boot-v3-lvl.img (штатный + loglevel=8). Telnet-шелл: `nc 172.16.42.1 23`, `pmos_continue_boot`.
- **drm/msm#46**: в downstream msm-4.9 (codelinaro 77c17178) BCR-ресеты MDSS убраны как нерабочие (0x2000 → crashdump) — ресет-путь тупик. Console-workaround требует достаточно высокого loglevel (chayleaf).
- Образ: `xiaomi-beryllium-v3-raw.img` (залит), `xiaomi-beryllium-v3.img` (sparse, не использовать с этим ABL). Пароль mitya = <пароль>, хостнейм skladen-2, UI sxmo-de-sway.
