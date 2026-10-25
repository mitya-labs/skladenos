## English

**skladenOS** is a Linux handheld OS for the **Xiaomi Poco F1** (SDM845): Mobian (Debian forky) with the SXMO (sway) desktop, kernel 7.2 with our Type-C/USB-PD patches, a first-boot wizard (12 languages) and the `skladenos-*` packages.

This release is the image for the **EBBG panel** variant of the Poco F1 (the usual Global one). The Tianma panel image is not published yet.

### Install (this ERASES the whole phone)

You need: an **unlocked bootloader**, `fastboot` and `zstd` on a computer (Linux, macOS or Windows with WSL), a USB cable, ~10 GB of free disk space.

1. Download `ebbg-boot.img`, `ebbg-userdata.simg.zst` and `SHA256SUMS` from the files below into one folder.
2. Check the files: `sha256sum -c SHA256SUMS --ignore-missing` (on macOS: `shasum -a 256 -c SHA256SUMS --ignore-missing`).
3. Unpack the image (about 9 GB): `zstd -d ebbg-userdata.simg.zst -o userdata.simg`
4. Put the phone into fastboot: power off, hold **Vol− + Power**, connect the cable. `fastboot devices` should list it.
5. Flash:
   ```
   fastboot flash boot ebbg-boot.img
   fastboot erase userdata
   fastboot -S 100M flash userdata userdata.simg
   fastboot reboot
   ```
6. The first boot takes 1–3 minutes: the phone extracts its own firmware and reboots once. Then the first-boot wizard starts (language, Bluetooth keyboard, Wi-Fi, user name, new password).

Default login: user `skladen`, password `1234`. Until you change the password, SSH is allowed from local networks only.

If `fastboot reboot` hangs, hold Power for about 10 seconds. Qualcomm and Xiaomi firmware is not distributed: it is extracted on the phone itself.

### Other files

- `linux-image-7.2-sdm845_*.deb`, `linux-headers-7.2-sdm845_*.deb` — the kernel.
- `skladenos-*.deb` — the packages. They are also in the signed apt repository **garmon**: https://mitya-labs.github.io/apt
- `ebbg-MANIFEST.txt` — packages inside the image; `SHA256SUMS` — checksums of the release files.
- `ebbg-FLASH.txt` — build notes for developers (it refers to scripts from the repository).

More: https://mitya-labs.github.io/en/skladenos/ · sources and build from scratch: https://github.com/mitya-labs/skladenos

## Русский

**skladenOS** — система для **Xiaomi Poco F1** (SDM845): Mobian (Debian forky) с рабочим столом SXMO (sway), ядро 7.2 с нашими патчами Type-C/USB-PD, мастер первой загрузки (12 языков) и пакеты `skladenos-*`.

В релизе образ для варианта с панелью **EBBG** (обычный Global). Образ для панели Tianma пока не опубликован.

### Установка (СТИРАЕТ весь телефон)

Нужны: **разблокированный загрузчик**, `fastboot` и `zstd` на компьютере (Linux, macOS или Windows с WSL), кабель USB, ~10 ГБ свободного места.

1. Скачайте `ebbg-boot.img`, `ebbg-userdata.simg.zst` и `SHA256SUMS` из файлов ниже в одну папку.
2. Проверьте файлы: `sha256sum -c SHA256SUMS --ignore-missing` (на macOS: `shasum -a 256 -c SHA256SUMS --ignore-missing`).
3. Распакуйте образ (около 9 ГБ): `zstd -d ebbg-userdata.simg.zst -o userdata.simg`
4. Переведите телефон в fastboot: выключите, зажмите **Громкость− + Питание**, подключите кабель. `fastboot devices` должен показать устройство.
5. Прошейте:
   ```
   fastboot flash boot ebbg-boot.img
   fastboot erase userdata
   fastboot -S 100M flash userdata userdata.simg
   fastboot reboot
   ```
6. Первая загрузка занимает 1–3 минуты: телефон извлекает собственные прошивки и один раз перезагружается. Затем запускается мастер первой загрузки (язык, Bluetooth-клавиатура, Wi-Fi, имя пользователя, новый пароль).

Вход по умолчанию: пользователь `skladen`, пароль `1234`. Пока пароль не сменён, SSH разрешён только из локальных сетей.

Если `fastboot reboot` зависает, удерживайте Питание около 10 секунд. Прошивки Qualcomm и Xiaomi мы не распространяем: они извлекаются на самом телефоне.

### Остальные файлы

- `linux-image-7.2-sdm845_*.deb`, `linux-headers-7.2-sdm845_*.deb` — ядро.
- `skladenos-*.deb` — пакеты. Они же лежат в подписанном apt-репозитории **garmon**: https://mitya-labs.github.io/apt
- `ebbg-MANIFEST.txt` — пакеты внутри образа; `SHA256SUMS` — контрольные суммы файлов релиза.
- `ebbg-FLASH.txt` — заметки о сборке для разработчиков (ссылаются на скрипты из репозитория).

Подробнее: https://mitya-labs.github.io/skladenos/ · исходники и сборка с нуля: https://github.com/mitya-labs/skladenos
