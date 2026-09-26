#!/bin/busybox sh
# Hyprland's early simpledrm alias must not hide the later Adreno render node.
# Keep existing compositor fds intact; atomically replace only our known alias.
set -eu

attempt=0
while [ "$attempt" -lt 180 ]; do
    for sysnode in /sys/class/drm/renderD*; do
        [ -f "$sysnode/dev" ] || continue
        driver=$(busybox readlink "$sysnode/device/driver" || true)
        case "$driver" in */adreno) ;; *) continue ;; esac
        node=/dev/dri/${sysnode##*/}
        if [ -L "$node" ]; then
            [ "$(busybox readlink "$node")" = card0 ] || {
                echo "render-node: refusing unexpected symlink $node" >&2
                exit 1
            }
            IFS=: read -r dev_major dev_minor < "$sysnode/dev"
            temp="${node}.new"
            [ ! -e "$temp" ] && [ ! -L "$temp" ] || exit 1
            [ ! -e "${node}.simpledrm" ] && [ ! -L "${node}.simpledrm" ] || exit 1
            busybox ln -s card0 "${node}.simpledrm"
            busybox mknod -m 600 "$temp" c "$dev_major" "$dev_minor"
            busybox mv "$temp" "$node"
            echo "render-node: restored $node ($dev_major:$dev_minor)" > /dev/kmsg
        fi
        [ -c "$node" ] || exit 1
        exit 0
    done
    attempt=$((attempt + 1))
    busybox sleep 1
done
echo "render-node: timed out waiting for Adreno" >&2
exit 1
