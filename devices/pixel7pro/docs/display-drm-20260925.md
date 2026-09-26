# Retained-display DRM bridge — September 25, 2026

## Session scope and decisions

The user approved the shared monorepo direction while requiring that the OnePlus
project remain intact. It is read-only during this Pixel session; eventual
consolidation must use an isolated destination and the clean public lineage.
Wired external video is not a Pixel requirement. Shared docking support belongs
to capable devices and does not block this port.

Android is no longer the intended OS for this phone. Per the user, validating an
Android return after every stage is unnecessary. Preserve the unlocked bootloader,
RAM-boot tooling and recovery artifacts; continue RAM tests while drivers mature.
No flash, slot change, bootloader/radio update or OnePlus edit is part of this test.

## Implementation

`drivers/gpu/drm/sysfb/pixel_handoff.c` in the local kernel provides a development
DRM/KMS driver using the same sysfb/shmem helpers as simpledrm. It is built only
with `CONFIG_DRM_PIXEL_HANDOFF=y`, activated with `pixel_drm=1`, and requires the
verified `google,GS201 CHEETAH` machine compatible string.

The probe rechecks DPP0 framebuffer base, dimensions, format, compression, crop,
stride selection, DECON running state and trigger state before taking ownership.
The early console already reserves and marks the retained framebuffer RAM nomap.
A console-lock handoff stops on-screen printk drawing, while the reserved RAM
kernel log remains active. USB serial remains independent of display ownership.

The driver exposes one 1440x3120 fixed-mode DSI connector, one primary plane and
XRGB8888 dumb buffers. Atomic updates copy damaged rows into the inherited
framebuffer, then use the previously verified bounded DECON update/trigger
sequence. No panel commands, clocks, regulators, scanout DMA addresses or firmware
are programmed. There is no GPU acceleration, real vblank IRQ, power-off/backlight
control or suspend support; the helper mode's nominal 60 Hz is not a measured
refresh guarantee. Page-flip events must not be represented as hardware vblank
measurements.

**Historical format assumption, contradicted by later physical evidence:**
Google's `cal_9845/regs-dpp.h` maps DPP format 0 to BGRA8888, and
`exynos_drm_format.c` maps that hardware code to DRM_FORMAT_BGRA8888. The driver
therefore converts conventional XRGB8888 rows to BGRA8888 with forced opaque
alpha. It does not change the DPP format register. Copies of these source files
are in `out/restart-20260924/display-source/`.
In the [v16 investigation](display-pipeline-20260925.md), the user confirmed that
this conversion turns a software-black background blue and produces cyan/pink
triangle colors. The September 24 probe's unrotated, high-byte-alpha pixels
produced gray correctly. Image C restores that byte layout for physical color
validation. A successful modeset or screenshot never established correct panel
colors in the earlier v11 checkpoint.

`mainline/pixel-kms-test.c` is a static AArch64 userspace test using standard DRM
ioctls only: identify the expected driver, enumerate the fixed connector, create
and map two dumb buffers, add framebuffers, modeset and request eight page flips.
It verifies flip events, shows red/green/blue bars and alternating checkerboards,
and holds a readable test card. It does not access physical memory or private
kernel ioctls. The VGA font is generated from the pinned kernel's font source.

## Build and evidence

```sh
python scripts/build-pixel-shell.py --output out/checkpoints/NEW-drm \
  --seconds 1800 --drm
```

`--drm` includes USB networking and the KMS test program. Follow the same image
SHA/device identity checks used by the network checkpoint before RAM booting.
Initial local builds v11 through v11c were never booted: v11 exposed missing
logging declarations; v11b preceded a userspace resource-query correction; v11c
preceded the verified BGRA conversion. Keep these separate from on-device evidence.

## Sources

- Local pinned mainline `drivers/gpu/drm/sysfb/simpledrm.c`,
  `drm_sysfb_modeset.c`, `drm_sysfb_helper.h`, and DRM UAPI headers.
- [Kernel DRM helper documentation](https://docs.kernel.org/gpu/drm-kms-helpers.html).
- [Google pixel formats](https://android.googlesource.com/kernel/google-modules/display/+/refs/heads/android-gs-pantah-5.10-android14-qpr3/samsung/exynos_drm_format.c).
- [Previous verified framebuffer/USB bring-up](restart-20260924.md).

## First on-device result: v11d

RAM image `out/checkpoints/20260925-drm-v11d/boot-pixel-shell.img`, SHA256
`ffcce07048c1924cd903d8550debd433d3a8baccb0f0eb777dd3820aa750ba95`:

- DRM registered `pixel-handoff` at uptime 0.372 s; `/dev/dri/card0` exists.
- Connector DSI-1 became connected with mode 1440x3120 after the first probe.
- Standard userspace modeset and page-flip requests succeed.
- DECON frame counters advance (first commit 17 → 18), update bits clear, and
  zero refresh timeouts were reported.
- The user confirmed: “yeah I see the test card.” Color accuracy was not separately
  confirmed; do not infer it solely from that response.
- The shared Arch base and SSH were provisioned concurrently with the display test;
  no Android return validation was performed between these stages.

Evidence is in that checkpoint's `drm-probe.txt`, `kms-start.txt`,
`kms-results-initial.txt` and `arch-session/`. The latter contains local SSH
credentials and is not distributable source.

## Native Wayland terminal: confirmed

Weston 15.0.1 runs directly on card0 with its Pixman renderer, a seatd session
(`SEATD_VTBOUND=0`) and DSI-1 scaled by 3. The screen is 1440×3120 physically,
480×1040 logically. `weston-terminal` runs native Arch Bash. The user confirmed:
“yep I see the terminal and the text!” This is Weston, not yet an Omarchy session.

A matching uinput module and `mainline/pixel-input-bridge.c` create a development
keyboard. Root-only `/run/pixel-input` receives text over SSH, emits Linux key
events, and Weston/libinput delivers them to the terminal. Typing a command this
way created `/run/pixel-wayland-input-proof` containing `pixel-wayland-input-ok`.
There is still no physical touchscreen driver. Evidence: `arch-session/wayland-
confirmed.txt`, `wayland-input-proof.txt`, and `weston-restored.txt` in v11d.
Nonfatal terminal warnings concern missing drag cursors and bracketed paste.

The reusable launch helpers are `scripts/pixel-weston-start.sh` and
`scripts/pixel-terminal-start.sh`; run them **inside the phone's RAM Arch root**,
not on the host. The latter expects the saved module and input bridge below.
Weston uses CPU copies; this does not establish acceleration or power management.

### Packages and transport

Arch was updated with pacman, and Weston, seatd and DejaVu fonts installed.
The Arch root needs a self-bind mount so pacman's CheckSpace sees the correct
mount; `pixel-arch-services.sh` now does this before bind-mounting virtual filesystems.
Pacman's filesystem sandbox required `DisableSandboxFilesystem` because this
kernel lacks Landlock. Package signature checking remained enabled. A future
kernel should include Landlock instead of needing this development exception.
The generic Arch kernel package's initramfs hook warned about missing modules and
fsck tools in this chroot; those files were only installed in RAM and that kernel
was not booted. The Pixel-specific v11d kernel remained running throughout.

`scripts/arch-usb-mirror.py` cached signed packages from
`https://ca.us.mirror.archlinuxarm.org` on the host, bound only to 10.77.7.2:8000.
A direct phone connection timed out, so a restricted reverse SSH tunnel mapped
phone localhost:8000 to that host address. The temporary sshd config allowed
remote forwarding only on 127.0.0.1:8000, and pacman's mirrorlist used
`http://127.0.0.1:8000/$arch/$repo`. No host firewall or routing change was needed.
Package hashes and upstream URLs are in `packages/downloads.jsonl`. Repository
`.db.sig` 404s are compatible with DatabaseOptional; package signatures were checked.
The saved rootfs retains this temporary mirrorlist and needs a tunnel for downloads.

### Saved Weston rootfs and replay

The known-working userspace was archived **before** the Hyprland experiment:

- `out/checkpoints/20260925-drm-v11d/arch-wayland-rootfs.tar.zst`
  (836981619 bytes), SHA256
  `9b3feca83eff50b4c37edd48d9d9c1cc08e38ce539e3f4dafed52c8dd77dc06b`.
- Gzip version required by the current bootstrap (1048861965 bytes), SHA256
  `cfd03bee57d36682249ff93fbe78e69430863fcf063bd918cb93eadf5e722efe`.

Archive integrity was checked. These are local development artifacts, not public
OS release images. The archive excludes virtual filesystem contents, runtime
state, package cache, root SSH credentials, Pixel SSH host/config files, and the
pacman keyring. Bootstrap creates fresh session SSH credentials. The userspace
snapshot does not change the kernel or the 1800-second test lifetime.

From Android/fastboot, the replay recipe is:

```sh
python scripts/boot-pixel-shell.py \
  --image out/checkpoints/20260925-drm-v11d/boot-pixel-shell.img \
  --sha256 ffcce07048c1924cd903d8550debd433d3a8baccb0f0eb777dd3820aa750ba95
python scripts/start-pixel-arch.py \
  --archive out/checkpoints/20260925-drm-v11d/arch-wayland-rootfs.tar.gz \
  --archive-sha256 cfd03bee57d36682249ff93fbe78e69430863fcf063bd918cb93eadf5e722efe \
  --output out/checkpoints/NEW-wayland-session
out/checkpoints/NEW-wayland-session/ssh 'bash -s' < scripts/pixel-weston-start.sh
out/checkpoints/NEW-wayland-session/ssh 'bash -s' < scripts/pixel-terminal-start.sh
```

The archive-selector option and complete fresh replay subsequently passed on
a second boot; see the Hyprland follow-up. Both launch scripts were checked against the live session;
Weston and its terminal were successfully restarted after the Hyprland test.

### Rebuilding the development keyboard

Use the exact v11d kernel build/config to match its module ABI:

```sh
mkdir -p out/checkpoints/NEW-input/module
cp mainline/linux/drivers/input/misc/uinput.c out/checkpoints/NEW-input/module/pixel_uinput.c
cp mainline/linux/drivers/input/input-compat.h out/checkpoints/NEW-input/module/
sed -i 's|../input-compat.h|input-compat.h|' out/checkpoints/NEW-input/module/pixel_uinput.c
printf 'obj-m := pixel_uinput.o\n' > out/checkpoints/NEW-input/module/Makefile
make -C mainline/linux ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
cp mainline/linux/vmlinux.symvers mainline/linux/Module.symvers
make -C mainline/linux ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  M="$PWD/out/checkpoints/NEW-input/module" modules
aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra \
  mainline/pixel-input-bridge.c -o out/checkpoints/NEW-input/pixel-input-bridge
```

Place the module at `/root/pixel_uinput.ko` and executable bridge at
`/usr/local/bin/pixel-input-bridge` inside the phone RAM root. Both are in the
saved Weston snapshot. Loading this separately built upstream module taints the
kernel as an external module; no touchscreen hardware is accessed.

## Initial Hyprland feasibility result (subsequently resolved)

See [the follow-up](hyprland-mobile-20260925.md) for the verified GBM software
setting and working Hyprland/mobile shell. The failure below is historical.

Installed Hyprland 0.56.2-3 and mesa-utils after saving the Weston snapshot.
Mesa 26.2.3 provides llvmpipe: surfaceless EGL 1.5, OpenGL 4.6 and GLES 3.2 were
reported. **GBM EGL initialization failed**, so surfaceless success does not prove
a renderer capable of presenting to this DRM device.

A direct, bounded Hyprland launch with `mainline/pixel-hyprland.lua`, card0,
seatd, llvmpipe and kms_swrast detected DSI-1 and its fixed mode. Aquamarine
reported “no matching devices found”; EGL then reported
“DRI2: failed to get compatible render device”. Hyprland aborted in `initEGL`.
Core dumps were disabled for this controlled probe. No native Hyprland frame was
shown. The exact command, compositor log and generated crash report are saved as
`arch-session/hyprland-probe.txt` and `hyprland-failure.txt`; EGL output is in
`egl-software-probe.txt`. Weston was restored afterward.

Next investigate the Mesa/GBM/Aquamarine compatibility path for a display-only DRM
device, or bring up a usable GPU/render node. Do not claim that installing Hyprland
solves that hardware/userspace interface. Touch, full service boot, charging,
thermal control and persistent storage remain separate work. The OnePlus source
was inspected read-only for configuration and renderer-selection reference.

Additional primary references:
[Weston running guide](https://wayland.pages.freedesktop.org/weston/toc/running-weston.html),
[Aquamarine source](https://github.com/hyprwm/aquamarine).
