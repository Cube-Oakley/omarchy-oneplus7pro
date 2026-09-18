#!/usr/bin/env bash
# Use the isolated corrected tree. Never overwrite the native2 recovery build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.work/linux-sm8150-codex-power"
BASE="$ROOT/.work/linux-sm8150-codex-native"
PATCH="$ROOT/devices/oneplus7pro/kernel/power/native3-charger.patch"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$BASE" "$SRC"
fi
# Refuse an unexpected source instead of silently applying a partial patch.
if cmp -s "$BASE/drivers/power/supply/qcom_smbx.c" "$SRC/drivers/power/supply/qcom_smbx.c"; then
    patch --batch --fuzz=0 -d "$SRC" -p1 < "$PATCH"
else
    patch --batch --fuzz=0 --dry-run --reverse -d "$SRC" -p1 < "$PATCH"
fi
install -m644 "$ROOT/devices/oneplus7pro/kernel/power/qcom_smbx_mobile.h" \
    "$SRC/drivers/power/supply/qcom_smbx_mobile.h"
export NATIVE_KERNEL_TREE="$SRC"
export NATIVE_OUTPUT="$ROOT/out/power-desktop-test"
export NATIVE_RAMROOT="$ROOT/.work/codex-power-initramfs"
export NATIVE_TOUCH_WORK="$ROOT/.work/power-touch-test"
export NATIVE_TEST_NAME=native3 NATIVE_POWER_SUPPORT=1
exec bash "$ROOT/scripts/build_native_display.sh"
