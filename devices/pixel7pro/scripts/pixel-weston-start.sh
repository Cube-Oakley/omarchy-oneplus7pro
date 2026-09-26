#!/bin/bash
# Temporary native display test inside the Pixel's RAM-only Arch chroot.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-drm11-* ]]
mkdir -p /run/user/0 /run/udev
chmod 700 /run/user/0
if ! pgrep -x systemd-udevd >/dev/null; then
    /usr/lib/systemd/systemd-udevd --daemon
fi
SYSTEMD_IN_CHROOT=0 udevadm trigger --subsystem-match=drm --action=add
SYSTEMD_IN_CHROOT=0 udevadm settle --timeout=10
if ! pgrep -x seatd >/dev/null; then
    nohup env SEATD_VTBOUND=0 seatd >/run/seatd.log 2>&1 </dev/null &
fi
for n in {1..30}; do [[ -S /run/seatd.sock ]] && break; sleep 0.1; done
[[ -S /run/seatd.sock ]]
cat >/root/weston-pixel.ini <<'EOF'
[core]
require-input=false
idle-time=0

[output]
name=DSI-1
mode=current
scale=3

[shell]
locking=false
background-color=0xff18202a
panel-position=top

[terminal]
font-size=10
EOF
pkill -x pixel-kms-test || true
nohup env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=seatd SEATD_SOCK=/run/seatd.sock \
    weston --backend=drm --renderer=pixman --drm-device=card0 \
    --continue-without-input --idle-time=0 --socket=wayland-pixel \
    --config=/root/weston-pixel.ini --log=/run/weston.log \
    >/run/weston-stdout.log 2>&1 </dev/null &
echo "WESTON_PID=$!"
