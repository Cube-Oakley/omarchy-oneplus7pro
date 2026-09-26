#!/usr/bin/env bash
# Pack a no-PIE C /init + Magisk no-PIE busybox into init_boot.img.
# Does not flash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/ramdisk-usb"
BB="$ROOT/out/root-dump/magisk-bin/magisk-busybox"
CC=aarch64-linux-gnu-gcc
[[ -f "$BB" ]] || { echo "missing Magisk busybox at $BB (dump it first)"; exit 1; }
chmod +x "$BB"
command -v "$CC" >/dev/null || { echo "missing $CC"; exit 1; }

"$CC" -static -no-pie -Os -s -o "$ROOT/ramdisk/init.nopie" "$ROOT/ramdisk/init.c"
"$CC" -static -no-pie -Os -s -o "$ROOT/ramdisk/rebootbl" "$ROOT/ramdisk/rebootbl.c"

rm -rf "$OUT/root"
mkdir -p "$OUT/root"
cp "$BB" "$OUT/root/busybox"
cp "$ROOT/ramdisk/init.nopie" "$OUT/root/init"
cp "$ROOT/ramdisk/rebootbl" "$OUT/root/rebootbl"
INIT_SH="${INIT_SH:-$ROOT/ramdisk/init.sh}"
cp "$INIT_SH" "$OUT/root/init.sh"
echo "packed init.sh from $INIT_SH"
chmod 750 "$OUT/root/busybox" "$OUT/root/init" "$OUT/root/rebootbl" "$OUT/root/init.sh"

( cd "$OUT/root" && find . | cpio -o -H newc --quiet ) > "$OUT/ramdisk.cpio"
lz4 -l -f -12 "$OUT/ramdisk.cpio" "$OUT/ramdisk.legacy.lz4"
mkbootimg \
  --header_version 4 \
  --pagesize 4096 \
  --os_version 15.0.0 \
  --os_patch_level 2025-02 \
  --ramdisk "$OUT/ramdisk.legacy.lz4" \
  --output "$OUT/init_boot-usb.img"
ls -lh "$OUT/root" "$OUT/init_boot-usb.img"
file "$OUT/root/init" "$OUT/root/busybox" "$OUT/init_boot-usb.img"
echo "flash with: fastboot flash init_boot_a $OUT/init_boot-usb.img && fastboot flash init_boot_b $OUT/init_boot-usb.img && fastboot set_active a && fastboot reboot"
echo "restore with: $ROOT/scripts/restore-init-boot.sh"
