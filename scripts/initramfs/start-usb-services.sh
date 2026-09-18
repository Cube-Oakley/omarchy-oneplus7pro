#!/bin/busybox sh
# Invoke from the initramfs after Arch's /dev, /proc, /sys and /run are mounted.
# Keys/config are provisioned separately on persistent Arch storage.
set -eu
ROOT=/newroot
# devtmpfs lacks these standard userspace links in this minimal initramfs.
# Bash process substitution (including pacman-key) requires /dev/fd.
for pair in fd:/proc/self/fd stdin:/proc/self/fd/0 stdout:/proc/self/fd/1 stderr:/proc/self/fd/2; do
    name=${pair%%:*}
    target=${pair#*:}
    if [ ! -e "/dev/$name" ] && [ ! -L "/dev/$name" ]; then
        busybox ln -s "$target" "/dev/$name"
    fi
done
busybox ip route replace default via 172.16.42.2 dev usb0 metric 2000
# Retire the old preferred USB default, retaining the directly connected SSH route.
busybox ip route del default via 172.16.42.2 dev usb0 metric 0 2>/dev/null || true
# Arch's resolver is a symlink into /run; systemd-resolved is not running yet.
busybox mkdir -p "$ROOT/run/systemd/resolve"
if ! busybox pidof NetworkManager >/dev/null; then
    printf 'nameserver 172.16.42.2\n' > "$ROOT/run/systemd/resolve/resolv.conf"
fi
# Optional device-specific radio setup runs after storage is mounted and waits
# for the power driver. It never delays SSH or the desktop, and is opt-in.
if [ -x "$ROOT/usr/local/sbin/guacamole-radio-start" ] &&
   [ -f "$ROOT/root/radio-bringup/autostart-enabled" ]; then
    busybox chroot "$ROOT" /usr/bin/nohup /usr/local/sbin/guacamole-radio-start \
        >> "$ROOT/root/radio-bringup/logs/startup.log" 2>&1 < /dev/null &
fi
if [ ! -s "$ROOT/etc/ssh/ssh_host_ed25519_key" ] ||
   [ ! -s "$ROOT/root/.ssh/authorized_keys" ] ||
   [ ! -f "$ROOT/etc/ssh/sshd_config.usb" ]; then
    echo 'USB routing/DNS ready; provision SSH keys/config before starting sshd.'
    exit 0
fi
busybox chroot "$ROOT" /usr/bin/sshd -t -f /etc/ssh/sshd_config.usb
if [ -s "$ROOT/run/sshd-usb.pid" ]; then
    pid=$(busybox cat "$ROOT/run/sshd-usb.pid")
    if [ -r "/proc/$pid/comm" ] && [ "$(busybox cat "/proc/$pid/comm")" = sshd ]; then
        echo USB_SSH_ALREADY_RUNNING
        exit 0
    fi
fi
busybox chroot "$ROOT" /usr/bin/sshd -f /etc/ssh/sshd_config.usb -E /root/sshd-usb.log
echo USB_SSH_READY
