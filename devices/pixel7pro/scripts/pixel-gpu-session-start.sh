#!/bin/bash
# Isolated hardware-rendered session in the native Pixel root.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs || $(cat /etc/omarchy-mobile-pixel-root 2>/dev/null) == v1 ]]
case $(uname -r) in
    *-pixel-gpu15-*|*-pixel-display16-*|*-pixel-scanout17-*|*-pixel-panel18-*|*-pixel-panel19-*) ;;
    *) echo 'Expected a validated Pixel GPU kernel.' >&2; exit 1 ;;
esac
[[ -c /dev/dri/card0 && -c /dev/dri/renderD128 ]]
[[ -f /root/pixel-hyprland.lua && -x /root/pixel-gpu-render-test ]]
[[ -f /root/pixel-desktop-prepare.sh ]]
if pgrep -x Hyprland >/dev/null; then
    echo 'Hyprland already running; refusing a second instance.' >&2
    exit 1
fi
export LD_LIBRARY_PATH=/opt/pixel-mesa/lib
export GBM_BACKENDS_PATH=/opt/pixel-mesa/lib/gbm
export __EGL_VENDOR_LIBRARY_FILENAMES=/opt/pixel-mesa/share/glvnd/egl_vendor.d/50_mesa.json
unset GBM_ALWAYS_SOFTWARE LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
# Refuse to start the desktop if the isolated build cannot execute a shader.
timeout 20 /root/pixel-gpu-render-test /dev/dri/card0
mkdir -p /run/user/0 /run/udev
chmod 700 /run/user/0
if ! pgrep -x systemd-udevd >/dev/null; then
    /usr/lib/systemd/systemd-udevd --daemon
fi
SYSTEMD_IN_CHROOT=0 udevadm trigger --subsystem-match=drm --action=add
SYSTEMD_IN_CHROOT=0 udevadm trigger --subsystem-match=input --action=add
SYSTEMD_IN_CHROOT=0 udevadm settle --timeout=10
if ! pgrep -x seatd >/dev/null; then
    nohup env SEATD_VTBOUND=0 seatd >/run/seatd.log 2>&1 </dev/null &
fi
for n in {1..30}; do [[ -S /run/seatd.sock ]] && break; sleep 0.1; done
[[ -S /run/seatd.sock ]]
pkill -x weston || true
for n in {1..30}; do pgrep -x weston >/dev/null || break; sleep 0.1; done
! pgrep -x weston >/dev/null
export XDG_RUNTIME_DIR=/run/user/0 XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland LIBSEAT_BACKEND=seatd
export SEATD_SOCK=/run/seatd.sock AQ_DRM_DEVICES=/dev/dri/card0 AQ_NO_MODIFIERS=1
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export HYPRLAND_STARTED_VIA_WRAPPER=1
ulimit -c 0
nohup Hyprland --i-am-really-stupid -c /root/pixel-hyprland.lua \
    >/run/hyprland-gpu.log 2>&1 </dev/null &
hypr_pid=$!
for n in {1..150}; do
    kill -0 "$hypr_pid" || { cat /run/hyprland-gpu.log >&2; exit 1; }
    hypr_socket=$(hyprctl instances 2>/dev/null | awk -v wanted="$hypr_pid" \
        '$1 == "pid:" { pid=$2 } $1 == "wl" && pid == wanted { print $3 }')
    [[ -n "$hypr_socket" && -S "$XDG_RUNTIME_DIR/$hypr_socket" ]] && break
    sleep 0.1
done
[[ -n "$hypr_socket" && -S "$XDG_RUNTIME_DIR/$hypr_socket" ]]
export WAYLAND_DISPLAY="$hypr_socket" QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl
install -m 700 /root/pixel-desktop-prepare.sh /root/.config/omarchy-mobile/session-prepare
/root/.local/bin/omarchy-mobile-session launch
/root/.local/bin/omarchy-mobile-keyboard start
cat >/root/pixel-gpu-terminal.sh <<'TERMINAL'
#!/bin/bash
printf 'Native Arch Linux ARM\nPixel 7 Pro | Mali-G710 hardware rendering\n\n'
if [[ -f /etc/omarchy-mobile-pixel-root ]]; then
    printf 'Persistent Linux root on internal storage.\n\n'
else
    printf 'RAM development session; files disappear at reboot.\n\n'
fi
exec /bin/bash
TERMINAL
chmod 700 /root/pixel-gpu-terminal.sh
nohup env KITTY_MOBILE_TOUCH=1 kitty --title 'Pixel Mali-G710' /root/pixel-gpu-terminal.sh \
    >/run/kitty-gpu.log 2>&1 </dev/null &
echo "HYPRLAND_PID=$hypr_pid WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
