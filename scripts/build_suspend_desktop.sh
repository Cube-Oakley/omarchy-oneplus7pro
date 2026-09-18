#!/usr/bin/env bash
# Native5 preserves native4 radio memory and charger limits, adding tested
# touch resume, PM diagnostics, and the stock RTC alarm driver before PMIC probe.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/.work/linux-sm8150-codex-suspend"
if [[ ! -d $SRC ]]; then
    cp -a --reflink=auto "$ROOT/.work/linux-sm8150-codex-wifi" "$SRC"
fi
cmp "$ROOT/devices/oneplus7pro/kernel/power/qcom_smbx_mobile.h" \
    "$SRC/drivers/power/supply/qcom_smbx_mobile.h"
"$SRC/scripts/config" --file "$SRC/.config" --enable PM_DEBUG --enable RTC_DRV_PM8XXX
export NATIVE_KERNEL_TREE="$SRC"
export NATIVE_OUTPUT="$ROOT/out/suspend-desktop-test"
export NATIVE_RAMROOT="$ROOT/.work/codex-suspend-initramfs"
export NATIVE_TOUCH_WORK="$ROOT/.work/native5-touch-test"
export POWER_WORK="$ROOT/.work/native5-power-support"
export NATIVE_TEST_NAME=native5 NATIVE_POWER_SUPPORT=1 POWER_RTC_SUPPORT=1
export NATIVE_EXTRA_DTS="$ROOT/devices/oneplus7pro/kernel/power/guacamole-radio-guards.dts"
bash "$ROOT/scripts/build_native_display.sh"
KERNEL_TREE="$SRC" RADIO_KEY_ACK=1 RADIO_MODULE_WORK="$ROOT/.work/native5-radio-modules" \
    RADIO_MODULE_OUT="$NATIVE_OUTPUT/modules" bash "$ROOT/scripts/build_radio_modules.sh"
KERNEL_TREE="$SRC" RADIO_OUTPUT="$NATIVE_OUTPUT" RADIO_TEST_NAME=native5 \
    RADIO_OVERLAY_WORK="$ROOT/.work/native5-overlay" bash "$ROOT/scripts/build_radio_overlays.sh"
