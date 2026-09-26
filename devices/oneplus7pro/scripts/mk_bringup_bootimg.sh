#!/usr/bin/env bash
# Build a no-rootfs mainline boot.img for guacamole: kernel 6.17 + DTB + USB shell ramdisk.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.work"
OUT="$ROOT/out"
KPKG="$WORK/kernel-pkg"
BB="$WORK/alpine/bb/bin/busybox.static"
STAGE="$WORK/initramfs-root"
IMG="$OUT/boot-guacamole-mainline-bringup.img"

mkdir -p "$OUT" "$STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,sbin,proc,sys,dev,tmp,run,etc}

cp "$BB" "$STAGE/bin/busybox"
chmod 755 "$STAGE/bin/busybox"
# Do not execute the aarch64 binary on the host; just link applets.
for a in sh ash mount umount mkdir ls cat echo sleep ln ip ifconfig nc \
         getty setsid dmesg reboot poweroff mknod mdev insmod modprobe \
         head tr kill ps; do
  ln -sf busybox "$STAGE/bin/$a"
done
cp "$ROOT/scripts/initramfs/init" "$STAGE/init"
chmod 755 "$STAGE/init"
printf 'root::0:0:root:/:/bin/sh\n' > "$STAGE/etc/passwd"
printf 'root:x:0:\n' > "$STAGE/etc/group"

# cpio/gzip ramdisk
RAMDISK="$WORK/initramfs.cpio.gz"
( cd "$STAGE" && find . | cpio -o -H newc --quiet ) | gzip -9 > "$RAMDISK"

# Image.gz + guacamole DTB (deviceinfo_append_dtb=true)
KERNEL_DTB="$WORK/vmlinuz-guacamole-dtb"
cat "$KPKG/boot/vmlinuz" "$KPKG/boot/dtbs/qcom/sm8150-oneplus-guacamole.dtb" > "$KERNEL_DTB"

CMDLINE="console=tty0 console=ttyMSM0,115200n8 clk_ignore_unused pd_ignore_unused ignore_loglevel"

mkbootimg \
  --header_version 0 \
  --kernel "$KERNEL_DTB" \
  --ramdisk "$RAMDISK" \
  --pagesize 0x00001000 \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 \
  --tags_offset 0x00000100 \
  --board '' \
  --cmdline "$CMDLINE" \
  --output "$IMG"

ls -lh "$IMG" "$RAMDISK" "$KERNEL_DTB"
file "$IMG"
echo "boot image: $IMG"
