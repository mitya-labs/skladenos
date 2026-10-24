# Восстановление Mobian (Debian forky) на Poco F1 (beryllium-ebbg)

Цель: воспроизвести текущее рабочее состояние с нуля. Детали и история — в `STATE.md`.
Всё ниже выполняется с Мака в корне репозитория. Время: около 25–30 минут без учёта скачивания.

> **Актуальный путь (с 23.10) — готовый образ skladenOS, раздел A ниже.** Разделы 0–11 описывают прежний путь
> «чистый Mobian + ручная постнастройка» (пользователь `mobian`, Phosh): он нужен для прошивок Android (§1) и аварийных путей (§7),
> а вся остальная система собирается образом.

# A. Образ skladenOS: сборка и прошивка (около 15 минут без скачивания)

Нужны: Docker (сборка), `fastboot`, `images/mobian/` (rootfs Mobian и `boot-beryllium-ebbg-rw.img`, §0), прошивки Android уже залиты (§1).

```sh
packages/build.sh skladenos-config                       # по одному пакету за вызов → out/packages/*.deb
packages/build.sh skladenos-firstboot                    # и так для каждого изменённого skladenos-*
build/image/build.sh check                               # предпосылки, секунды
build/image/build.sh build                               # Docker, ~5–6 мин → out/image/<ГГГГММДД-ЧЧММ>/ (самопроверка [5/8] должна быть без «НЕТ»)
```
Телефон в fastboot (Vol− + Power), кабель прямо в Мак:
```sh
scripts/snapshot-flash out/image/<метка>                 # СТИРАЕТ телефон; распаковка, sha256, проверка rw, запрос yes, запись ~140 с
```
`fastboot reboot` после записи обычно виснет или пишет `could not clear input/output pipe e00002d6` (безвредно): выйти из fastboot
долгим нажатием питания (иногда помогает перетыкание кабеля). Первая загрузка 1–2 минуты.

**Первая загрузка образа:** мастер (`skladenos-firstboot`, язык выбирается на первом экране; Bluetooth-клавиатура → Wi‑Fi → имя
пользователя и пароль). До мастера вход `skladen` / `1234` (SSH по паролю открыт только из локальных сетей). Смена имени применяется
после перезагрузки (юнит `skladenos-firstboot-rename`, файл `/var/lib/skladenos/rename-pending`); флаг `firstboot-done` — мастер больше не запускается.

**После прошивки на Маке:** `ssh-keygen -R 10.66.0.1` (новый ключ хоста); доступ — `scripts/phone-ssh` (`PHONE_USER`, `PHONE_PASS`;
`--put` копирует файлы); перед работой по SSH — `phone-nosleep on`. Имя хоста в образе — `skladen` (`IMG_HOSTNAME`).
Проверка живой системы: `skladenos-touch-watchdog` active, мастер в `foot` с `touch-nudge`, в журнале нет ошибок кроме шума SXMO (STATE п.155).

Переменные сборки (`VARIANT=ebbg|tianma`, `IMG_USER`, `IMG_HOSTNAME`, `SSH`, `EXTRA_PKGS`) и устройство образа — в шапке `build/image/build.sh` и `build/image/README.md`.

---

# Прежний путь: чистый Mobian + ручная постнастройка


## 0. Что должно быть под рукой

Артефакты лежат в `images/` (в git **не входят**, хранить отдельно; еженедельные образы Mobian на сайте
удаляются). Контрольные суммы (sha256) — в конце файла (§10); проверка: `shasum -a 256 <файл>`.

| Файл | Назначение | Откуда |
|---|---|---|
| `images/mobian/mobian-sdm845-phosh-20260927.tar.xz` | образ Mobian (weekly 2026-09-27, ядро 6.12.90-1) | `https://images.mobian.org/qcom/weekly/` (может быть удалён!) |
| `images/mobian/mobian-sdm845-phosh-20260927.rootfs.img` | rootfs из архива (sparse, 6.2 ГБ) | `tar -xf …tar.xz` |
| `images/mobian/boot-beryllium-ebbg-rw.img` | boot с `rw` в cmdline | `scripts/make-boot-rw ebbg` (создаётся автоматически) |
| `images/miui/miui_POCOF1Global_V12.0.3.0.QEJMIXM_cf3fccffce_10.0.zip` | прошивки Android, `firmware-update/` | сторонние зеркала (MD5 `cf3fccffcec70ec1cf9998f631965a7e`) |
| `images/pmos-v25.12-ebbg-4k/boot-debugshell.img` | аварийный pmOS debug-shell | собран ранее, см. `STATE.md` |

Требования: `fastboot` (`brew install android-platform-tools`), разблокированный загрузчик (`fastboot getvar unlocked` → `yes`),
батарея > 50%, кабель с данными (при зависании fastboot — порт USB-A 2.0 или хаб). Телефон **не пробрасывать в виртуалку**.
Модель: `androidboot.hwc=GLOBAL`, панель **ebbg** (для tianma — `scripts/mobian-flash --tianma`).

## 1. Прошивки Android (один раз; нужны для микрофона, свежего модема и WLAN)

Телефон в fastboot (Power + Vol−).

```sh
scripts/miui-firmware-flash --dry-run      # показать 16 команд
scripts/miui-firmware-flash --yes          # прошивает ТОЛЬКО прошивки; boot/userdata не трогает
```
Без этого шага микрофон отдаёт нули, а датчики/модем остаются на прошивке 2018 года.

## 2. Mobian

```sh
scripts/mobian-flash --reboot              # boot(rw) + userdata + dtbo; стирает userdata!
```
Скрипт сам делает `rw`-образ (`scripts/make-boot-rw`). **Нельзя** шить оригинальный `…boot-beryllium-ebbg.img`:
в cmdline стоит `ro`, и Mobian уходит в бутлуп (`droid-juicer` не может записать `status.json`).

## 3. Первая загрузка (вручную на телефоне)

1. Ждать 2–3 минуты (растягивание ФС, `droid-juicer`). Вход: `mobian` / `1234`.
2. Подключить Wi-Fi в настройках Phosh. Wi-Fi на свежей установке может не быть до пункта 4 (конфликт двух `rmtfs`).
   Если нет: ещё один ребут. Запасной вход — USB-консоль через pmOS debug-shell (см. §6).
3. В терминале телефона включить SSH: `sudo systemctl enable --now ssh || sudo apt install -y openssh-server`.

## 4. Постнастройка по SSH

```sh
scp scripts/mobian-postinstall mobian@mobian.local:/tmp/
ssh -t mobian@mobian.local sudo bash /tmp/mobian-postinstall
ssh -t mobian@mobian.local sudo reboot
```
Скрипт ставит: маску `rmtfs-dir.service` (без неё нет Wi-Fi), `apt-mark hold` (ядро, rmtfs, прошивки),
юнит `adsp-start`, таймаут остановки 15 с, отключение Wi-Fi powersave, обход для звука,
`GMOBILE_DT_COMPATIBLES` (вырез экрана), дропин USB-гаджета (SSH по кабелю на `10.66.0.1`).

## 5. После обновления прошивок Android — перегнать `droid-juicer`

(Если в §1 прошивали Android — **обязательно**, иначе файлы модема/WLAN/ADSP от старой выгрузки.)

```sh
scp scripts/mobian-refresh-firmware mobian@mobian.local:/tmp/
ssh -t mobian@mobian.local sudo bash /tmp/mobian-refresh-firmware
```
Скрипт: бэкап старой выгрузки, `droid-juicer` заново, **отключает SLPI** (`slpi.mbn` → `/root/fw-disabled/`, иначе он падает в
цикле и жжёт батарею) и пересобирает initramfs. **Важно:** пересборка initramfs **перезаписывает раздел `boot`**
(`update-initramfs` → `zz-qcom-bootimg`). Перед ребутом проверить, что в нём `rw`:
```sh
sudo dd if=/dev/disk/by-partlabel/boot bs=1M count=8 2>/dev/null | grep -a -o 'init=/sbin/init [a-z]* quiet splash'
# должно быть: init=/sbin/init rw quiet splash   (если ro — НЕ перезагружаться, перешить boot-rw через fastboot)
```
Затем `sudo reboot`.

## 6. Проверка результата (чек-лист)

| Что | Команда на телефоне / Маке | Ожидаемо |
|---|---|---|
| Phosh, тач, вырез | глазами | экран блокировки, значки не под вырезом |
| `boot` | `dd … \| grep -a -o …` (см. §5) | `rw` |
| Wi-Fi | `ip -br a show wlan0` | `UP`, адрес |
| DSP | `for r in /sys/class/remoteproc/*; do echo $(cat $r/name) $(cat $r/state); done` | `adsp`, `cdsp`, модем `running`; `5c00000.remoteproc` (slpi) `offline` |
| Звук | `cat /proc/asound/cards`; `speaker-test -t wav -c 2 -l 1` | карта `sdm845 - Xiaomi Poco F1`, слышно |
| Микрофон | `pw-record --rate 48000 --channels 1 /tmp/m.wav` и говорить | не нулевой уровень |
| Модем | `mmcli -m 0` | виден; без SIM: `failed reason: sim-missing` (норма) |
| USB-гаджет | на Маке: `ifconfig` → порт «Debian» (`en*`, 10.66.0.x); `ssh mobian@10.66.0.1` | отвечает |
| Холды | `apt-mark showhold` | 9 пакетов |
| `rmtfs-dir` | `systemctl is-enabled rmtfs-dir` | `masked` |

## 7. Аварийные пути

- **Бутлуп** (логотип → ребут ~30 с): в `boot` `ro`. Перешить `images/mobian/boot-beryllium-ebbg-rw.img` (`fastboot flash boot …`).
- **Нет Wi-Fi/SSH**: один раз случается нестабильный старт WLAN — ещё один ребут. USB-сеть: после §4 заходить по кабелю (`ssh mobian@10.66.0.1`).
- **Совсем нет доступа**: `fastboot boot images/pmos-v25.12-ebbg-4k/boot-debugshell.img` (ничего не прошивает) →
  `telnet 172.16.42.1` (pmOS debug-shell, `userdata` монтируется как `/dev/disk/by-partlabel/userdata`, журнал в `/var/log/journal`).
- **Type-C/PD (ядро 7.2) сломался или не нравится**: режим PD (TCPM, STATE п.129–133) ставится `scripts/pmi8998-install` + на телефоне `sudo pmi8998-reapply apply pd`; вернуть Type-C без PD — `sudo pmi8998-reapply apply typec`, всё штатное — `revert` (потом перезагрузка). Без SSH: `fastboot flash boot images/kernels/boot-7.2-taygoth-20261010.img` (taygoth; модуль PD в `updates/` при этом останется, но с этим dtb не привяжется). После апдейта пакета ядра — пересборка `scripts/pmi8998-build` и `PD=1 scripts/pmi8998-build`.
- **`fastboot` зависает**: другой USB-порт (A 2.0) / хаб; телефон не должен быть проброшен в VM.
- **Ошибка `usb_read failed … e00002eb`** при `fastboot flash`: телефон забрала виртуалка (UTM) — отключить от неё.

## 8. Что НЕ восстанавливается

- **Данные и настройки на телефоне**: пароли Wi-Fi, ваши файлы, приложения, Phosh-настройки (`mobian-flash` стирает `userdata`).
  Для этого есть снимок: `scripts/mobian-snapshot` (§11).

- Точное состояние пакетов (лишние установки руками: `hexagonrpcd` и др. — на работу не влияют).
- Замеры `mobian-health` (юнит `mobian-health`/`mobian-health-after`, `scripts/mobian-health`) — по желанию.

## 9. Известные проблемы (на момент снимка)

- **Датчики не работают** (`slpi`): `qcom_scm Assign memory protection call failed -22`, FastRPC sdsp не поднимается; SLPI отключён намеренно.
- **Камера не работает**: `imx363 … chip id mismatch: 363!=333` — на i2c 0x10 отвечает чип с ID 0x333, драйвер `imx363` отказывается.
- **Модем**: поднимается, но проверить звонки/data нельзя без SIM.
- Wi-Fi иногда не стартует с первого раза (WLAN-прошивка падает при инициализации).
- Любое обновление initramfs/ядра перезаписывает `boot` (см. §5, проверка `rw`).

## 10. Контрольные суммы (sha256)

```
fdb81d6d67ec0371258e770f0558932d3ebd064602c2890bbd6a828d5a360200  mobian/mobian-sdm845-phosh-20260927.tar.xz
d2001779738340a29db875c6a8a44c518a1a408413dfd1666cda9cfd2288dd07  mobian/mobian-sdm845-phosh-20260927.rootfs.img
1a0d1fd94e002b5e4e9c7db9ac645ca0e26d7c9411e2c68907d52298cc589585  mobian/boot-beryllium-ebbg-rw.img
adf1e964e68d2489017cb06a638bbb90f4c5da7c48fe7c00952d783b4e849cb9  mobian/boot-beryllium-tianma-rw.img
aeb05ec30c8feccc65d2152cfa8bdbbdc9800874aff4c570057d9326e9038630  miui/miui_POCOF1Global_V12.0.3.0.QEJMIXM_cf3fccffce_10.0.zip
2bb488d445a18adb2c7bc9fdeb8260cae81d053728d08745278f60f05f98f7b1  pmos-v25.12-ebbg-4k/boot-debugshell.img
```
MD5 MIUI-архива: `cf3fccffcec70ec1cf9998f631965a7e`. `boot-*-rw.img` воспроизводится `scripts/make-boot-rw` (проверено: байт-в-байт совпал с прошитым).

## 11. Снимок системы (данные и настройки)

`scripts/mobian-snapshot [хост]` (по умолчанию USB-кабель `10.66.0.1`, ~5 минут): архив `/` (`tar` + `zstd -3`, xattrs/acls,
без `/proc /sys /dev /run /tmp` и кеша apt) + `dd` раздела `boot` + метаданные (uname, os-release, holds, `cmdline` в `boot`,
`fstab`, `dpkg --get-selections`) → `images/snapshots/mobian-<ГГГГММДД-ЧЧММ>/`, sha256 сверяется при копировании.
Текущий: `mobian-20261010-2147` (`snap.tar.zst` 3.92 ГБ, `snap.boot.img.zst` 50 МБ; Mobian, ядро 7.2, SXMO, **PD** (STATE п.133),
`boot` с `rw`, SLPI/датчики работают); предыдущие — `mobian-20261008-1723`, `mobian-20261006-0916`.

**Какой снимок что умеет** (подробно — `<снимок>/ABOUT.txt`; новые снимки: `NOTE="..." scripts/mobian-snapshot`):

| Снимок | Что есть | Чего нет |
|---|---|---|
| `mobian-20261006-0916` (п.115) | ядро 7.2, SXMO, сон, USB-OTG, Type-C через taygoth, эмуляторы, us+ru | SLPI, PD |
| `mobian-20261008-1723` (п.119) | + датчики SLPI, nosleep-фиксы, альбомные обои, Super+F, подменю Scripts | PD, старт в альбоме, EN/RU в баре, ребут из меню |
| `mobian-20261010-2147` (п.134) | + USB PD (хаб с зарядником → host + зарядка, 3 А), старт в альбоме, EN/RU в баре, ребут из меню | — |

Все три — с `flash/` (`boot.img` + сжатый `userdata.simg.zst`; несжатые удалены 10.10, освободилось ~14 ГБ).

**Образы для fastboot (основной способ восстановления, проверен 05.10, STATE п.71):**
`scripts/snapshot-to-userdata [снимок]` (~5 мин, Docker arm64) → `<снимок>/flash/`: `boot.img` (с `rw`),
`userdata.simg.zst` (sparse ext4 с UUID корня из снимка, **сжат zstd -10**: 9,6 ГБ → 3,3 ГБ; fastboot ест только несжатый),
`SHA256SUMS` (сжатого и распакованного), `FLASH.txt`. Прошивка — **стирает userdata**:
```sh
scripts/snapshot-flash mobian-20261010-2147   # распакует .zst (~9 ГБ места), сверит sha256, проверит rw, спросит yes, прошьёт
```
Вручную: `cd <снимок>/flash && zstd -d userdata.simg.zst && shasum -a 256 -c SHA256SUMS` → `fastboot flash boot boot.img` →
`fastboot erase userdata` → `fastboot -S 100M flash userdata userdata.simg` → `fastboot reboot` (может повиснуть: `pkill -9 fastboot`
и повторить) → `rm userdata.simg`. Первая загрузка ~1–2 мин, ФС сама растягивается на весь раздел (`x-systemd.growfs`).

**Секреты**: в снимке пароли Wi-Fi (NetworkManager), хэши паролей, host-ключи SSH — хранить локально, не публиковать
(`images/` вне git).

**Восстановление поверх живой системы по SSH (НЕ проверялось на практике, это план; проще — образы fastboot выше):**
1. Базовая установка по §1–§2 (`miui-firmware-flash`, `mobian-flash --reboot`), SSH, как в §3.
2. Накатить снимок поверх по SSH (на работающей системе, по USB-кабелю):
   ```sh
   S=images/snapshots/mobian-20261010-2147
   shasum -a 256 -c $S/snap.sha256           # внутри папки: cd $S && shasum -a 256 -c snap.sha256
   zstd -dc $S/snap.tar.zst | ssh mobian@10.66.0.1 'sudo tar -xpf - --xattrs --acls --numeric-owner -C /'
   ```
3. Раздел `boot` (нужен, чтобы initrd в `boot` совпал с `/boot` из снимка; делать только если нужно вернуть точное состояние):
   `zstd -dc $S/snap.boot.img.zst > /tmp/boot.img` → `fastboot flash boot /tmp/boot.img` (перед этим убедиться, что cmdline `rw`:
   `grep -a -o 'init=/sbin/init [a-z]* quiet splash' /tmp/boot.img`). Затем `reboot`.
Осторожно: распаковка поверх живой системы перезапишет `/etc`, `/var`, `/usr` (в т. ч. то, что сейчас запущено); при проблемах запасной путь — pmOS debug-shell (§7).
