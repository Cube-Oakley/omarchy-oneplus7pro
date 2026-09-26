# CPU and GPU work — 2026-09-16, Codex

## Accelerated desktop verified (~23:38 PDT)

**gpu1 / kernel #173 is running on slot B. Hyprland and Quickshell both use
Adreno FD640, and their pixels reach the physical scanout buffer.** All eight
CPUs are online and passed the pinned checksum test again; USB is configured.

- Offscreen shader/readback passed on gpu1.
- Two temporary Hyprland sessions started and shut down normally. The software
  session was restored successfully after each. The imported-buffer WARN and
  stuck shutdown from smp2 did not recur.
- With Hyprland's own renderer reporting FD640, swaybg displayed `#2468ac`
  followed by `#ac6824`. A read-only snapshot of the DT-described bootloader
  framebuffer at `0x9c000000` matched **every sampled RGB pixel** for both colors
  (360×780 sample grid, FNV-1a hashes `00cf8945` and `46021f45`). This verifies
  composition through to scanout memory, beyond merely opening an EGL context.
- The existing Quickshell bar loaded and reported `freedreno / FD640`, OpenGL
  4.6. A snapshot shows the Omarchy wallpaper and `omarchy-bringup` top bar.
- A separate 20-second Quickshell animation produced 301/300/300/300 animation
  callbacks in successive 5-second windows and different framebuffer snapshots.
  These are animation ticks, **not measured physical presentation FPS**. Qt
  detected broken vsync throttling and used a timer. Native DPU/DSI/DSC, accurate
  presentation timing, brightness/power management, and touch remain unfinished.
- At uptime 741 seconds, no kernel WARN/Oops/BUG appeared in the collected log.
  An RT-throttling message appeared during testing. This remains a bring-up
  smoke test, not a claim of long-term stability.
- The exact automatic-start helper was tested live: it started Hyprland,
  validated the Lua config, then started swaybg and the existing Quickshell bar.

Live files `/root/run-hypr.sh` and `/etc/hypr/hyprland.lua` now select Adreno;
backups are `/root/run-hypr.software-gpu1.sh` and
`/etc/hypr/hyprland.lua.before-adreno`. **gpu1's embedded init still overwrites
them with its software launcher on reboot.** The accelerated boot change needs
one more flash, described below. User Quickshell configuration was not changed.

**Ready, not yet boot-tested: gpu2 / #174**,
`6.17.0-sm8150-codex-gpu2-g379d8fe35c7c-dirty`.
Build with `bash scripts/rebuild_gpu_desktop.sh`; frozen bundle:
`out/checkpoints/20260916-gpu2-desktop/`. Flash with
`bash scripts/flash_gpu_desktop.sh` in fastboot. Driver source and embedded DTB
are identical to gpu1; the initramfs now waits for real Adreno (~108 seconds),
starts accelerated Hyprland, validates config, then starts wallpaper/Quickshell.
USB still starts first. No desktop render-node alias is created on this path.
Rollback to gpu1: `bash scripts/flash_gpu_test.sh`; to smp2:
`bash scripts/flash_cpu_test.sh`.

Evidence in `out/cpu-test/`: `gpu1-offscreen-test.log`, `gpu1-hypr-results.log`,
`gpu1-hypr-pixels.log`, `gpu1-live-desktop.log`, `gpu1-desktop.png`,
`gpu1-quickshell-animation.log`, `gpu1-startup-helper-test.log`,
`gpu1-final-check.log`. Framebuffer reader: `scripts/read-scanout.c` (read-only,
checks the known DT geometry before mapping; cross-build with aarch64 GCC).

Touchscreen preliminary finding: downstream 18821 `sm8150-oem.dtsi` defines a
Samsung S6SY761 at I2C address 0x48. The current kernel has S6SY761 and evdev as
modules; neither is active and `/proc/bus/input/devices` is empty. Next work
needs the correct mainline DT/controller/pins/supplies and module deployment
or built-in drivers. No touchscreen hardware changes were attempted here.

## GPU desktop experiment (~23:20 PDT)

The temporary Hyprland session on #172 selected **FD640 / freedreno** in
Aquamarine with `AQ_DRM_DEVICES=/dev/dri/card0`, `AQ_NO_MODIFIERS=1`, and the
three software-rendering overrides removed. Aquamarine 0.15.0 can resolve the
sole Adreno render node even though simpledrm owns the display. Hyprland IPC
responded and reported Unknown-1 enabled at 1440x3120@60. This is encouraging,
but does **not yet prove correct accelerated frame delivery**.

Buffer destruction hit `msm_gem_free_object` line 1133, followed on exit by
shmem/GEM release warnings. PID 517 remained stuck with SIGKILL pending;
the attempted software-session restoration did **not** succeed. The script's
original `RESTORED_SOFTWARE_SESSION` message was unconditional and must not be
treated as validation. USB stayed accessible and logs/filesystems were synced.
Evidence: `out/hypr-adreno-full-results.log`.

The fault matches upstream Linux commit
[`c34e08ba6c0037a72a7433741225b020c989e4ae`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=c34e08ba6c0037a72a7433741225b020c989e4ae),
“drm/msm: Fix GEM free for imported dma-bufs”. Imported buffers share a
reservation object but do not own the extra reference used by NO_SHARE
buffers. The old code incorrectly drops that reference. The exact upstream
fix is backported in `kernel/patches/codex-msm-imported-dmabuf-free.patch`.

**Built, not yet flashed/tested:** kernel #173,
`6.17.0-sm8150-codex-gpu1-g379d8fe35c7c-dirty`.
Frozen image/source bundle: `out/checkpoints/20260916-gpu1-dmabuf-fix/`.
Flash using `bash scripts/flash_gpu_test.sh` when serial `$PHONE_SERIAL` is in
fastboot. This targets boot_b/dtbo_b and retains the software boot launcher.
The only tracked kernel source change since smp2 is the upstream fix; config
changes only LOCALVERSION. Rollback remains `bash scripts/flash_cpu_test.sh`.

Next: verify eight CPUs/USB/offscreen GPU on gpu1, rerun the temporary Hyprland
test, check clean shutdown and restore, then verify visible changing frames.
Do not make GPU composition the boot default until those checks pass.
`scripts/test_hypr_adreno.sh` now refuses the known-buggy older kernels and
reports a failed restoration when Hyprland remains stuck.

## Latest verified state (~23:05 PDT)

**Kernel #172, `6.17.0-sm8150-codex-smp2-g379d8fe35c7c-dirty`, is running on
slot B with all eight cores, USB networking, persistent Arch, and working
Adreno shader rendering.** Hyprland and swaybg remain running on simpledrm.

- `online=0-7`; boot log: `smp: Brought up 1 node, 8 CPUs`.
- SHA-256 of the same executable, run concurrently with one process pinned to
  each CPU 0-7, matched on all eight cores.
- The GPU test passed again on this kernel: FD640, RGBA `64,128,191,255`, no GL error.
- The render-node repair ran automatically at ~108 seconds; the canonical node
  is a real Adreno character device, not the startup framebuffer alias.
- At the final check, uptime was 216 seconds, USB was `configured`, all eight
  cores remained online, and the desktop processes were still running. No
  Oops, panic, RCU stall, or GPU fault appeared in the collected kernel log.
- The persistent logger successfully saved its snapshots under
  `/newroot/root/bringup-logs/98eb9612-1223-4318-96e3-36a2cb55842a/`.

This is a successful boot and smoke test, not a long-duration stability test.
GPU rendering is verified independently of the panel; native DSI/DSC and an
accelerated desktop remain unfinished.

Frozen checkpoint: **`out/checkpoints/20260916-8cpu-gpu/`**. It includes boot/DTBO,
config, full tracked kernel diff, untracked bring-up source, embedded DTB,
initramfs archive, and test logs with a checksum manifest. Restore this tested
checkpoint with `bash scripts/flash_cpu_test.sh`; that script no longer selects
the older `smp1` experiment. The original four-core restore image is also retained.

Latest evidence: `out/cpu-test/smp2-first-boot.log`, `smp2-validation.log`,
`smp2-gpu-test.log`, and `smp2-final-check.log`.

### Why the USB wait matters

On this boot, init starts at 16.608 seconds while the DWC3 device was still
unbound at the preceding diagnostic dump. The added loop waits one second,
then sees `a600000.usb` at 17.626 seconds. It binds the gadget at 19.741 seconds.
This strongly supports a startup timing race as the cause of `smp1`'s missing
USB: the old init sampled UDC once and never retried. That failed boot had no
saved phone-side log, so its exact state remains unverified.

## GPU result: hardware shader rendering works

On the restored **#159** kernel, an offscreen GLES test opened Adreno, compiled
vertex/fragment shaders, drew a triangle into a 16x16 texture, and read pixels
back successfully:

```text
EGL 1.5 vendor=Mesa Project
GL vendor=freedreno renderer=FD640 version=OpenGL ES 3.2 Mesa 26.2.2-arch1.1
readback RGBA=64,128,191,255 GL_error=0x0
PASS: Adreno shader rendered and pixels verified
```

The first run used a temporary node `/dev/dri/adreno-test` (226:128). The second
used the repaired canonical `/dev/dri/renderD128`; both passed. The canonical
test also eliminated Mesa's device-information warnings. Kernel logs show
SQE and GMU firmware loading at first open, GMU version 2.0.261, with no GPU
faults reported in the collected post-test logs. Hyprland and swaybg remained
running.

This proves GPU rendering, not hardware-accelerated Hyprland or native DSI/DSC
scanout. The compositor still deliberately uses software rendering on simpledrm.
The completed test did not modeset or take DRM master.

### Render-node repair

The initramfs created `renderD128 -> card0` for early software rendering. That
alias hid the later real Adreno character device. The live repair now exposes
`renderD128` as **226:128**, retaining the old alias as
`renderD128.simpledrm -> card0`.

`scripts/initramfs/fix-render-node.sh` waits for an Adreno render device in
sysfs and replaces only that known alias. It leaves already-open compositor
file descriptors intact and is safe to call again once the device exists.
The staged initramfs and CPU test image include the repair. On the currently
flashed #159 image, the live repair alone is temporary and disappears on reboot.

Test source: `scripts/gpu-render-test.c`. Build with
`bash scripts/build_gpu_test.sh`; requires aarch64-linux-gnu-gcc and host
EGL/GLES2/KHR headers. The resulting executable dynamically loads the phone's
graphics libraries, clears software-rendering overrides in its own process,
and fails if the renderer or returned pixels are wrong.

Run inside Arch, with a timeout:

```sh
busybox chroot /newroot /usr/bin/timeout 30 /tmp/gpu-render-test /dev/dri/renderD128
```

Evidence: `out/codex-gpu-render-test-20260916.log`,
`out/codex-gpu-canonical-test-20260916.log`, and
`out/codex-gpu-postcheck-20260916.log`.

## CPU experiment history

At ~22:28 PDT the checked image and matching DTBO were successfully flashed to
slot B and rebooted (`out/cpu-test/flash.log`). The user reports the Omarchy
wallpaper on screen. The host has not yet seen a USB gadget; kernel identity
and CPU count are therefore **not confirmed**. A cable-only replug was requested.
No crashdump USB device was observed. Do not infer successful eight-core startup
from the wallpaper alone.

The cable replug did not restore USB. **Diagnostic image `smp2` was subsequently
built and successfully boot-tested:** `out/cpu-test/boot-codex-smp2.img`, with the same DTBO.
Checksums: `out/cpu-test/boot-codex-smp2.sha256`. It retains early SMP and adds
a 30-second UDC-discovery wait plus persistent boot snapshots under
`/newroot/root/bringup-logs/<boot-id>/`. The logger records CPU state, USB state,
kernel messages, and processes through 150 seconds after mounting Arch.
The successful boot's logs support a UDC timing race as described above.
If a future test loses USB, restore the frozen working image and retrieve these
files. Rebuild the current staging with
`CPU_TEST_NAME=smp2 bash scripts/rebuild_cpu_test.sh`.

The live kernel starts CPU0 alone and finalizes capabilities before the init
script hotplugs CPU1-3. The kernel's own capability-checking code explains why
a later CPU lacking one of those finalized capabilities is rejected. Historical
logs report the larger cores failing the `32-bit EL1 Support` check; the live
configuration has KVM enabled, which includes that capability check.

The experiment restores normal early SMP startup (`setup_max_cpus = NR_CPUS`)
and the normal `smp_prepare_cpus` handling of `maxcpus=0`. It does not bypass
CPU capability checks. With both CPU types present during feature discovery,
Linux selects their common features. The successful `smp2` boot confirms that
the larger cores start through this path; the boot no longer advertises the
CPU0-only `32-bit EL1 Support` capability.

### Image and isolation

- Working test: **`out/cpu-test/boot-codex-smp2.img`** (96 MiB, header v2).
- DTBO: existing **`out/dtbo-filtered-gpu-sqe.img`**.
- Expected kernel suffix: **`-sm8150-codex-smp2`**, followed by the Git suffix.
- Source copy: `.work/linux-sm8150-codex-cpu`; original kernel source preserved.
- Initramfs staging: `.work/codex-cpu-initramfs`.
- Changes relative to the source snapshot: `kernel/patches/codex-early-smp-test.patch`.
- Rebuild prepared inputs: `bash scripts/rebuild_cpu_test.sh` (default four jobs).
- Working image checksums: `out/cpu-test/boot-codex-smp2.sha256`.

The source copy includes the existing local kernel patches. Its config and
embedded DTB were extracted from `boot-embed-hypr-pin.img`. The existing compiled
DTB is embedded byte-for-byte via `bringup-guacamole.dtb`, so this CPU test does
not pick up the newer experimental DPU device tree. The original tree's dirty
patch and untracked bring-up C file are saved under `out/cpu-test/`.

The live #159 `/init`, `/hypr/run-hypr.sh`, and `/hypr/hyprland.lua` were exported
individually into `out/cpu-test/live-boot-scripts.log` and used for the test
initramfs, with the render-node repair, UDC wait, and persistent logger added.
Other initramfs files came
from the existing staging directory. The old external ramdisk is preserved;
this kernel uses its built-in initramfs.

DPU startup is now opt-in in the test source (`bringup_usb.dpu=1`); the test
image leaves it off. Both the embedded DTB command line and the boot header
omit `maxcpus=0` and `iommu.passthrough=1`. The packer now accepts `BOOT_CMDLINE`
so the header can match the selected embedded device tree.

Validation completed: successful kernel build; header v2 and 96 MiB partition
size; ARM64 magic and text offset; exact embedded known-good DTB; built-in
render-node helper; absence of the later DSI fill startup; matching checksums.

### Flash and rollback

Phone serial is `$PHONE_SERIAL`. After the user enters the START/fastboot menu:

```sh
bash scripts/flash_cpu_test.sh
```

The script verifies the frozen eight-core checkpoint hashes, targets this serial explicitly,
flashes only `boot_b` and `dtbo_b`, selects B, and reboots. Slot A, userdata,
bootloader firmware, and vbmeta are not written.

Known-working rollback pair remains untouched:

```sh
fastboot -s $PHONE_SERIAL flash boot_b out/pmos/boot-embed-hypr-pin.img
fastboot -s $PHONE_SERIAL flash dtbo_b out/dtbo-filtered-gpu-sqe.img
fastboot -s $PHONE_SERIAL set_active b
fastboot -s $PHONE_SERIAL reboot
```

After the test boot: capture dmesg, confirm the new kernel suffix and
`online=0-7`, verify USB and UFS, then repeat offscreen rendering after the
delayed GPU starts. If early boot stalls, photograph the console and use the
hardware key combination to return to fastboot. Do not use the known-broken
`/proc/bringup_reboot_bootloader` helper.
