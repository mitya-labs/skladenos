# План

> **2026-10-05: разделы 0–6 и «Следующий шаг» сняты с плана.** Они писались под pmOS (чёрный экран/зависание на старте, baseline 20 загрузок, cmdline-эксперименты, ramoops, бисект). Остаёмся на Mobian + SXMO (ядро 7.2), к ним не возвращаемся. Актуально только то, что ниже раздела «Потом: USB-host», и то, что в `SUMMARY.md`.

Порядок важен: каждый шаг решает, нужен ли следующий. Результаты каждого эксперимента записывать в `logs/` и в журнал внизу.

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

## Потом: USB-host (OTG, хаб Baseus с PD-портом, без своего БП)

Известно (STATE п.64): на ядре 7.2 `dr_mode = "peripheral"` у `usb@a600000`; DWC3 `DUAL_ROLE=y`, модули `xhci-hcd`, `usb-storage`; `/sys/class/typec` пуст; VBUS порта не питается (регулятор PMI8998 не настроен), поэтому хаб надо питать снаружи.

- [x] Этап 1. Разведка (выполнено, STATE п.74: `mode` не переключается, нужен DT) (~5 мин, без изменений): есть ли `/sys/kernel/debug/usb/a600000.usb/mode` и принимает ли `host`; `dmesg` про VBUS/PMI8998.
- [x] Этап 2 (образ `images/kernels/boot-7.2-host.img` собран, STATE п.75; не прошит). Принудительный хост через DT: взять `sdm845-xiaomi-beryllium-ebbg.dtb` из `linux-image-7.2-sdm845`, `dtc -I dtb -O dts`, `dr_mode = "host"`, обратно в dtb, собрать `boot.img` как делает `zz-qcom-bootimg` (cmdline с `rw`!). Откат: `fastboot flash boot images/kernels/boot-*-known-good.img`.
- [x] Этап 3 (работает после переподключения, STATE п.77). Проверка железа: телефон → хаб, **зарядник на PD-порт хаба** (БП 5 В и выше), в хаб клавиатура или флешка; `lsusb`, `dmesg | grep -i xhci`, `lsblk`. Заряжается ли телефон от хаба (гипотеза: да, если на CC стоит Rp).
- На время теста пропадает USB-сеть с Маком (`10.66.0.1`): SSH по Wi‑Fi; fastboot всегда доступен (Vol− + Power).
- [ ] Если порт не питает хаб/не видит устройства: апстрим-патч регулятора VBUS PMI8998 в `qcom_usb_vbus-regulator`, затем Type-C роли PMI8998 рядом с `qcom_pmic_typec_port.c`; согласовать в `#sdm845`.

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

## Потом: драйвер Type-C для PMI8998 (автоопределение роли USB)

Сейчас в апстриме нет Type-C/role-switch для PMI8998 (`/sys/class/typec` и `usb_role` пусты), поэтому роль USB-порта выбирается вручную (`phone-usb host|device`, пункт меню «usb»); по умолчанию после загрузки — device.

- [ ] Драйвер Type-C порта PMI8998 (по образцу `qcom_pmic_typec_port.c`): чтение CC, смена роли DWC3 через `usb_role_switch`, управление VBUS-регулятором, затем PD. Тогда хаб/флешка/Мак определятся сами, без ручного переключения.
- [ ] Согласовать в `#sdm845` и отправить в linux-arm-msm.

### Проект: Type-C + VBUS PMI8998 (старт 2026-10-05)

Разведка показала, что с нуля писать не нужно, апстрим-работа уже идёт:
- **Type-C role-switch**: серия `[PATCH 0/6] usb: typec: add Qualcomm PMI8998 …` (taygoth / Maxim Furman, v1, 18.05.2026, https://ratatoskr.run/linux-arm-msm/2026/05/16996111/t). Читает `TYPE_C_STATUS_4` (SPMI 0x1300), по IRQ `type-c-change` двигает `usb_role_switch` в dwc3. Тест на OnePlus 6T, Poco F1 заявлен. Критика ревью: нет PD/TCPM (Bryan: PDPHY совместим с PM8150B), нужно реальное имя автора, разделить USB и DT.
- **VBUS-регулятор**: `regulator: qcom_usb_vbus: Add support for PMI8998 VBUS` (James A. MacInnes, фев 2025, https://lkml.rescloud.iu.edu/2502.1/06549.html). Замечания Caleb Connolly: `.is_enabled`, задержка включения 250 мс, риск OCP при раннем потреблении тока.
- Зарядка: `qcom_smbx` (Casey Connolly) уже в апстриме, Type-C делит с ним регион USBIN.

Этапы:
- [x] 1. Исходники ядра Mobian `sdm845-7.2.8-1` + `debian/patches/series`, сборка dtb и модулей в Docker (`scripts/pmi8998-build`), минуты (STATE п.89).
- [x] 2. (серия taygoth + beryllium DT; отдельный патч регулятора не нужен, fallback pm8150b) Применить обе серии, добавить в DT beryllium (`sdm845-xiaomi-beryllium-common.dtsi`) узлы typec + vbus-regulator; `dr_mode = "otg"` + `usb-role-switch`, порт с `vbus-supply`.
- [x] 3. Boot-образ (как `boot-7.2-otg.img`), `fastboot boot` без прошивки; откат — `boot-7.2-otg.img`.
- [x] 4. (сделано, STATE п.89–91; hot-plug 5/5 после таблицы токов PMI8998) Тесты: Мак → device сам; хаб → host сам; VBUS питает хаб без зарядника в PD-порту (осторожно с током, сначала флешка/клавиатура); зарядка от Мака/зарядника не ломается; hot-plug 20 раз.
- [ ] 4б. (найдено, STATE п.90) Хаб с зарядником: автоматика даёт device, нужен PD DR_Swap (PDPHY 0x1700, как PM8150B) — вне объёма пунктов 1–2; пока ручной `phone-usb host`.
  - [x] 4б.1 Разбор исходников `qcom_pmic_typec*` (STATE п.122).
  - [x] 4б.2 (STATE п.123: модули есть, PDPHY свободен, Rp 3 А, 0x1360=08 ≈ 5–9 В) Проверка на телефоне (только чтение): `modinfo tcpm qcom_pmic_tcpm`, `/proc/interrupts` + DT даунстрима для IRQ PDPHY 0x17, дамп 0x1700–0x17FF и 0x1360.
  - [x] 4б.3 (STATE п.124: `pd/0009`, `pd/0010`, `boot-7.2-pd.img`; compatible `qcom,pmi8998-tcpm`) Port-бэкенд `pmi8998` в `qcom_pmic_typec_port` (или отдельный файл) + compatible `qcom,pmi8998-typec-pd`; DT: узел с reg 0x1300+0x1700, IRQ, `vdd-pdphy-supply = <&vreg_l24a_3p075>`, `vdd-vbus`, connector с `sink-pdos` только 5 В; модуль taygoth не грузить.
  - [~] 4б.4 (STATE п.125: Мак/Steam Deck — контракт есть; цикл Soft_Reset у Мака; хаб не проверен) `fastboot boot`: Мак/хаб без БП/хаб с БП (DR_Swap → host)/Steam Deck БП (контракт 5 В), `/sys/class/typec`, `usbpd` лог TCPM (debugfs `usb/tcpm-*`).
  - [ ] 4б.4а (09.10, новый хаб с PD) Хаб без БП → host; хаб с БП → DR_Swap `echo host > /sys/class/typec/port0/data_role` (`sudo ~/pd/pd-tests.sh`). Мак: цикл Soft_Reset — опыт с `pd-revision` 2.0 в DT.
  - [ ] 4б.5 (по желанию) 9 В: `USBIN_ADAPTER_ALLOW_CFG`, ICL, температура.
- [x] 5. (установлено на телефон, STATE п.92; снимок и sxmo-setup — ещё нет) Если стабильно: убрать ручной `phone-usb` из дефолта, обновить `sxmo-setup`, снимок.
- [ ] 6. Апстрим: тест на linux-next, отзыв/Tested-by на серию taygoth (Poco F1), при необходимости PD-PHY (общий с PM8150B) отдельным заходом.

