# build/image — сборка прошиваемого образа skladenOS

`build/image/build.sh check` — проверка предпосылок (секунды, безопасно). `build/image/build.sh build [метка]` — полная сборка (~25-40 мин, Docker `--privileged`, ~25 ГБ в Docker-VM).

Вход: официальный rootfs Mobian (`images/mobian/…rootfs.img`), `out/packages/skladenos-*.deb`, `out/kernel/linux-image-7.2-sdm845_*.deb`.
Выход: `out/image/<метка>/` с `boot.img` (cmdline с `rw`), `userdata.simg.zst`, `SHA256SUMS`, `FLASH.txt`, `MANIFEST.txt`; симлинк `flash -> .`, поэтому
`scripts/snapshot-flash out/image/<метка>` прошивает без изменений (стирает телефон!). Лог сборки — `logs/image-build-<метка>.log`.

Шаги: simg2img → копия в каталог (loop-mount) → chroot (`chroot-stage.sh`: hold версий, ядро 7.2 + skladenos-* + sxmo-utils/jq/sudo/swaybg/network-manager из репозиториев, ядро 6.12 удаляется,
ssh host-ключи и machine-id сбрасываются, пароль mobian 1234, `skladenos-apply.service` на первой загрузке) → `boot.img` через mkbootimg (vmlinuz + dtb beryllium-<ebbg|tianma> + новый initrd +
cmdline оригинала Mobian) → `mke2fs -d` с тем же UUID корня → `e2fsck` → `img2simg` → zstd. В образ не кладутся: прошивки Qualcomm (`droid-juicer` на телефоне; первая загрузка перезагрузит телефон один раз), часовой пояс, личные данные.
Переменные: `VARIANT=ebbg|tianma`, `SSH=1|0`, `EXTRA_PKGS`, `FORCE=1` (при идущей сборке ядра). Не запускать `build`, пока собирается ядро (контейнер `skladenos-kbuild`).
