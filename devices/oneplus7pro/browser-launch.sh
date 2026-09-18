#!/usr/bin/env bash
# Root-session compatibility adapter. Install only after display access approval.
# Chromium retains its packaged setuid and renderer sandboxes.
set -euo pipefail
(( EUID == 0 )) || { echo 'This adapter is for the root bring-up session.' >&2; exit 1; }
browser_user=mobile-browser
browser_uid=$(id -u "$browser_user")
browser_gid=$(id -g "$browser_user")
browser_home=$(getent passwd "$browser_user" | cut -d: -f6)
session_runtime=${XDG_RUNTIME_DIR:-/run/user/0}
display=${WAYLAND_DISPLAY:?Launch from the Wayland desktop}
case $display in /*) display_socket=$display ;; *) display_socket=$session_runtime/$display ;; esac
[[ -S $display_socket ]] || { echo 'Wayland display is unavailable.' >&2; exit 1; }
browser_runtime=/run/user/$browser_uid
install -d -m700 -o "$browser_uid" -g "$browser_gid" "$browser_runtime"
# /dev/shm is created mode 0755 by the frozen bring-up initramfs.
chmod 1777 /dev/shm
# Traverse the compositor runtime directory, with access only to its display
# socket. Do not grant access to the root session bus or Hyprland IPC sockets.
setfacl -m "u:$browser_user:x" "$(dirname "$display_socket")"
setfacl -m "u:$browser_user:rw" "$display_socket"
audio_env=()
if [[ -S "$session_runtime/pulse/native" ]]; then
    # Share the audio protocol socket only, not the root session bus or general
    # PipeWire socket. This bridge goes away with the future standard-user session.
    setfacl -m "u:$browser_user:x" "$session_runtime/pulse"
    setfacl -m "u:$browser_user:rw" "$session_runtime/pulse/native"
    audio_env+=("PULSE_SERVER=unix:$session_runtime/pulse/native")
fi
cd "$browser_home"
exec runuser -u "$browser_user" -- env -i \
    HOME="$browser_home" USER="$browser_user" LOGNAME="$browser_user" \
    PATH=/usr/local/bin:/usr/bin LANG="${LANG:-C.UTF-8}" \
    XDG_RUNTIME_DIR="$browser_runtime" WAYLAND_DISPLAY="$display_socket" \
    "${audio_env[@]}" \
    dbus-run-session -- /usr/bin/chromium --ozone-platform=wayland --no-first-run "$@"
