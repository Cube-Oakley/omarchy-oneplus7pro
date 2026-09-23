#!/usr/bin/env bash
# Board Bluetooth start for the root/chroot session. Loads the WCN3990 stack
# once per boot (modules, the hsuart0 alias shim, the UART13 overlay), gives
# the controller its stable address and runs bluetoothd. Safe to run again:
# the shell's Bluetooth toggle calls it (device.json "bluetoothStart") when
# no controller exists. Never rmmod hci_uart; its serdev remove path panicked
# on the 7T Pro. Reboot to unload. Details: docs/bluetooth-20260922.md.
set -euo pipefail
D=/root/bluetooth-bringup
M=$D/modules
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
exec 8>/run/guacamole-bluetooth.lock
flock -w 120 8
# bluetooth.ko links rfkill, which the radio startup loads for Wi-Fi; at boot
# both start from the desktop hook, so wait for it rather than race it.
for i in $(seq 1 240); do [[ -d /sys/module/rfkill ]] && break; sleep 0.5; done
[[ -d /sys/module/rfkill ]] || { echo 'rfkill never loaded; is the radio startup running?' >&2; exit 1; }
if [[ ! -d /sys/module/guacamole_bluetooth ]]; then
    (cd "$M" && sha256sum -c --quiet SHA256SUMS)
    for f in crbtfw21.tlv crnv21.bin; do [[ -s /lib/firmware/updates/qca/$f ]]; done
    symbol() { awk -v s="$1" '$3 == s { print $1 }' /proc/kallsyms; }
    for m in $(cat "$M/load-order"); do
        # Kernel #190's boot DTB has the hsuart0 alias; older ones need the shim.
        if [[ $m == guacamole_bluetooth && ! -d /sys/module/guacamole_hsuart_alias &&
              ! -e /sys/firmware/devicetree/base/aliases/hsuart0 ]]; then
            insmod "$M/guacamole_hsuart_alias.ko" aliases_lookup_addr=0x"$(symbol aliases_lookup)" \
                of_mutex_addr=0x"$(symbol of_mutex)"
        fi
        [[ -d /sys/module/${m//-/_} ]] || insmod "$M/$m.ko"
    done
fi
for i in $(seq 1 40); do [[ -e /sys/class/bluetooth/hci0 ]] && break; sleep 0.5; done
[[ -e /sys/class/bluetooth/hci0 ]] || { echo 'No hci0 after loading the stack.' >&2; exit 1; }
# The WCN3990 has no address of its own; this one is derived once from the
# machine ID, stays on the phone, and keeps pairings valid across boots.
if [[ ! -s $D/bdaddr ]]; then
    python3 - > "$D/bdaddr.new" <<'PY'
import hashlib
b = bytearray(hashlib.sha256(open('/etc/machine-id', 'rb').read().strip() + b'guacamole-bluetooth').digest()[:6])
b[0] = (b[0] & 0xFC) | 0x02  # unicast, locally administered
print(':'.join(f'{x:02X}' for x in b))
PY
    chmod 600 "$D/bdaddr.new"
    mv "$D/bdaddr.new" "$D/bdaddr"
fi
# At boot this can run before the system bus exists; bluetoothd then exits at once.
for i in $(seq 1 240); do [[ -S /run/dbus/system_bus_socket ]] && break; sleep 0.5; done
[[ -S /run/dbus/system_bus_socket ]] || { echo 'No system D-Bus for bluetoothd.' >&2; exit 1; }
pgrep -x bluetoothd >/dev/null ||
    setsid -f sh -c "exec /usr/lib/bluetooth/bluetoothd -n >> $D/bluetoothd.log 2>&1 < /dev/null"
adapter() {
    busctl --system call org.bluez /org/bluez/hci0 org.freedesktop.DBus.Properties \
        Get ss org.bluez.Adapter1 Address >/dev/null 2>&1
}
# The kernel keeps the controller unconfigured, and invisible to bluetoothd,
# until it has a public address. Firmware setup takes about 2 s after hci0.
for i in $(seq 1 60); do
    adapter && break
    if timeout 10 btmgmt --index 0 config 2>/dev/null | grep -q 'missing options: public-address'; then
        timeout 10 btmgmt --index 0 public-addr "$(cat "$D/bdaddr")" >/dev/null
    fi
    sleep 0.5
done
adapter || { echo 'bluetoothd never showed an adapter.' >&2; exit 1; }
echo 'BLUETOOTH_READY'
