#!/usr/bin/env bash
# Выполняется ВНУТРИ контейнера kbuild-sdm845. /src — том с деревом, /gitsrc — .git с Мака (ro),
# /patches — patches/pmi8998-typec, /kb — scripts/kbuild, /out — images/kernels/pmi8998.
# PD=1: дополнительно /patches/pd/*.diff (TCPM-бэкенд PMI8998 + DT), собирается qcom_pmic_tcpm.ko, результат в /out/pd/.
set -euo pipefail
git config --global --add safe.directory /src
cd /src
if [ ! -d .git ]; then cp -a /gitsrc .git; fi
git checkout -q -f HEAD
git clean -qfdx
# 1) патчи Mobian (debian/patches/series), как в штатной сборке: иначе dtb отличается (пути прошивок, голос и т.д.)
while read -r f; do
  case "$f" in ''|\#*) continue;; esac
  patch -p1 -s --no-backup-if-mismatch < "debian/patches/$f" || { echo "FAIL mobian patch $f"; exit 1; }
done < debian/patches/series
# 2) наши патчи (taygoth v1 + beryllium)
for p in $(ls /patches/*.diff | grep -v 0006); do
  echo "apply $p"; patch -p1 -s --no-backup-if-mismatch -F3 < "$p" || { echo "FAIL $p"; exit 1; }
done
if [ "${PD:-0}" = 1 ]; then
  for p in /patches/pd/*.diff; do
    echo "apply $p"; patch -p1 -s --no-backup-if-mismatch -F3 < "$p" || { echo "FAIL $p"; exit 1; }
  done
fi
cp /kb/config-7.2-sdm845 .config
scripts/config --module TYPEC_QCOM_PMI8998
[ "${PD:-0}" = 1 ] && scripts/config --module TYPEC_TCPM --module TYPEC_QCOM_PMIC
make -j12 KERNELRELEASE=7.2-sdm845 olddefconfig modules_prepare
export KBUILD_MODPOST_WARN=1
if [ "${PD:-0}" = 1 ]; then
  make -j12 KERNELRELEASE=7.2-sdm845 W=1 \
    drivers/usb/typec/tcpm/qcom/qcom_pmic_tcpm.ko \
    qcom/sdm845-xiaomi-beryllium-ebbg.dtb qcom/sdm845-xiaomi-beryllium-tianma.dtb
  mkdir -p /out/pd
  cp drivers/usb/typec/tcpm/qcom/qcom_pmic_tcpm.ko arch/arm64/boot/dts/qcom/sdm845-xiaomi-beryllium-*.dtb /out/pd/
  modinfo /out/pd/qcom_pmic_tcpm.ko | grep -E 'vermagic|depends|alias'
  ls -la /out/pd
  exit 0
fi
make -j12 KERNELRELEASE=7.2-sdm845 \
  drivers/usb/typec/qcom_pmi8998_typec.ko \
  drivers/regulator/qcom_usb_vbus-regulator.ko \
  qcom/sdm845-xiaomi-beryllium-ebbg.dtb qcom/sdm845-xiaomi-beryllium-tianma.dtb
cp drivers/usb/typec/qcom_pmi8998_typec.ko drivers/regulator/qcom_usb_vbus-regulator.ko /out/
cp arch/arm64/boot/dts/qcom/sdm845-xiaomi-beryllium-*.dtb /out/
modinfo /out/qcom_pmi8998_typec.ko | grep -E 'vermagic|depends'
ls -la /out
