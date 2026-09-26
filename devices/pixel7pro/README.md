# Omarchy Mobile · Pixel 7 Pro

Bringing native Linux and the Omarchy desktop experience to the Pixel 7 Pro
(`cheetah`, Tensor G2 / GS201). The OnePlus 7 Pro project is the reference for
bring-up methods and the eventual mobile interface.

**Status: native Hyprland and shared Omarchy mobile shell, September 25, 2026.** Mainline Linux
boots in RAM with all eight CPUs, an on-screen boot log, and a BusyBox serial
shell. The shared OnePlus Arch Linux ARM base runs in a RAM-only chroot, with
key-only SSH and verified SFTP over USB Ethernet. A fixed-mode DRM display bridge
runs user-confirmed Hyprland with USB-fed keyboard input. The same mobile shell
as the OnePlus project displays its launcher, themes, Kitty, keyboard and Settings
using Mesa software rendering. Physical touch was confirmed with a temporary GPIO
SPI driver; proper CPU/GPU/display drivers are now the priority. Full Arch boot and persistent
installation are still ahead.
Factory Android remains the normal boot on slot A; no experimental Linux image
has been flashed.

## What works

| Area | Verified result |
|---|---|
| Recovery baseline | Rooted factory Android AP4A.250205.002 on slot A; boot images checked by SHA256. |
| Native boot | Linux 7.3.0-rc2, embedded initramfs, all eight CPUs online. |
| Display | Fixed-mode 1440×3120 DRM bridge, standard dumb buffers/modeset/page flips, visible test card; early console hands off while RAM logs continue. |
| Wayland | Hyprland/llvmpipe, confirmed graphical input, shared mobile launcher, themed Kitty, keyboard and Settings; Weston fallback preserved. |
| Physical touch | S3908 GPIO SPI input reached Hyprland; user confirmed response, but it is slow. |
| USB | DWC3 peripheral using inherited PHY state; concurrent USB2 CDC-ACM and CDC-ECM Ethernet. |
| Shell | Native root BusyBox shell, job control, RAM files, shell restart after exit, command exit-status reporting. |
| Arch userspace | Same cached Arch Linux ARM base as OnePlus; native Bash, glibc, pacman and OpenSSH. |
| Network transfer | Private USB link, key-only SSH, 8 MiB SFTP roundtrip with matching hashes. |
| Boot watchdogs | Both inherited AP watchdogs stopped; two-minute runtime verified before the longer shell test. |
| Return path | Automatic test timeout; normal `reboot` from the shell returns to Android. |

Storage, GPU acceleration, complete panel control, battery/charging, thermal and
power management are not brought up in this mainline image. The current shell
uses RAM only; files disappear on reboot. Slot B is **not** a recovery fallback.

## Connect

From `devices/pixel7pro/` on the computer, with the phone in Android or fastboot.
The helper needs the handset serial, which stays local: set `PHONE_SERIAL` or
put it on one line in ignored `out/device.serial`.

```sh
python scripts/boot-pixel-shell.py
python scripts/pixel-shell.py
```

The boot helper verifies the image hash, phone identity and slot state, then
uses `fastboot boot`. The default v9 image returns to Android after ten minutes.
`Ctrl-]` disconnects the terminal; `exit` restarts the phone's shell; `reboot`
returns to Android immediately.

For a single command:

```sh
python scripts/pixel-shell.py --command 'id; uname -a; cat /sys/devices/system/cpu/online'
```

The host's USB serial access rule is installed. Full setup, build instructions,
test evidence and recovery steps: [native shell bring-up](docs/native-shell-20260925.md).
For the network image and repeatable Arch/SSH bootstrap, follow
[native Arch userspace](docs/native-arch-20260925.md).

## Documentation

- [Hardware pipeline](docs/hardware-pipeline-20260925.md): CPU/GPU/display dependency order, stock inventory and initial ACPM patches.

- [Physical touch checkpoint](docs/touch-bringup-20260925.md): user-confirmed GPIO SPI experiment and its limitations.

- [Hyprland and shared mobile shell](docs/hyprland-mobile-20260925.md): renderer fix, shared-source provenance, screenshots and replay.
- [Current checkpoint](docs/status.md): working image, exact state, next steps.
- [Native DRM display, September 25](docs/display-drm-20260925.md): retained-panel bridge, visual confirmation and page-flip evidence.
- [USB networking and native Arch, September 25](docs/native-arch-20260925.md): shared base, SSH, repeatable RAM provisioning.
- [Shared OS architecture proposal](../../docs/shared-os-20260925.md): monorepo/device boundaries, docking and upstream updates.
- [Native shell, September 25](docs/native-shell-20260925.md): implementation, reproduction, validation, recovery.
- [Recovery and first native boot, September 24](docs/restart-20260924.md): chronological investigation and failed experiments.
- [Kernel patch and config](kernel/README.md): source checkpoint, independent of built images.
- [Historical README](README-legacy-20260913.md) and [historical recovery notes](STATUS-legacy-20260913.md): preserved for reference; their state and procedures are superseded.

Dated build artifacts, source snapshots, checksums and test transcripts live in
`out/checkpoints/`; earlier diagnostics remain in `out/restart-20260924/`.
