# USB networking and shared Arch userspace — September 25, 2026

## Outcome

Native Pixel Linux now supports concurrent USB serial and Ethernet. The exact
Arch Linux ARM base archive from the OnePlus project runs natively in a RAM-only
chroot, with Bash, glibc, pacman and OpenSSH. Public-key-only SSH and an 8 MiB
binary SFTP roundtrip are verified. This is **not yet an Arch systemd boot or an
Omarchy graphical session**: the small bring-up program remains PID1.

No phone block device is mounted and no partition is flashed. The host network
profile is in memory only, with a private link and no default route or DNS/NAT
changes. Android slot A remains the normal boot; B is not a fallback.

## Checkpoints

| Checkpoint | Boot image SHA256 | Details |
|---|---|---|
| `out/checkpoints/20260925-network-v10/` | `fecf7986602dfc5d0402944b4204f3d57bcf5fb0edb079d012ac72ad38d39240` | First successful network, native Arch, SSH and SFTP test. |
| `out/checkpoints/20260925-network-v10b/` | `c67e891cb75b1297282cbde755f56018e95636e895baff01d9015ae257633dc5` | Removes an unavailable BusyBox HTTP applet call; repeatability test described below. |

The v10b fresh-boot test completed the automated bootstrap in about 75 seconds:
829,367,415 bytes transferred in 22.58 seconds, archive verified/extracted,
SSH host key pinned, and native Arch commands executed. An interactive SSH PTY
reported `/dev/pts/0` and `PIXEL_ARCH_PTY_OK`. Its corrected network startup
completed at kernel uptime 0.603 seconds. Logs are under `arch-session/`
within that checkpoint; source snapshots are under `host-source/`.

After both experiments, Android boot completed on slot A. The final v10b return
check verified the recovery-baseline hashes below, battery 100%, charging, and
temperature 27.9°C. Both temporary host network profiles were removed. The phone
was left in Android, so the RAM Arch environment and SSH service are now gone.

```text
boot_a:      6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10
init_boot_a: 7e3f27da39717be9170ef982aa0bebf0e2806a66650520ad562843a1dc6a0117
```

Return evidence: `out/checkpoints/20260925-network-v10b/android-return-verified.txt`.

Both use `7.3.0-rc2-pixel-net10-g5225b8eec4c9-dirty`, all eight CPUs, and a
1,200-second automatic reboot limit. v9 remains the known serial-only baseline
and the default of `boot-pixel-shell.py`.

The first v10 script attempted to serve a proof file using `httpd`, which this
BusyBox binary does not contain. Networking had already come up successfully.
v10b removes that call; transfers use an explicitly started one-shot `nc`
listener, then authenticated SSH/SFTP. Existing v10 artifacts are preserved.

## Kernel and link changes

Relative to v9, disable `CONFIG_USB_G_SERIAL` and enable
`CONFIG_USB_CDC_COMPOSITE`. Mainline's `g_cdc` provides CDC-ECM and CDC-ACM
interfaces together as USB `0525:a4aa`. The DWC3/PHY bring-up code is unchanged.
The composite gadget retains serial as an independent control path.

| Endpoint | Interface | Address | MAC |
|---|---|---|---|
| Phone | `usb0` | `10.77.7.1/30` | `02:70:07:00:00:01` |
| Host | discovered from USB identity and MAC | `10.77.7.2/30` | `02:70:07:00:00:02` |

The host's previous OnePlus Ethernet profile initially autoconnected to the
physical USB port. A new nonpersistent NetworkManager profile replaces that
active connection for this test; the OnePlus profile itself is not edited.
The updated `69-pixel-linux-serial.rules` was installed by the user and verified,
so either the serial-only or composite Pixel gadget receives desktop tty access.

## Shared OS input

Source archive, borrowed read-only from the existing project:

```text
../oneplus7pro/.work/arch/ArchLinuxARM-aarch64-latest.tar.gz
size: 829367415 bytes
SHA256: 42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319
```

This pins the cached reference input; no upstream signature verification was
performed in this session. The file transferred in 22.51 seconds on the first
run and was hash-checked again on the phone before extraction. The archive has
49,104 entries and about 2.11 GB of file content; archive plus extracted files
use about 2.8 GiB of `/run` tmpfs. Its generic kernel/modules are merely files in
RAM; the running kernel is always the Pixel boot image.

Verified packages from this same base:

```text
bash 5.3.15-1
glibc 2.43+r22+g8362e8ce10b2-2
openssh 10.4p1-3
systemd 261.2-1
```

`/usr/lib/systemd/systemd --version` runs; this does not mean systemd is PID1.
The first diagnostic used the nonexistent `/bin/systemd` PATH name, then the
correct executable path was tested successfully. `stat -f /` inside Arch reports
tmpfs, while `/proc/1/comm` reports `ourinit`.

## Repeatable use

From the project root, with the Pixel in Android/ADB or its bootloader:

```sh
python scripts/boot-pixel-shell.py \
  --image out/checkpoints/20260925-network-v10b/boot-pixel-shell.img \
  --sha256 c67e891cb75b1297282cbde755f56018e95636e895baff01d9015ae257633dc5
python scripts/pixel-shell.py --command 'ip addr show usb0'
python scripts/start-pixel-arch.py --output out/arch-session-NEW
out/arch-session-NEW/ssh
```

Choose a new output directory for each test. Provision promptly after boot: the
image returns to Android after twenty minutes, including transfer/extraction
time. Reprovisioning is required after reboot because all phone files are in RAM.
The bootstrap refuses provisioning when fewer than six minutes remain.
The bootstrap requires host NetworkManager desktop authorization and the cached
archive; it does not require host root when the tty udev rule is installed.

`start-pixel-arch.py` verifies the archive, identifies the USB network gadget,
creates/activates a nonpersistent host profile, starts a one-shot receiver over
serial, sends and verifies the archive, extracts it, provisions a dedicated
client public key and starts Arch sshd. It also sets the phone's volatile system
clock from the host. Source: `scripts/pixel-arch-services.sh`.

SSH binds only `10.77.7.1:22`, disables password/interactive authentication and
forwarding, and uses a fresh phone host key. The host key is obtained over the
known serial connection and pinned in the output directory's `known_hosts`.
No existing host SSH config or private keys are read or changed. The local output
directory contains private temporary client credentials and must remain local.
Phone root keys/config exist only in RAM. Do not publish `out/`.

The service script gives the chroot its own bind mount so `/` resolves correctly
in mountinfo and package-manager space checks. It recursively binds `/dev`, mounts proc/sysfs and a separate
RAM `/run` inside Arch, and provides devpts/shm and standard `/dev/fd` links.
It does not run Arch's default services or mount internal storage. There is no
internet route yet; do not assume package downloads work.

For serial fallback:

```sh
python scripts/pixel-shell.py
# Inside the phone shell:
chroot /run/arch /bin/bash
```

Use `exit` to leave the Arch shell. Use `reboot` from the **outer BusyBox shell**
to return to Android; Arch's systemctl-backed reboot is not the PID1 control path.
The bootstrap prints a command to delete its exact temporary NetworkManager
profile after reboot. That UUID is also recorded in its `session.json`.

## Build

```sh
python scripts/build-pixel-shell.py \
  --output out/checkpoints/NEW-network \
  --seconds 1200 --usb-network
```

The recipe starts with the saved v9 kernel configuration, adjusts the gadget,
embeds network setup in the initramfs and records source/config/checksums. It
creates a RAM-boot image locally and never accesses the phone. Use the resulting
image's own SHA256 when booting it. The factory boot envelope requirements and
recovery safeguards from [native shell notes](native-shell-20260925.md) apply.

## Evidence and next boundary

First-run evidence under `out/checkpoints/20260925-network-v10/` includes
`transfer-host.json`, `archive-sha256.txt`, `arch-extract.txt`, `ssh-proof.txt`,
`sftp-roundtrip.json` and `hardware-inventory.txt`. The 8 MiB SFTP roundtrip SHA256
was `828f122c0e6ad3e685bd5558f8f24fc1a09a01866fbfd4d0eb2b3b7169272bd6` in both
directions. Kernel uptime exceeded ten minutes during the test.

Hardware enumeration currently shows no DRM device, input devices, power supplies
or thermal zones; only loop block devices. GPIO keys and a fixed regulator remain
deferred. The inherited framebuffer console is not a DRM/KMS output usable by
Hyprland. Native display/input and power support need further driver work before
an interactive Omarchy desktop is possible. The shared userspace boundary is now
proven independently of those drivers.

See [shared OS architecture](../../../docs/shared-os-20260925.md) for how this base
should become one common OS with separate device support and docking profiles.
