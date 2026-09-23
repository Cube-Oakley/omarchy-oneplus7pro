#!/usr/bin/env bash
# Build-only: the camera stack as modules for the running native5 kernel: the
# media core its .config selects as =m (mc, videodev, v4l2-async/fwnode,
# videobuf2), qcom-camss with the 7T Pro's SM8150 patches, the CCI I2C master
# and the Sony IMX586 main-camera driver. The phone has no module tree for this
# kernel. camcc and the RPMh hold are built separately into out/camera/power/.
# Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/camera-modules"
OUT="$ROOT/out/camera/modules"
SRC="$ROOT/devices/oneplus7pro/kernel/camera"
rm -rf "$WORK"
mkdir -p "$WORK/cci" "$WORK/imx586" "$OUT"
copy() {
    rsync -a --exclude '*.o' --exclude '*.cmd' --exclude '.*' --exclude '*.ko' \
        --exclude '*.mod' --exclude '*.mod.c' --exclude 'modules.order' \
        --exclude 'built-in.a' "$1" "$2"
}
build() {
    local dir=$1
    shift
    make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/$dir" \
        KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $*" modules
}
copy "$KERNEL/drivers/media/mc" "$WORK/"
copy "$KERNEL/drivers/media/v4l2-core" "$WORK/"
copy "$KERNEL/drivers/media/common/videobuf2" "$WORK/"
copy "$KERNEL/drivers/media/platform/qcom/camss" "$WORK/"
# v4l2-core holds eight =m modules; only these three are needed. videodev's
# object list is taken from the tree's Makefile so it follows the .config.
{
    awk '/^videodev-/{p=1} p{print} p && !/\\$/{p=0}' "$KERNEL/drivers/media/v4l2-core/Makefile"
    printf 'obj-m += videodev.o v4l2-async.o v4l2-fwnode.o\n'
} > "$WORK/v4l2-core/Makefile"
# videobuf2: CAMSS uses scatter-gather buffers, not dma-contig or vmalloc.
printf '%s\n' 'obj-m += videobuf2-common.o videobuf2-v4l2.o videobuf2-memops.o videobuf2-dma-sg.o' \
    'videobuf2-common-y := videobuf2-core.o frame_vector.o' \
    'videobuf2-common-$(CONFIG_TRACEPOINTS) += vb2-trace.o' > "$WORK/videobuf2/Makefile"
# SM8150 support from the 7T Pro (hotdog r181); see camss/README.md.
for patch in "$SRC"/camss/*.patch; do
    patch -d "$WORK/camss" -p6 --forward --no-backup-if-mismatch -s < "$patch"
done
cp "$KERNEL/drivers/i2c/busses/i2c-qcom-cci.c" "$WORK/cci/"
printf 'obj-m += i2c-qcom-cci.o\n' > "$WORK/cci/Makefile"
cp "$SRC/imx586.c" "$WORK/imx586/"
printf 'obj-m += imx586.o\n' > "$WORK/imx586/Makefile"
MC="$WORK/mc/Module.symvers"
V4L2="$WORK/v4l2-core/Module.symvers"
VB2="$WORK/videobuf2/Module.symvers"
build mc
build v4l2-core "$MC"
build videobuf2 "$MC $V4L2"
build camss "$MC $V4L2 $VB2"
build cci
build imx586 "$MC $V4L2"
rm -f "$OUT"/*.ko
cp "$WORK"/mc/mc.ko "$WORK"/v4l2-core/{videodev,v4l2-async,v4l2-fwnode}.ko \
    "$WORK"/videobuf2/{videobuf2-common,videobuf2-memops,videobuf2-v4l2,videobuf2-dma-sg}.ko \
    "$WORK"/camss/qcom-camss.ko "$WORK"/cci/i2c-qcom-cci.ko "$WORK"/imx586/imx586.ko "$OUT/"
# Load order for insmod (no depmod tree on the phone). camcc-sm8150 and the
# RPMh hold from out/camera/power/ go first; the camera overlay after these.
printf '%s\n' mc videodev v4l2-async v4l2-fwnode videobuf2-common videobuf2-memops \
    videobuf2-v4l2 videobuf2-dma-sg qcom-camss i2c-qcom-cci imx586 > "$OUT/load-order"
# Every module must match the running kernel and only need modules loaded
# before it in that order.
VERMAGIC="$(cat "$KERNEL/include/config/kernel.release") SMP preempt mod_unload aarch64"
loaded=" "
while read -r mod; do
    ko="$OUT/$mod.ko"
    [[ $(modinfo -F vermagic "$ko") == "$VERMAGIC" ]] || { echo "$mod: bad vermagic" >&2; exit 1; }
    for dep in $(modinfo -F depends "$ko" | tr ',-' ' _'); do
        [[ $loaded == *" $dep "* ]] || { echo "$mod needs $dep before it" >&2; exit 1; }
    done
    loaded+="${mod//-/_} "
done < "$OUT/load-order"
(cd "$OUT" && sha256sum ./*.ko load-order > SHA256SUMS)
