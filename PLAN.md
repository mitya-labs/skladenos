# План

> Актуальный статус — `SUMMARY.md`, подробности — `STATE.md`, восстановление с нуля — `RESTORE.md`.
> Старый план поиска причин сбоев pmOS (разделы 0–6, журнал, находки 02.10) снят 05.10 и вынесен в `PLAN-archive-pmos.md`.

## Потом: USB-host (OTG, хаб Baseus с PD-портом, без своего БП)

Известно (STATE п.64): на ядре 7.2 `dr_mode = "peripheral"` у `usb@a600000`; DWC3 `DUAL_ROLE=y`, модули `xhci-hcd`, `usb-storage`; `/sys/class/typec` пуст; VBUS порта не питается (регулятор PMI8998 не настроен), поэтому хаб надо питать снаружи.

- [x] Этап 1. Разведка (выполнено, STATE п.74: `mode` не переключается, нужен DT) (~5 мин, без изменений): есть ли `/sys/kernel/debug/usb/a600000.usb/mode` и принимает ли `host`; `dmesg` про VBUS/PMI8998.
- [x] Этап 2 (образ `images/kernels/boot-7.2-host.img` собран, STATE п.75; не прошит). Принудительный хост через DT: взять `sdm845-xiaomi-beryllium-ebbg.dtb` из `linux-image-7.2-sdm845`, `dtc -I dtb -O dts`, `dr_mode = "host"`, обратно в dtb, собрать `boot.img` как делает `zz-qcom-bootimg` (cmdline с `rw`!). Откат: `fastboot flash boot images/kernels/boot-*-known-good.img`.
- [x] Этап 3 (работает после переподключения, STATE п.77). Проверка железа: телефон → хаб, **зарядник на PD-порт хаба** (БП 5 В и выше), в хаб клавиатура или флешка; `lsusb`, `dmesg | grep -i xhci`, `lsblk`. Заряжается ли телефон от хаба (гипотеза: да, если на CC стоит Rp).
- На время теста пропадает USB-сеть с Маком (`10.66.0.1`): SSH по Wi‑Fi; fastboot всегда доступен (Vol− + Power).
- [ ] Если порт не питает хаб/не видит устройства: апстрим-патч регулятора VBUS PMI8998 в `qcom_usb_vbus-regulator`, затем Type-C роли PMI8998 рядом с `qcom_pmic_typec_port.c`; согласовать в `#sdm845`.

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
