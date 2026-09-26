#!/usr/bin/env bash
# Build-only: IPA v4.1 (patched) and rmnet modules for the #188 native5 tree,
# plus the boot-DTB overlay. Deploys nothing; see README.md for the flash test.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../../../.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/ipa-module"
OUT="$ROOT/out/cellular/ipa"
SRC="$ROOT/kernel/radio/ipa"
RADIO_SYMVERS="$ROOT/.work/native5-radio-modules/remoteproc/Module.symvers"
rm -rf "$WORK"
mkdir -p "$WORK/drivers/net/ethernet/qualcomm" "$WORK/Documentation/devicetree/bindings/net" "$OUT"
copy() {
    rsync -a --exclude '*.o' --exclude '*.cmd' --exclude '.*' --exclude '*.ko' \
        --exclude '*.mod' --exclude '*.mod.c' --exclude 'modules.order' "$1" "$2"
}
copy "$KERNEL/drivers/net/ipa" "$WORK/drivers/net/"
copy "$KERNEL/drivers/net/ethernet/qualcomm/rmnet" "$WORK/drivers/net/ethernet/qualcomm/"
cp "$KERNEL/Documentation/devicetree/bindings/net/qcom,ipa.yaml" \
    "$WORK/Documentation/devicetree/bindings/net/"
for patch in "$SRC"/0*.patch; do
    patch -s -d "$WORK" -p1 < "$patch"
done
for dir in drivers/net/ipa drivers/net/ethernet/qualcomm/rmnet; do
    make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/$dir" \
        KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $RADIO_SYMVERS" modules
done
cp "$WORK/drivers/net/ipa/ipa.ko" "$WORK/drivers/net/ethernet/qualcomm/rmnet/rmnet.ko" "$OUT/"
# Plain dtc, like build_native_display.sh's NATIVE_EXTRA_DTS.
dtc -@ -q -I dts -O dtb "$SRC/guacamole-ipa.dts" -o "$OUT/guacamole-ipa.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/merged-check.dtb" "$OUT/guacamole-ipa.dtbo"
(cd "$OUT" && sha256sum ipa.ko rmnet.ko guacamole-ipa.dtbo merged-check.dtb > SHA256SUMS)
