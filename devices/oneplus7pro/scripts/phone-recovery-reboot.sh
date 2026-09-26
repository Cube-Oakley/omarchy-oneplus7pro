#!/bin/sh
# Run only in this phone's outer BusyBox initramfs, never inside Arch/the host.
set -eu
BB=/bin/busybox
case "$($BB uname -r)" in *-sm8150-codex-native5-*) ;; *) exit 1 ;; esac
[ "$($BB readlink /proc/1/exe)" = /bin/busybox ]
$BB grep -q '^/dev/sda19 /newroot ext4 ' /proc/mounts
echo 'RECOVERY_REBOOT_BEGIN'
for signal in TERM KILL; do
    for root in /proc/[0-9]*/root; do
        [ "$($BB readlink "$root" 2>/dev/null || true)" = /newroot ] || continue
        pid=${root%/root}; pid=${pid##*/}
        $BB kill -"$signal" "$pid" 2>/dev/null || true
    done
    $BB sleep 2
done
$BB sync
# The writable firmware bind mount otherwise prevents ext4's read-only remount.
if $BB grep -q '^/dev/sda19 /lib/firmware ext4 ' /proc/mounts; then
    $BB umount /lib/firmware
fi
# A process still exiting can hold the filesystem for a moment after KILL.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    $BB mount -o remount,ro /newroot && break
    echo "READ_ONLY_REMOUNT_RETRY $attempt"
    $BB sync
    $BB sleep 1
done
$BB grep '^/dev/sda19 /newroot ext4 ro,' /proc/mounts
echo 'STORAGE_READ_ONLY_REBOOT_REQUEST'
$BB reboot -f
