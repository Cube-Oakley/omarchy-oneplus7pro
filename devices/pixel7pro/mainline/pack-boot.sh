#!/usr/bin/env bash
# Pack a Pixel header-v4 boot.img (mainline Image.lz4, empty ramdisk)
# and init_boot.img (busybox + this init + rebootbl).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ML="$ROOT/mainline"
OUT="$ROOT/out/mainline"
IMG="$ML/linux/arch/arm64/boot/Image"
BB="$ROOT/ramdisk/busybox"
[ -x "$BB" ] || BB="$ROOT/out/ramdisk-usb/root/busybox"
RB="$ROOT/ramdisk/rebootbl"
CINIT="$ROOT/ramdisk/init"

mkdir -p "$OUT"
test -f "$IMG" || { echo "missing $IMG — build the kernel first"; exit 1; }
test -x "$BB" && test -x "$RB" && test -x "$CINIT"

lz4 -f -12 "$IMG" "$OUT/Image.lz4"
ls -lh "$OUT/Image.lz4"

# boot.img: kernel only (Pixel 7 GKI boot ramdisk is empty).
# rdinit on the boot.img cmdline is concatenated by the bootloader with
# vendor_boot's cmdline. Vendor ramdisk overwrites /init; /ourinit stays.
mkbootimg --header_version 4 \
  --kernel "$OUT/Image.lz4" \
  --cmdline "rdinit=/ourinit" \
  --output "$OUT/boot-mainline.img"
ls -lh "$OUT/boot-mainline.img"

# init_boot: same layout as the USB ramdisk (C init execs busybox sh /init.sh)
R="$OUT/initramfs-root"
rm -rf "$R"
mkdir -p "$R"
cp -a "$CINIT" "$R/init"
cp -a "$BB" "$R/busybox"
cp -a "$RB" "$R/rebootbl"
cp -a "$ML/init.sh" "$R/init.sh"
chmod 755 "$R/init" "$R/busybox" "$R/rebootbl" "$R/init.sh"

# C init expects /init.sh as busybox sh script after mounting.
( cd "$R" && find . -print0 | cpio --null -o -H newc ) > "$OUT/initramfs.cpio"
lz4 -f -12 "$OUT/initramfs.cpio" "$OUT/initramfs.cpio.lz4"

# unpack Evolution compact init_boot to steal header if needed
mkbootimg --header_version 4 \
  --ramdisk "$OUT/initramfs.cpio.lz4" \
  --output "$OUT/init_boot-mainline.img"
ls -lh "$OUT/boot-mainline.img" "$OUT/init_boot-mainline.img"
echo "flash: fastboot flash boot_a $OUT/boot-mainline.img && fastboot flash init_boot_a $OUT/init_boot-mainline.img && fastboot set_active a && fastboot reboot"
echo "restore: fastboot flash boot_a $ROOT/out/RESTORE-boot_a.img && fastboot flash init_boot_a $ROOT/out/RESTORE-init_boot-compact.img && fastboot set_active a && fastboot reboot"
echo "NEVER flash *_b. Slot B stays Evolution X."
