#!/bin/bash
# Run inside the native Pixel RAM Arch root after pixel-weston-start.sh.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-drm11-* ]]
[[ -S /run/user/0/wayland-pixel ]]
if [[ ! -c /dev/uinput ]]; then
    insmod /root/pixel_uinput.ko
fi
if ! pgrep -f '^/usr/local/bin/pixel-input-bridge$' >/dev/null; then
    nohup /usr/local/bin/pixel-input-bridge >/run/pixel-input.log 2>&1 </dev/null &
fi
cat >/root/pixel-terminal.sh <<'EOF'
#!/bin/bash
printf '\nNative Arch Linux ARM\nPixel 7 Pro | Wayland + software display\n\n'
printf 'Development session in RAM. Files disappear on reboot.\n\n'
exec /bin/bash
EOF
chmod 700 /root/pixel-terminal.sh
if ! pgrep -x weston-terminal >/dev/null; then
    nohup env XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-pixel \
        weston-terminal --maximized --font='DejaVu Sans Mono' --font-size=12 \
        --shell=/root/pixel-terminal.sh >/run/terminal.log 2>&1 </dev/null &
fi
