#!/usr/bin/env bash
# Radio preflight image: guard memory at boot; radio starts only in a live test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.work/linux-sm8150-codex-wifi"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$ROOT/.work/linux-sm8150-codex-power" "$SRC"
fi
test -s "$SRC/drivers/power/supply/qcom_smbx_mobile.h"
patch --batch --fuzz=0 --dry-run --reverse -d "$SRC" -p1 \
    < "$ROOT/kernel/power/native3-charger.patch"
cmp "$ROOT/kernel/power/qcom_smbx_mobile.h" \
    "$SRC/drivers/power/supply/qcom_smbx_mobile.h"
export NATIVE_KERNEL_TREE="$SRC"
export NATIVE_OUTPUT="$ROOT/out/wifi-desktop-test"
export NATIVE_RAMROOT="$ROOT/.work/codex-wifi-initramfs"
export NATIVE_TOUCH_WORK="$ROOT/.work/wifi-touch-test"
export POWER_WORK="$ROOT/.work/wifi-power-support"
export NATIVE_TEST_NAME=native4 NATIVE_POWER_SUPPORT=1
export NATIVE_EXTRA_DTS="$ROOT/kernel/power/guacamole-radio-guards.dts"
exec bash "$ROOT/scripts/build_native_display.sh"
