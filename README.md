# poco-f1-mainline

Исследование и патчи mainline Linux для **Xiaomi Poco F1** (`xiaomi-beryllium`, SDM845) под postmarketOS / Nura.

Главная цель — разобраться с **нестабильной загрузкой**: на свежих ядрах до ~80% загрузок заканчиваются чёрным экраном или зависанием. Вторая цель (позже) — USB-host на PMI8998.

Телефон нужен для палмтопа на Linux. Сам проект палмтопа (корпус, клавиатура, хаб, питание) ведётся отдельно, здесь — только ядро, DT и диагностика.

## Устройство

| | |
|---|---|
| Модель | Xiaomi Poco F1, M1805E10A |
| SoC / PMIC | Qualcomm SDM845 / PM8998 + PMI8998 |
| Панель | **EBBG** (FocalTech FT8719, драйвер панели и тачскрина только в форке; `dsi_ebbg_fhd_ft8719_video_display`, проверено 2026-10-02). Бывает ещё Tianma (NT36672A, есть в mainline) |
| Загрузчик | разблокирован 2026-10-02 |
| Пакет устройства | `device-xiaomi-beryllium` (pmaports, community) |
| Ядро | `linux-postmarketos-qcom-sdm845`, собирается из форка [sdm845-mainline/linux](https://gitlab.com/sdm845-mainline/linux) |

Версии ядра в pmOS (на 2026-10-02):

| Релиз | Тег форка |
|---|---|
| v25.12 | `sdm845-6.16.7-r0` |
| v26.06, edge | `sdm845-7.1-rc1-r0` |

## Известные проблемы

- **Загрузка** — [drm/msm#46](https://gitlab.freedesktop.org/drm/msm/-/work_items/46): с ~v6.5 гонка инициализации панели на SDM845, чёрный экран. Обходной путь в pmaports — `console=ttyMSM0,115200` без `quiet` ([kernel-cmdline.conf](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/community/device-xiaomi-beryllium/kernel-cmdline.conf)). По вики на 7.1-rc1 зависает ~80% загрузок, иногда нет модема и Wi-Fi.
- **USB-host** — в DT `dr_mode = "peripheral"`, нет драйверов Type-C и VBUS для PMI8998. Хост включается принудительно, 5 В наружу телефон не даёт.
- **Wi-Fi / модем** — модем отваливается через минуты–недели ([pmaports#3486](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/issues/3486)).

## Полезные факты из конфигурации ядра

- `CONFIG_DRM_MSM=y`, `CONFIG_DRM_PANEL_NOVATEK_NT36672A=y`, `CONFIG_DRM_PANEL_EBBG_FT8719=y` — всё встроено, `modprobe.blacklist` для дисплея не сработает без пересборки с `=m`.
- `CONFIG_PSTORE_RAM=y`, но в DT beryllium **нет узла ramoops** (у OnePlus 6 есть в `sdm845-oneplus-common.dtsi`).
- `CONFIG_QCOM_WDT=y`.
- Загрузчик оставляет включённый splash: в DT `simple-framebuffer` на `cont_splash_mem` (`0x9d400000`), потом экран забирает msm DRM.

## Структура (планируется)

```
PLAN.md         план работ
logs/           результаты загрузок, dmesg, pstore
scripts/        сбор статистики загрузок и автоматические проверки на телефоне
patches/        патчи к ядру и DT (формат git format-patch)
pmaports/       свой оверлей для pmbootstrap (device-, linux- пакеты)
```

## Ссылки

- Вики: [Xiaomi POCO F1 (xiaomi-beryllium)](https://wiki.nura.eco/wiki/Xiaomi_POCO_F1_(xiaomi-beryllium)), [OnePlus 6](https://wiki.nura.eco/wiki/OnePlus_6_(oneplus-enchilada)). Вики закрыта от ботов, но API открыт: `https://wiki.nura.eco/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&format=json&titles=<Страница>`
- [pmOS: SDM845 devices occasionally just have a black screen on boot](https://postmarketos.org/edge/2023/12/08/sdm845-no-display/)
- Mainline DT: `arch/arm64/boot/dts/qcom/sdm845-xiaomi-beryllium-{common.dtsi,tianma.dts,ebbg.dts}`
- Драйвер панели: `drivers/gpu/drm/panel/panel-novatek-nt36672a.c`
- USB/PMI8998: [патчи role-switch (Furman, май 2026, не приняты)](https://ratatoskr.run/linux-usb/2026/05/16996111/t), [ветка Кейси b4/pmi8998-typec](https://git.codelinaro.org/casey_connolly/kernel/-/commits/b4/pmi8998-typec/)
- Обновление прошивки: [LineageOS wiki](https://wiki.lineageos.org/devices/beryllium/fw_update/)
- Matrix: `#sdm845:postmarketos.org`, `#postmarketos-mainline`

## Mobian (Debian forky) на Poco F1 (ebbg)

Текущий статус: [`SUMMARY.md`](SUMMARY.md). Восстановление с нуля: [`RESTORE.md`](RESTORE.md). Подробные выводы: [`STATE.md`](STATE.md).

Статус и все выводы: `STATE.md`. Работает: Phosh, тач, Wi-Fi, зарядка, Bluetooth, звук (после `mobian-postinstall`: юнит запускает ADSP). USB-сеть по кабелю (SSH на `10.66.0.1`, после `mobian-postinstall`). Не работает/не проверено: модем/SIM (модем поднимается, нужна SIM), датчики (`slpi`, `qcom_scm -22`), камера (датчик отвечает ID 0x333, драйвер `imx363` ждёт 0x363).

Образы: `images/mobian/` (weekly 2026-09-27, ядро 6.12.90-1).
- `boot-beryllium-ebbg-rw.img`: boot-образ с `rw` в cmdline (оригинальный `…boot-beryllium-ebbg.img` с `ro` даёт бутлуп: `droid-juicer` ребутит, т.к. не может сохранить `status.json`).
- `mobian-sdm845-phosh-20260927.rootfs.img`: оригинальный rootfs (sparse).

Прошивка (телефон в fastboot: Power + Vol−; не пробрасывать в виртуалку):
```sh
scripts/mobian-flash --reboot
```
После первой загрузки (на телефоне включить `sshd`, вход `mobian`/`1234`):
```sh
scp scripts/mobian-postinstall mobian@mobian.local:/tmp/
ssh -t mobian@mobian.local sudo bash /tmp/mobian-postinstall
```
Скрипт: маска `rmtfs-dir.service` (без неё нет Wi-Fi), `apt-mark hold` на ядро/rmtfs/прошивки, обход для звука. Потом перезагрузить телефон.

### Обновление прошивок Android (только firmware, Mobian остаётся)
Источник: [LineageOS wiki: fw_update](https://wiki.lineageos.org/devices/beryllium/fw_update/), MIUI **V12.0.3.0.QEJMIXM** (Global; `androidboot.hwc=GLOBAL`). Архив `miui_POCOF1Global_V12.0.3.0.QEJMIXM_cf3fccffce_10.0.zip` (MD5 `cf3fccffcec70ec1cf9998f631965a7e`) лежит в `images/miui/`, распакована папка `firmware-update/`.
```sh
scripts/miui-firmware-flash --dry-run     # показать команды
scripts/miui-firmware-flash --reboot      # шьёт 16 разделов прошивки; boot/userdata не трогает
# на телефоне после загрузки:
scp scripts/mobian-refresh-firmware mobian@mobian.local:/tmp/
ssh -t mobian@mobian.local sudo bash /tmp/mobian-refresh-firmware   # переизвлечь прошивки droid-juicer
```

## Дополнительно (не в образе)

Необязательные вещи вынесены в [`extras/`](extras/README.md) и ставятся из репо по желанию: эмуляторы (HP Jornada 720, Psion 5mx, PumpkinOS) — `extras/emulators/install`. В базовый образ они не входят.
