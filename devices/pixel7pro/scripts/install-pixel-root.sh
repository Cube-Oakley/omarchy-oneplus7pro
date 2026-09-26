#!/bin/bash
# Run INSIDE the prepared Arch RAM root. Destructive only with the explicit flag.
set -euo pipefail
[[ ${1:-} == --replace-android-data && $# == 1 ]] || {
    echo 'Usage: install-pixel-root.sh --replace-android-data (erases userdata)' >&2
    exit 2
}
[[ $EUID == 0 && $(uname -m) == aarch64 && $(stat -f -c %T /) == tmpfs ]]
grep -q 'pixel_test_seconds=0\b' /proc/cmdline
[[ $(tr '\0' '\n' </sys/firmware/devicetree/base/compatible | head -1) == 'google,GS201 CHEETAH' ]]
grep -qx 'PARTNAME=userdata' /sys/class/block/sda31/uevent
grep -qx 'PARTNAME=boot_a' /sys/class/block/sda10/uevent
grep -qx 'PARTNAME=init_boot_a' /sys/class/block/sda11/uevent
device=/dev/sda31
[[ $(blockdev --getsize64 "$device") == 245977141248 ]]
[[ -z $(findmnt -rn -S "$device") ]]
[[ -z $(ls -A /sys/class/block/sda31/holders) ]]
[[ $(blkid -s TYPE -o value "$device" || true) != ext4 ]]
[[ -x /root/pixel-gpu-session-start.sh && -x /root/pixel-gpu-render-test ]]
[[ -f /usr/local/lib/omarchy-mobile/pixel-boot.sh ]]
# Verify known partition reads before allowing the single destructive operation.
sha256sum -c <<'HASHES'
6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10  /dev/sda10
7e3f27da39717be9170ef982aa0bebf0e2806a66650520ad562843a1dc6a0117  /dev/sda11
HASHES
target=/mnt/pixel-root
mkdir -p "$target"
! mountpoint -q "$target"
echo 'Formatting verified userdata as the Linux root; Android user data is being erased.'
mkfs.ext4 -F -L omarchy-root -m 1 -N 1048576 \
    -E nodiscard,lazy_itable_init=1,lazy_journal_init=1 "$device"
mount -t ext4 "$device" "$target"
echo 'Checking filesystem writes and uncached readback before copying Arch.'
dd if=/dev/urandom of=/tmp/pixel-storage-test bs=1M count=16 status=none
expected=$(sha256sum /tmp/pixel-storage-test | cut -d' ' -f1)
cp /tmp/pixel-storage-test "$target/.storage-test"
sync -f "$target"
umount "$target"
mount -t ext4 "$device" "$target"
[[ $(sha256sum "$target/.storage-test" | cut -d' ' -f1) == "$expected" ]]
rm /tmp/pixel-storage-test "$target/.storage-test"
echo 'Copying the prepared Arch root to internal storage.'
tar --one-file-system --xattrs --acls --numeric-owner \
    --exclude=./mnt --exclude=./run --exclude=./dev --exclude=./proc \
    --exclude=./sys --exclude=./tmp -C / -cpf - . |
    tar --xattrs --acls --numeric-owner -C "$target" -xpf -
mkdir -p "$target"/{mnt,run,dev,proc,sys,tmp}
chmod 1777 "$target/tmp"
# Written last: boot refuses to use a partially copied root without this marker.
sync -f "$target"
printf 'v1\n' >"$target/etc/omarchy-mobile-pixel-root"
sync -f "$target"
echo 'Root copy complete. Verify after unmount/remount before changing the boot slot.'
df -h "$target"
