# Native USB shell — September 25, 2026

Later milestone: [USB Ethernet and shared Arch userspace](native-arch-20260925.md).
The v9 serial-only checkpoint below remains available unchanged.

Shell v9 adds an interactive BusyBox root shell to the verified v8 mainline
kernel/USB/watchdog handoff. It runs directly on the phone, in an embedded
initramfs. Android is not running underneath it. No partitions are mounted or
flashed by this test.

## Everyday use

From `devices/pixel7pro/` on the computer:

```sh
# Phone in Android with ADB, or the verified fastboot bootloader:
python scripts/boot-pixel-shell.py

# Interactive terminal; Ctrl-] leaves the connection:
python scripts/pixel-shell.py

# Or execute one command and return its exit code:
python scripts/pixel-shell.py --command 'id; uname -a; cat /sys/devices/system/cpu/online'
```

The shell prompt is `pixel-linux#`. `exit` ends that shell; PID1 starts another.
`reboot` signals PID1 and returns to Android. The default image also has a
600-second runtime limit, counted from native PID1 startup. Disconnecting the
host terminal does not stop the timer. All files are volatile.

The connection helper waits up to 45 seconds and matches USB vendor/product
0525:a4a7 plus the Pixel kernel manufacturer string. It sets the host tty to raw
mode and sends Ctrl-C/newline to clear partial startup input. The interactive
mode forwards terminal input and restores the host terminal when it exits;
command mode uses a unique completion marker and reports the remote exit code.
One helper owns the port at a time through an advisory lock. Do not run the old
echo-test observer alongside the shell helper.

## Host serial access

The user installed this rule and reloaded udev on September 25:

```sh
sudo install -m 0644 devices/pixel7pro/69-pixel-linux-serial.rules /etc/udev/rules.d/69-pixel-linux-serial.rules
sudo udevadm control --reload-rules
```

It grants the active local desktop user access to the matching ACM tty through
`uaccess`; it does not make the tty world-writable. On this host the gadget is
`/dev/ttyACM0`, with phone endpoint `/dev/ttyGS0`. The rule passed `udevadm verify`.
Before installation the gadget enumerated but opening its root/uucp-owned tty
failed with EACCES. After installation both host-to-phone and phone-to-host
traffic worked without sudo.

## Implementation

- `mainline/pixel-shell-init.c`: static PID1 mounts devtmpfs, proc, sysfs,
  tmpfs `/tmp` and `/run`, and devpts. It creates a session/controlling terminal
  for `sh -i`, reaps children, restarts an exited shell, logs to `/dev/kmsg`,
  and handles normal reboot signals and a runtime deadline.
- BusyBox 1.37.0: the exact static AArch64 binary already used by the OnePlus
  native initramfs. SHA256:
  `999cb969d09093a71716cfc747bb53cdada3f332c05eb5046c56e0f66a4d6d22`.
  Source location on this host:
  `../oneplus7pro/.work/codex-native-initramfs/bin/busybox`.
  The build checks the checksum and copies it into the checkpoint root.
- `scripts/build-pixel-shell.py`: creates a new root/output directory, compiles
  PID1, builds the kernel, packs the boot image, and saves source/config/hash
  evidence. It issues no device commands and refuses an existing output path.
- `scripts/boot-pixel-shell.py`: checks the image digest, exact phone serial,
  product, slot A, successful-slot flag, unlock and production state before
  RAM boot. It never flashes or switches slots.
- `scripts/pixel-shell.py`: interactive and scripted serial access.

Kernel changes are recorded in
[`devices/pixel7pro/kernel`](../kernel/README.md). The exact
base commit is in `kernel-base.txt`. The patch includes the framebuffer console,
startup RAM-log markers, GS201 MCT exclusion, embedded initramfs/bootconfig
support, runtime USB DT fixup, and watchdog handoff. Reverse patch validation
against the working tree passed.

The USB path preserves ABL's PHY/clock setup, fixes the vendor child compatible
from `synopsys,dwc3` to mainline `snps,dwc3`, removes unresolved vendor-provider
dependencies in the runtime tree, and registers the real DWC3 child. Mainline
`g_serial` provides CDC-ACM at USB2 high speed. Both AP boot watchdogs are stopped
using the same WTCON sequence as this phone's ABL; normal watchdog/PHY/clock
integration remains future driver work.

## Rebuild

Dependencies used here: GNU AArch64 GCC 16.1.0/binutils 2.47, make, QEMU AArch64
user emulator (only to list BusyBox applets), Python, legacy-capable lz4,
mkbootimg, and the checksum-pinned factory image under `out/factory-images/`.
The current `mainline/linux` already has the saved kernel patch applied.

```sh
python scripts/build-pixel-shell.py --output out/checkpoints/NEW-shell --seconds 600
```

For a clean kernel checkout, use the exact commit and apply
`devices/pixel7pro/kernel/native-bringup-v9.patch` once. The helper uses the saved
configuration and substitutes the output root's absolute initramfs path.
Kernel timestamps/build numbers mean a rebuild may have a different image hash.
The boot helper defaults to the tested v9 image and digest; a deliberate new
build can be selected with `--image PATH --sha256 DIGEST` after checking its
build result. `--seconds 0` builds a manual-reboot variant; indefinite runtime
has not been validated.

The boot packer preserves matching factory AVB metadata/OS properties around
the modified payload. Its payload digest is deliberately stale; this works on
this unlocked phone and does not make the new kernel Google-signed. Images are
for `fastboot boot` only.

## Validation and evidence

| Check | Result |
|---|---|
| v8 USB roundtrip after udev rule | Host marker sent, echoed, and recorded in native kernel log. |
| v9 root/kernel | `uid=0(root) gid=0(root)`; Linux `7.3.0-rc2-pixel-shell9-g5225b8eec4c9-dirty`. |
| CPU | `/sys/devices/system/cpu/online` is `0-7`. |
| Mounts | rootfs, devtmpfs, proc, sysfs, tmpfs and devpts only. |
| Interactive job control | Background `sleep`, `jobs`, and `kill %1` succeeded. |
| Shell supervision | `exit` replaced PID 90 with PID 103; kernel log confirms clean exit and restart. |
| RAM filesystem | Created, read and removed a file in `/tmp`. |
| Host reconnect | Multiple independent serial helper sessions succeeded. |
| Repeat RAM boot | Boot helper passed every identity/slot/hash guard; root shell and eight CPUs verified again. |
| Command status | `exit 7` returned host exit code 7; successful commands returned 0. |
| Native reboot | Normal `reboot` caused PID1 signal 15 and reboot at 145.684 seconds. |
| Android recovery | Android ADB and Magisk root returned; boot/init_boot hashes unchanged. |
| v9 automatic deadline | Configured and logged as 600 seconds; this session used manual reboot earlier. |

Checkpoint: `out/checkpoints/20260925-shell-v9/`.
Image SHA256:
`88671219ba0d6835a7c6eee283948e38ec02f59522b44e6d760ddfb643493e05`.

Evidence files include `shell-proof.txt`, `interactive-proof.txt`,
`exit-status-proof.txt`, `reboot-request.txt`, `linux-log.txt`, `android-after.txt`,
`build.log`, `kernel.config`, `kernel-tracked.patch`, the new C source files,
`cmdline.txt`, and `SHA256SUMS`. The complete embedded root and raw Image are
also saved. Earlier echo evidence is under
`out/restart-20260925/usb-roundtrip-v8/`.

## Recovery and limitations

Stock `boot_a` SHA256:
`6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10`.
Magisk `init_boot_a` SHA256:
`7e3f27da39717be9170ef982aa0bebf0e2806a66650520ad562843a1dc6a0117`.
Both were read back unchanged after the shell test.

Normal reboot returns to Android on slot A. If the native kernel hangs, Power
+ Volume Down reaches the verified bootloader; `fastboot -s "$PHONE_SERIAL" reboot`
returns to the installed OS. Slot B is not a fallback. Do not use historical
restore scripts or relock the bootloader. The detailed recovery investigation
is in [September 24 restart notes](restart-20260924.md).

This is a BusyBox bring-up shell, not the Arch/Omarchy desktop. USB networking,
SSH, file transfer, persistent storage, GPU/DRM, touch, Wi-Fi, charging, thermal
and power management still need development. The next milestone is a dependable
USB network/file-transfer path for fuller userspace.

## End-of-session shutdown

User requested power-off until tomorrow. Issued `/bin/busybox poweroff -f`
from the native root shell after a two-second delay. The forced form goes
directly to the kernel power-off operation; the bring-up PID1 currently maps
normal shutdown signals, including the normal BusyBox poweroff signal, to
reboot. This distinction matters for this experimental init. Transcript:
`out/checkpoints/20260925-shell-v9/shutdown-request.txt`.
