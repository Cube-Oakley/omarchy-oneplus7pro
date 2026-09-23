# Bluetooth bring-up — September 22, 2026

Result: **Bluetooth works on kernel #189 without a reflash.** The WCN3990
controller loads its stock firmware, scans (22 devices in 15 s), and paired
OnePlus Bullets Wireless 2 play A2DP audio (aptX HD). The user heard YouTube
through them. Wi-Fi kept HTTPS 200 with Bluetooth active. The shell can power,
scan, pair, connect and forget, and the headphones' own volume buttons drive
the volume overlay. Boot autostart is enabled on the phone; the first boot with
it has not happened yet.

Reference: the related 7T Pro port (`.work/hotdog-reference`, patches
`0025`/`0026`), whose Bluetooth later died without a root cause; see
[hardware plan §4](hardware-plan-20260922.md).

## Pieces

| Piece | Where |
| --- | --- |
| Module build: `bluetooth`, `rfcomm`, `bnep`, `hidp`, `hci_uart`, `btqca`, `btbcm`, `ecc`, `ecdh_generic`, `pwrseq-core` | `scripts/build_bluetooth_modules.sh` |
| UART13 overlay and its loader module | `devices/oneplus7pro/kernel/radio/bluetooth/` |
| `hsuart0` alias shim | `devices/oneplus7pro/kernel/radio/bluetooth/hsuart_alias_shim.c` |
| Board start (modules, address, `bluetoothd`) | `devices/oneplus7pro/bluetooth/start.sh` → `/usr/local/sbin/guacamole-bluetooth-start` |
| Diagnostic run | `scripts/phone-bluetooth-test.sh` |
| Shell helper, Settings page, shade toggle | `overlay/mobile/bluetooth.py`, `kit/BluetoothPage.qml`, `NotificationShade.qml` |

Our `.config` already had the stack as modules (`BT_HCIUART_QCA=y`,
`SERIAL_DEV_BUS=y`), but the phone has no module tree for this kernel. The
modules are built out of tree against `.work/linux-sm8150-mmcx-sleep` like
`ipa.ko`. `bluetooth.ko` links the phone's own `rfkill.ko`
(`.work/native5-radio-modules`, byte-identical), and `hci_uart.ko` links the
power-sequencing core, which the WCN3990 path does not use.

## Device tree

UART13 (QUP2 SE3, `serial@c8c000`, GPIOs 43–46) with a `qcom,wcn3990-bt`
child, `firmware-name = "crnv21.bin", "crbtfw21.tlv"` (the ROM version derives
to `crbtfw01`/`crnv01`, which do not exist), and the four rails Wi-Fi already
uses: L1A, L7A, L2C, L11C. There is no enable GPIO. QUP2 is already enabled and
bound for its I2C bus, so the overlay only switches the serial engine on. The
stock OOS12 DTBO node is byte-identical to the 7T Pro's.

Two problems had to be solved at runtime.

**The RX wake IRQ self-deadlocks.** With the 7T Pro's
`interrupts-extended = <&intc GIC_SPI 585 …>, <&tlmm 46 IRQ_TYPE_EDGE_FALLING>`,
the controller never answered (`command 0xfc00 tx timeout`, three power-on
retries). The stuck tasks (`out/bluetooth/first-load-20260922.log`):

```
irq/194-c8c000.serial:wakeup  D  __synchronize_irq ← disable_irq ← msm_pinmux_set_mux
  ← pinctrl_pm_select_default_state ← geni_se_resources_on
  ← qcom_geni_serial_runtime_resume ← rpm_resume ← handle_threaded_wake_irq
```

The wake IRQ thread runtime-resumes the UART; the resume muxes GPIO 46 from
the sleep state's `gpio` function back to `qup13`; `msm_pinmux_set_mux()` then
calls `disable_irq()` on that same IRQ and waits for its own thread. The port
stayed locked, so every HCI command timed out, and a clean recovery reboot was
the only way out. Without the wake IRQ the chip answered at once. This may be
what killed the 7T Pro's Bluetooth later; that is an inference. Waking the phone
from suspend on Bluetooth traffic needs another design.

**No serial alias.** `qcom_geni_serial` numbers an alias-less port from the
highest `serial` alias plus one. Our boot DTB has no serial aliases, so that is
`-ENODEV + 1` and the probe fails with `Invalid line -19`. Overlays cannot add
aliases, so `guacamole_hsuart_alias.ko` adds `hsuart0` to the kernel's alias
list at runtime. The list is not exported: the start script passes the
addresses of `aliases_lookup` and `of_mutex` from `/proc/kallsyms`, and the
module checks both with `sprint_symbol()` before touching anything. **Kernel
#190 carries `hsuart0` in its boot DTB** ([camera notes](camera-20260922.md)),
and the start script skips the shim when the alias exists; on #190 Bluetooth
came up without it.

The first boots with autostart lost two races, both from the desktop hook
starting several jobs at once. `bluetooth.ko` links `rfkill`, which the radio
startup loads, so the first insmod failed with an unknown symbol. On the next
boot the modules loaded but `bluetoothd` started before the system bus existed
and exited, and the script then failed silently. It now waits for `rfkill` and
for `/run/dbus/system_bus_socket`, and every failure path logs its reason.

## Controller and firmware

```
QCA SOC Version  :0x40010224   ROM Version :0x00001001   Patch Version:0x00006699
QCA Downloading qca/crbtfw21.tlv
QCA Downloading qca/crnv21.bin
QCA setup on UART is completed
```

The same versions as the 7T Pro. The firmware is the phone's own, from the stock
`bluetooth_a`/`bluetooth_b` partitions (byte-identical FAT16 images, `image/`):
`crbtfw21.tlv` (229,812 bytes, SHA-256 `46a09f53…`) and `crnv21.bin` (4,710
bytes, `148255b1…`). Both differ from the linux-firmware copies in
`/lib/firmware/qca`, which stay untouched; the stock ones are installed in
`/lib/firmware/updates/qca/`, which the kernel searches first. The partition
also holds identical board NVMs `crnv21.b44`/`b46`/`b47`/`b55`/`b71`; which
board ID stock selects is unverified. Copies and hashes: `out/bluetooth/`.

## Address

The kernel registers the controller as **unconfigured**, invisible to
`bluetoothd`, until it has a public address; the bootloader passes none. The
start script derives a stable, locally administered address from
`/etc/machine-id` once and sets it with `btmgmt public-addr`, so pairings
survive reboots. It is stored only on the phone. Reading the factory address
from the modem can replace it later. The adapter is named "OnePlus 7 Pro
(Omarchy)".

## Audio

The board's WirePlumber config had `monitor.bluez = disabled` from the speaker
bring-up. Headphones then paired, but every audio connection failed with
`a2dp-sink profile connect failed: Protocol not available`, because no media
endpoints were registered. It is now `optional`, with seat monitoring disabled
(this root session has no logind). PipeWire registers SBC, AAC, aptX (HD, LL),
LDAC, Opus and FastStream endpoints.

The first pairing never completed an audio connection, so the headphones
dropped the key: `btmon` showed our Link Key Request Reply answered with
`PIN or Key Missing`, then `Authentication Failure`. Forgetting and pairing
again fixed it.

WirePlumber gives Bluetooth sinks priority 1010, above the speakers' 1000, so
connected headphones become the output by themselves. Media volume is per
output, as on Android: while headphones play, "media" means their absolute
volume (their buttons change it), the media loopback is held at 100%, and the
speaker level comes back when they leave (`overlay/mobile/volume.py`). The
volume overlay watches `pactl subscribe` and shows changes made by the
headphones' buttons, and names the output when expanded.

Not tested: hands-free (HFP) calls, where `bluetoothd` logged the headset's HFP
connection as refused; HID keyboards, which need a PIN agent; suspend with
Bluetooth loaded.

## Using it

- `guacamole-bluetooth-start` loads everything once per boot and is safe to
  rerun. The shell's toggles call it when no controller exists.
- Autostart after the desktop: `touch /root/bluetooth-bringup/autostart-enabled`
  (hook in `devices/oneplus7pro/desktop-prepare.sh`). Enabled on the phone at
  the user's request; remove the marker to go back to on-demand starts.
- **Never `rmmod hci_uart`.** Its serdev remove path panicked the 7T Pro. Reboot
  to unload.

## Unexplained

The first boot after the deadlock's recovery reboot answered ping from the
initramfs, never reached SSH, and dropped off USB. A button restart showed the
desktop but no USB until a restart with the cable connected throughout. No
Bluetooth code loaded at boot then (autostart came later), pstore was empty,
and neither boot wrote a bring-up log. Watch for a repeat.
