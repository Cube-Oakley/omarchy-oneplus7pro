#!/usr/bin/env bash
# Pack stub-DT vendor_kernel_boot + slim mainline boot.img.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/mainline"
K="$ROOT/mainline/linux"
DUMP="$ROOT/out/device-slot-a"
mkdir -p "$OUT" "$OUT/builtin-root/sbin" "$OUT/builtin-root/bin"

aarch64-linux-gnu-gcc -static -no-pie -Os -s \
  -o "$ROOT/ramdisk/pid1-banner" "$ROOT/ramdisk/pid1-banner.c"
for p in init ourinit sbin/init bin/sh; do
  cp -a "$ROOT/ramdisk/pid1-banner" "$OUT/builtin-root/$p"
  chmod 755 "$OUT/builtin-root/$p"
done

dtc -I dts -O dtb -o "$OUT/gs201-cheetah-stub.dtb" \
  "$ROOT/mainline/dts/gs201-cheetah-stub.dts"
# ABL image originally concatenated two gs201 FDTs. Repeat the stub.
cat "$OUT/gs201-cheetah-stub.dtb" "$OUT/gs201-cheetah-stub.dtb" \
  > "$OUT/gs201-cheetah-stub.concat.dtb"

mkdir -p /tmp/vkb-pack
unpack_bootimg --boot_img "$DUMP/vendor_kernel_boot.img" --out /tmp/vkb-pack >/dev/null
mkbootimg --header_version 4 --pagesize 2048 \
  --base 0x10000000 \
  --dtb "$OUT/gs201-cheetah-stub.concat.dtb" \
  --dtb_offset 0x01f00000 \
  --vendor_ramdisk /tmp/vkb-pack/vendor_ramdisk00 \
  --vendor_boot "$OUT/vendor_kernel_boot-stub.img"

lz4 -f -12 "$K/arch/arm64/boot/Image" "$OUT/Image.lz4"
mkbootimg --header_version 4 \
  --kernel "$OUT/Image.lz4" \
  --cmdline "earlycon=exynos4210,mmio32,0x10A00000 ignore_loglevel initcall_debug fw_devlink=off clk_ignore_unused pd_ignore_unused ramoops.mem_address=0xf8800000 ramoops.mem_size=0x400000 ramoops.console_size=0x200000 ramoops.record_size=0x40000 printk.always_kmsg_dump=Y" \
  --output "$OUT/boot-mainline-stub.img"

ls -lh "$OUT/boot-mainline-stub.img" "$OUT/vendor_kernel_boot-stub.img" "$OUT/gs201-cheetah-stub.dtb"
echo "flash: boot_a + vendor_kernel_boot_a only. restore vendor_kernel_boot from $DUMP/vendor_kernel_boot.img"
