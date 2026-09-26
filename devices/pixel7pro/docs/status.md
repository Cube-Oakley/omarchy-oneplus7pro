# Checkpoint — September 26, 2026

**Active work: persistent installation and power-button screen sleep/wake.**
The merged repository is the workspace for both devices. [V19 B](persistence-power-20260925.md)
now has physically verified power-key screen off/on with the shared CRT animation
and no console flash. The CPU stays awake; full suspend is not implemented.
The user authorizes replacing Android and userdata for a Linux-only install.
UFS enumerated the expected partitions and full boot-image reads matched the
saved hashes. Userdata is ext4 and passed a 16 MiB write/remount/readback check.
The complete Arch filesystem was installed through a checked sparse image;
image G mounts it and passes GPU shader readback. The shared desktop runs from
storage at 120 Hz after first-run font discovery and a desktop restart. Clock
setup now precedes Hyprland; cold reads at PWM gear 1 remain slow. The guarded
boot_a write and direct SHA256 readback passed. The following orderly restart
has not restored USB; the user sees console text. Autonomous startup and file
persistence across that restart are not yet verified.

**Current RAM test:** v19 G persistent-bootstrap candidate, SHA256
`eefa70189bf032f68d821bf9a1695229b15f0a20d2b0ffcbfbc0a4d35d80d42a`,
no automatic reboot timeout. USB serial remains the recovery interface.
Local SSH: `out/checkpoints/20260925-persistence-power/arch-session-f/ssh`.
Android recovery appeared after a native restart; recovery ADB successfully
returned it to the bootloader. Do not select Factory reset: userdata is Linux.

**Previous RAM milestone:** panel/bandwidth v18 image D, 120 Hz animation validated;
1800-second automatic return to stock slot A. No partitions were flashed.

**120 Hz milestone:** [Panel timing and bandwidth investigation](panel120-20260925.md)
now establishes clean native 120 Hz scanout and clean accelerated Hyprland
animation at approximately 120 fps. The user confirms both the native bars and
the final GPU triangle are clean. At the 421 MHz boot memory rate, GPU animation
was limited to about 60 fps and generated 600 observed DSI underruns in ten
seconds, producing full-width flashing lines. A stock-DT 1352 MHz MIF request
through CCF/ACPM, with unchanged GPU clocks, yields 119.6–120.2 fps and zero new
underruns. Image D integrates that bandwidth requirement with 120 Hz mode
ownership and detects underruns as transfer failures. Final D animation and
physical visual checks pass. Normal touch restoration remains under test: the
temporary GPIO driver initially stopped on a packet error. The vendor-style
bounded read-retry module stays loaded; physical response awaits the user's
retry. The normal shell is restored and its stale-kernel startup warning is
fixed. Earlier checkpoints remain intact.

**New hardware milestone:** [Thermal and CPU scaling](power-bringup-20260925.md)
work through standard Linux frameworks: seven thermal zones, three bounded
cpufreq policies, verified thermal cooling and schedutil. [GPU v15](gpu-bringup-20260925.md)
now powers the Mali-G710, starts CSF firmware and runs hardware GLES rendering.
An isolated Mesa build with the missing G710 model entry passes shader/readback
and resume tests. Hyprland selects Mali-G710 MC7 and renders the shared mobile
UI; a native screenshot is saved. The user confirms significantly faster
response, with remaining lag. Smooth 120 Hz is the target.
Full DPU/DSI display ownership and standard SPI touch remain unfinished.
The [v16 display investigation](display-pipeline-20260925.md) measured about
21 ms copying plus 12 ms refreshing each full-screen update. The user reports
horizontal tearing/glitchiness despite smooth-looking motion. Image B verifies
intermittent busy-at-update-entry and tests a bounded idle wait. Physical photos
also exposed blue backgrounds where software pixels are black; image C restores
the original ABL pixel/alpha layout. The user and physical photo now confirm
correct labeled red/green/blue bars, dark background and white checkerboard;
GPU animation still glitches, while the user confirms clean CPU-only motion.
A small display-owned GPU-buffer test reproduces stale CPU reads. Image D
uses standard shmem write-combined mappings: the identical three-color regression
now has zero mismatches (all 3,072 pixels failed on C). The user confirms GPU
animation edges are clean and the glitchy issue is fixed. Remaining pauses and
sub-60-fps performance persist; proper DPU/DSI scanout is still needed for 120 Hz.
The source/config, failed/passing regression and physical feedback are saved.

**Current milestone:** [Native Hyprland and shared mobile shell](hyprland-mobile-20260925.md)
now run on the Pixel. The user confirmed Hyprland's terminal and input proof.
The shared OnePlus mobile UI, Kitty and on-screen keyboard are captured in native
Wayland screenshots; Settings also maps and renders. Physical touch now reaches Hyprland and the shared UI through a temporary GPIO
SPI input driver; the user confirmed response, with severe latency. See the
[touch checkpoint](touch-bringup-20260925.md).
The older v11 EGL blocker was fixed with Mesa's `GBM_ALWAYS_SOFTWARE=1`.
The current v15 GPU launcher clears those software overrides and uses the
isolated hardware Mesa build; v11 remains an independent fallback.

**Previous stable 60 Hz image:** native DMA scanout v17 image D, SHA256
`8f8c6ae4d353452c6e76ecfc7ff086abd297cf81d844541fadddc83f8fef0fb0`.
The [direct scanout record](display-direct-20260925.md) preserves hardware IRQ
validation, read-only SysMMU capabilities, a physically confirmed Linux-owned
DMA test card and successful native DRM page flips. Both Mali shader and GPU
sharing regressions pass. The native display-only control reaches about 60 fps;
GPU desktop animation reaches 58–60 fps in several windows after lower startup
windows, with zero scanout failures. The user confirms correct visuals and much smoother motion. The mobile UI
was left running with bounded touch input. The later v18 work above adds 120 Hz
refresh control and the required memory bandwidth; full display power/PHY
ownership remains unfinished. The v16 D image remains the separate known-good visual fallback:
`b8479c90bfb58f9758f597393d56205794f0989fce1aa12466647b9c5480d2de`.
Sources, test results and replay are in the linked checkpoint. Earlier v11d
Arch/Hyprland/mobile shell and touch evidence remain preserved independently.
Earlier RAM milestones returned to Android. The current Linux-only installation
reuses userdata; recovery now means the bootloader and saved host images.

**Repository consolidation complete:** shared userspace lives in
`overlay/mobile/`; hardware-specific sources and evidence live in
`devices/<device>/`. The clean publication line is preserved separately, as
[publication instructions](../../../docs/publishing.md) describe.

## Display/Arch image

- Checkpoint: `out/checkpoints/20260925-drm-v11d/boot-pixel-shell.img`.
- SHA256: `ffcce07048c1924cd903d8550debd433d3a8baccb0f0eb777dd3820aa750ba95`.
- Kernel: `7.3.0-rc2-pixel-drm11-g5225b8eec4c9-dirty`.
- Display: `/dev/dri/card0`, DSI-1, fixed 1440×3120, CPU-copy XRGB → BGRA.
- Test: `pixel-kms-test 900` from the native serial shell.
- USB: composite serial + Ethernet, same link as v10 below.
- Local SSH wrapper while this boot is alive:
  `out/checkpoints/20260925-mobile-replay/arch-session/ssh`.
- Full patch/config: `devices/pixel7pro/kernel/native-bringup-v11.*`.

## Saved graphical userspace

The v11d directory contains a checked Weston rootfs archive, excluding temporary
SSH keys and runtime state. See [replay recipe and exact hashes](display-drm-20260925.md#saved-weston-rootfs-and-replay).
The Weston archive was successfully restored on a second RAM boot. Separate
Hyprland and mobile snapshots now preserve subsequent milestones; see the
[new replay notes](hyprland-mobile-20260925.md#checkpoints-and-replay).
The full mobile archive then passed a third-boot replay, including graphical
keyboard input. The RAM image reboots at 1800 seconds; that session has now ended.

## Network/Arch image

- Checkpoint: `out/checkpoints/20260925-network-v10b/boot-pixel-shell.img`.
- SHA256: `c67e891cb75b1297282cbde755f56018e95636e895baff01d9015ae257633dc5`.
- Composite USB `0525:a4aa`: CDC-ACM serial plus CDC-ECM Ethernet.
- Phone `10.77.7.1/30`, host `10.77.7.2/30`; no internet route/NAT.
- Twenty-minute automatic reboot; all phone userspace files disappear on reboot.
- See [exact boot/provisioning commands](native-arch-20260925.md#repeatable-use).

## Historical serial-only baseline (default helper image)

| Item | Value |
|---|---|
| Device | Pixel 7 Pro `cheetah`, serial kept locally in `out/device.serial` |
| Bootloader | `cloudripper-15.1-12292122`, unlocked, NOS production yes |
| Default OS | Factory Android 15 AP4A.250205.002 + Magisk 28.1 |
| Slot | A, successful; B is not a usable fallback |
| Native checkpoint | `out/checkpoints/20260925-shell-v9/` |
| Image | `boot-pixel-shell.img` |
| SHA256 | `88671219ba0d6835a7c6eee283948e38ec02f59522b44e6d760ddfb643493e05` |
| Native release | `7.3.0-rc2-pixel-shell9-g5225b8eec4c9-dirty` |
| USB | `0525:a4a7`, CDC-ACM; host `/dev/ttyACM*`, phone `/dev/ttyGS0` |
| Runtime | Default ten-minute automatic reboot; explicit `reboot` supported |
| Root filesystem | Embedded RAM-only initramfs; no phone partitions mounted |

## Use

```sh
python scripts/boot-pixel-shell.py
python scripts/pixel-shell.py
```

Run from `devices/pixel7pro/`. `Ctrl-]` leaves the connection; `exit` starts a fresh
shell. These are historical v9 commands; use the current installation state above.
ADB is an Android service and is not
present in the native image. The host helper identifies the Pixel gadget rather
than assuming that ttyACM0 is always its port.

## Milestones leading here

- September 24: recovered Android after identifying ABL command-line copying;
  factory boot restored exactly through fastbootd, Magisk root verified.
- Standalone framebuffer probe v2: screen photo and DECON frame-counter proof.
- Linux v4: screen console; MCT panic captured automatically in reserved RAM.
- Linux v5: GS201 MCT skip; eight CPUs, PID1 and planned 45-second reboot.
- USB v7: real DWC3 serial gadget enumerated; reset around 60 seconds.
- USB v8: stopped inherited watchdogs, completed 120 seconds and planned reboot.
- September 25: host udev rule installed, USB roundtrip verified, shell v9 tested.
- September 25 morning: USB Ethernet + serial, shared Arch base in RAM, key-only
  SSH and 8 MiB SFTP roundtrip verified; Android boot hashes unchanged afterward.

## Next work

1. Diagnose the console stop after the first orderly restart of the installed
   G boot image. Both root and boot_a are written; direct boot-image readback
   passes. Obtain the last visible console lines before physical recovery.
2. Validate persistence across independent boots and improve UFS performance.
3. Extend charging and suspend/resume after persistent boot.
   Screen blanking does not establish CPU suspend or deep idle.
4. Replace temporary GPIO SPI touch with standard SPI/IRQ input. CPU scaling,
   thermal sensing, Mali rendering and 120 Hz scanout already have checkpoints.

## Recovery state

Userdata is now the Linux filesystem; Android is no longer the recovery OS.
Power + Volume Down reaches the verified bootloader. Preserve the host factory
images and follow the validated restoration procedure if needed; do not switch
to B or use the old restore scripts blindly. Exact recovery hashes and the ABL
flash-header caveat are in [restart notes](restart-20260924.md).
