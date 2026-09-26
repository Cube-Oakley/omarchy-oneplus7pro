#!/usr/bin/env bash
# Build native2 in the prepared isolated tree. Never flashes a device.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${NATIVE_KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-native}"
OUT="${NATIVE_OUTPUT:-$ROOT/out/native-display-test}"
RAMROOT="${NATIVE_RAMROOT:-$ROOT/.work/codex-native-initramfs}"
BASE="$ROOT/out/checkpoints/20260916-touch1/embedded.dtb"
RESTORE_RAMDISK="$ROOT/out/cpu-test/restore-ramdisk.gz"
TEST_NAME="${NATIVE_TEST_NAME:-native2}"
case "$TEST_NAME" in
    native[0-9]) ;;
    *) echo 'NATIVE_TEST_NAME must be native1 through native9' >&2; exit 1 ;;
esac
for file in "$BASE" "$RESTORE_RAMDISK" "$SRC/.config" \
    "$SRC/drivers/gpu/drm/panel/panel-samsung-oneplus-dsc.c"; do
    test -s "$file" || { echo "Missing prepared input: $file" >&2; exit 1; }
done
grep -q 'config DRM_PANEL_SAMSUNG_ONEPLUS_DSC' "$SRC/drivers/gpu/drm/panel/Kconfig"
if grep -q 'bringup_halt_leftover_mdp' "$SRC/arch/arm64/kernel/bringup_usb.c"; then
    echo 'Isolated source still contains the old DPU register workaround' >&2
    exit 1
fi
mkdir -p "$OUT" "$RAMROOT"
dtc -@ -I dts -O dtb \
    "$ROOT/kernel/display/guacamole-native-panel.dts" \
    -o "$OUT/guacamole-native-panel.dtbo"
fdtoverlay -i "$BASE" -o "$OUT/$TEST_NAME.dtb" "$OUT/guacamole-native-panel.dtbo"
if [[ -n ${NATIVE_EXTRA_DTS:-} ]]; then
    dtc -@ -I dts -O dtb "$NATIVE_EXTRA_DTS" -o "$OUT/extra.dtbo"
    fdtoverlay -i "$OUT/$TEST_NAME.dtb" -o "$OUT/extra-merged.dtb" "$OUT/extra.dtbo"
    cp "$OUT/extra-merged.dtb" "$OUT/$TEST_NAME.dtb"
fi
BOOT_ARGS="$(fdtget "$BASE" /chosen bootargs) bringup_usb.dpu=1 drm_kms_helper.fbdev_emulation=0"
fdtput -t s "$OUT/$TEST_NAME.dtb" /chosen bootargs "$BOOT_ARGS"
cp "$OUT/$TEST_NAME.dtb" "$SRC/bringup-guacamole.dtb"

"$SRC/scripts/config" --file "$SRC/.config" \
    --set-str LOCALVERSION "-sm8150-codex-$TEST_NAME" \
    --enable DRM_PANEL_SAMSUNG_ONEPLUS_DSC --enable SECURITY_LANDLOCK
make -C "$SRC" ARCH=arm64 LLVM=1 olddefconfig modules_prepare
KERNEL_TREE="$SRC" TOUCH_WORK="${NATIVE_TOUCH_WORK:-$ROOT/.work/native-touch-test}" \
    TOUCH_OUT="$OUT/touch" bash "$ROOT/scripts/build_touch_test.sh"

cp -a "$ROOT/.work/codex-touch-initramfs/." "$RAMROOT/"
install -m 755 "$ROOT/scripts/initramfs/init-native" "$RAMROOT/init"
install -m 755 "$ROOT/scripts/initramfs/start-usb-services.sh" "$RAMROOT/hypr/"
install -m 755 "$ROOT/scripts/initramfs/run-hypr-native.sh" \
    "$ROOT/scripts/initramfs/start-native-desktop.sh" "$RAMROOT/hypr/"
install -m 644 "$OUT/touch/evdev.ko" "$OUT/touch/s6sy761.ko" \
    "$OUT/touch/touch_overlay.ko" "$RAMROOT/hypr/touch/"
if [[ ${NATIVE_POWER_SUPPORT:-0} == 1 ]]; then
    test -s "$SRC/drivers/power/supply/qcom_smbx_mobile.h"
    KERNEL_TREE="$SRC" POWER_OUT="$OUT/power" bash "$ROOT/scripts/build_power_support.sh"
    mkdir -p "$RAMROOT/hypr/power"
    install -m644 "$OUT/power/power_support.ko" "$RAMROOT/hypr/power/"
    install -m755 "$ROOT/scripts/initramfs/start-power.sh" "$RAMROOT/hypr/"
fi
python3 - "$RAMROOT" "$SRC/bringup.cpio" <<'PY'
from pathlib import Path
import subprocess, sys
root, archive = map(Path, sys.argv[1:])
paths = ['.'] + [str(p.relative_to(root)) for p in sorted(root.rglob('*'))]
with archive.open('wb') as dest:
    subprocess.run(['cpio', '--null', '-o', '-H', 'newc', '--owner=0:0'],
                   cwd=root, input=('\0'.join(paths) + '\0').encode(),
                   stdout=dest, check=True)
PY
make -C "$SRC" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" Image
BOOT_CMDLINE="$BOOT_ARGS" bash "$ROOT/scripts/pack_hdr2_boot.sh" \
    "$SRC/arch/arm64/boot/Image" "$RESTORE_RAMDISK" \
    "$OUT/$TEST_NAME.dtb" "$OUT/boot-$TEST_NAME.img"
cp "$SRC/.config" "$OUT/$TEST_NAME.config"
sha256sum "$OUT/boot-$TEST_NAME.img" "$OUT/$TEST_NAME.dtb" "$OUT/$TEST_NAME.config" \
    > "$OUT/$TEST_NAME.sha256"
cat "$OUT/$TEST_NAME.sha256"
