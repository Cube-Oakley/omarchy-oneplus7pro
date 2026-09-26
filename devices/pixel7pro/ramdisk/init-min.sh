#!/busybox sh
# Minimal: prove /init → busybox → reboot bootloader. No modules, no persist.
BB=/busybox
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

$BB mkdir -p /proc /sys /dev /tmp /bin /sys/fs/selinux
$BB mount -t proc proc /proc
$BB mount -t sysfs sysfs /sys
$BB mount -t tmpfs tmpfs /dev 2>/dev/null || true
$BB mknod /dev/null c 1 3 2>/dev/null || true
$BB mknod /dev/kmsg c 1 11 2>/dev/null || true
$BB mount -t selinuxfs selinuxfs /sys/fs/selinux 2>/dev/null || true
$BB echo 0 > /sys/fs/selinux/enforce 2>/dev/null || true

k() { $BB echo "OMARCHY: $*" > /dev/kmsg 2>/dev/null; }

k "min init pid=$$"
k "uptime=$($BB cat /proc/uptime)"
k "rebootbl exists=$($BB test -x /rebootbl && echo y || echo n)"
k "calling rebootbl"
exec /rebootbl
k "rebootbl returned"
while :; do :; done
