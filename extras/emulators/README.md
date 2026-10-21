# Эмуляторы (необязательно)

Не входят в образ skladenOS — ставятся из репо одной командой с Мака (телефон подключён по USB, `PHONE_HOST` по умолчанию `10.66.0.1`).

| Эмулятор | Источник | Что нужно от вас |
|---|---|---|
| HP Jornada 720 | QEMU с патчами Jornada 720 (форк `DmitriiTrifonov/qemu-jornada720`) | свой ROM (`JORNADA_ROM`, по умолчанию `~/jorn720/jornada720.bin`) |
| Psion 5mx | WindEmu, ветка `pmos` (форк `DmitriiTrifonov/WindEmu`) | свой ROM (`PSION_ROM`, по умолчанию `~/Downloads/5mx_v1.05(260)_eng.bin`) |
| PumpkinOS | форк `DmitriiTrifonov/PumpkinOS` (ветка `pmOS`, Wayland) | рабочая копия на Маке (`PUMPKIN_SRC`, по умолчанию `~/Developer/pmOS/PumpkinOS`), см. `pumpkin-sync.sh` |

ROM-ы в репозиторий не входят и не распространяются: берите свои.

## Установка

```sh
extras/emulators/install          # 1) сборка на телефоне (в фоне, ~40-90 мин), 2) пункты меню SXMO Scripts
```

По шагам:
1. `extras/emulators/build-emulators.sh` — зависимости (apt), ROM, сборка QEMU + PumpkinOS + WindEmu в фоне. Следить: `scripts/phone-ssh 'cat ~/logs/emulators-build.status; tail -5 ~/logs/emulators-build.log'` (готово, когда в `status` появится `FINISHED`).
2. `extras/emulators/emulators-install` — лаунчеры и подменю в SXMO Scripts (HP Jornada 720, Psion 5mx, PumpkinOS). Нужен хук меню с подпапками: его ставит базовый `scripts/powerplan-install`.
3. `extras/emulators/rebuild-emulators.sh` — повторная сборка (докомпилирует), `extras/emulators/pumpkin-sync.sh` — залить PumpkinOS с Мака и собрать.

## Удаление

На телефоне: `rm -rf ~/Developer/qemu-jornada720 ~/Developer/WindEmu ~/PumpkinOS ~/roms ~/.config/sxmo/userscripts/{HP_Jornada_720,Psion_5mx,pumpkinos}` и `sudo apt purge qtwayland5` (если не нужен). Ядро системы от эмуляторов не зависит.
