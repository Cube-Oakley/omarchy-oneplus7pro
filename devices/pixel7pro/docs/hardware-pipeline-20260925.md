# GS201 hardware pipeline — September 25, 2026

The user confirmed physical touch but explicitly prioritized proper CPU/GPU and
display support over further tuning of the temporary GPIO/retained-framebuffer
paths. The touch experiment is preserved in [its checkpoint](touch-bringup-20260925.md).
Current follow-ups: [v14 CPU/thermal](power-bringup-20260925.md) and
[v15 GPU](gpu-bringup-20260925.md). Panthor firmware startup now works;
hardware shader/readback, runtime resume and Hyprland rendering now pass.
Full DPU/DSI display scanout remains unfinished.
The [v16 display investigation](display-pipeline-20260925.md) measures the
retained-buffer copy bottleneck and investigates the reported horizontal tearing.

## Measured baseline

The final native v11d session had CPUs 0–7 online, working GIC/timer interrupts,
and no cpufreq policies or thermal zones. Hyprland rendered with llvmpipe and the
Pixel DRM bridge copied frames to the bootloader's retained scanout buffer. A
running compositor is not evidence of GPU rendering, hardware page flipping or
Linux ownership of panel power/sequencing.

After unloading the touch module and verifying pin restoration, the phone was
intentionally rebooted into the stock kernel for read-only reference inventory.
This is diagnostic work, not a new requirement to return to Android after each
stage. No partitions were flashed.

Stock evidence in `out/checkpoints/20260925-hardware-pipeline/stock-inventory.txt`:

- GPU identifies as `Mali-G710 7 cores r0p0 0x0A080602`. The final hex value is
  the vendor driver's **product ID**, not a raw MMIO GPU_ID register dump.
- GPU uses separate top-level and shader clocks, and top/cores power domains.
  Stock exposes firmware scheduling controls and ships `mali_csffw-r48p0.bin`
  through `-r51p0.bin`. Firmware compatibility with Panthor is not yet verified.
- Stock CPU policy groups are 0–3, 4–5, 6–7, controlled by `exynos_cpufreq`.
  Native CPU online state must not be mistaken for working DVFS.
- Stock display binds `exynos-decon` at 0x1c240000 and `exynos-dsim` at
  0x1c2c0000, along with DPP and display SysMMU devices. These are not the old
  upstream Exynos7/5433 display blocks merely because some names match.

The checked Linux tree's Panthor driver recognizes Mali-G710 and implements the
CSF interface (`panthor_hw.c`, `panthor_fw.c`). It is the intended kernel rendering
path to validate. Mesa's [Panfrost documentation](https://docs.mesa3d.org/drivers/panfrost.html)
explains that Mali rendering and display scanout are separate; its current
supported-device table does not establish this particular Pixel integration.
Do not claim a tested Mesa/Panthor stack from GPU family similarity alone.

## Dependency order and acceptance criteria

1. **Firmware/clock foundation:** GS201 ACPM mailbox, SRAM channels and common
   clock framework; GS201-specific CMU and PMU/genpd dependencies. First runtime
   acceptance is bounded frequency queries with stable USB/reboot, without any
   frequency-setting request or CPU governor activation.
2. **CPU power and thermal:** validated CPU OPP tables, firmware-managed voltage
   and clock transitions, temperature readings and cooling. Acceptance includes
   measured frequency changes and thermal reporting before sustained workloads.
3. **GPU rendering:** GS201 GPU domains and both clocks, correct IRQ ordering,
   DMA coherency/IOMMU behavior and compatible CSF firmware; then Panthor render
   node and a hardware EGL shader/readback test. A render node alone is not success.
4. **Display scanout:** DPU/DPP + SysMMU, DECON, DSI host/PHY and S6E3HC4 panel
   sequencing. Replace the retained-buffer copy with real atomic KMS, vblank and
   page flips. Validate DMA-BUF import, fences and buffer lifetime before removing
   the bridge. GPU acceleration alone would still leave the CPU-copy bottleneck.
5. **Integrated compositor:** shared userspace, actual hardware renderer selected,
   synchronized scanout and physical input; measure frame and input latency.
   Replace GPIO touch transport with standard pinctrl/SPI/IRQ while retaining the
   verified report parser/geometry. No Pixel workaround belongs in shared OS code.

This order has parallel source work, but the runtime dependencies are real.
Keep the v11d display/USB image and archived userspace as independent fallbacks.

## First upstream-style driver increment

Prepared `devices/pixel7pro/kernel/acpm-foundation/` as two patches, separating
bindings from driver changes. The patches are also applied to the working kernel
source tree. They add explicit `google,gs201-acpm-ipc`, `google,gs201-mbox` and
`gs201-acpm-clk` matches to existing Linux framework drivers. Clock probe now
selects its data from the platform ID instead of hardcoding GS101.

This reuse is based on comparison against pinned GS201 vendor code:

- ACPM SRAM initdata offset 0xa000, channel-table offset field at +8 and AP channel
  count (`ipc_ap_max`, **not** `num_ipc_channels`) at +24.
- 72-byte IPC channel descriptor; queue offsets/length/message-size and polling
  flag agree with the upstream representation.
- AP doorbell INTGR1=0x40 and interrupt mask INTMR0=0x28, 16 mailbox channels.
- DVFS clock IDs 0–13: MIF, INT, CPUCL0/1/2, G3D, G3DL2, TPU, INTCAM, TNR, CAM,
  MFC, DISP, BO. The vendor clock node uses channel 0.
- Stock GS201 mailbox is at 0x18210000; SRAM at 0x18500000, size 0x48000.
  GS101 physical addresses must not be copied.

The three modified driver translation units cross-compile without warnings.
Both patches pass checkpatch with zero errors/warnings. Binding schema checks are
recorded separately in the evidence directory.

**Now hardware validated in a later increment:** the GS201 CMU_APM subset,
mailbox and ACPM queue handling run in RAM-only v13 images. The phone answered
CPU/GPU/display frequency queries and all seven mapped temperature queries.
See [the v13 record](acpm-bringup-20260925.md) for measurements, exact image hash,
transport fixes, source checkpoint and limitations. The original two patches
above remain the historical compile-only starting point. Later v14 verifies
CPU frequency changes and thermal cooling; v15 advances GPU bring-up. Full
display scanout remains unfinished.

## Source provenance

Official vendor research revisions (matching family; exact stock build manifest
still unverified):

- [GS201 kernel](https://android.googlesource.com/kernel/gs/+/b3c9095e01cefb36f35723b5c66638bf15f5144a/)
- [GPU](https://android.googlesource.com/kernel/google-modules/gpu/+/14fdd7d6beeb8d54b027634eb519251b27d9e8e1/)
- [Display](https://android.googlesource.com/kernel/google-modules/display/+/0137241105270acf53c329e899ea9c4b6b1c8e66/)

Relevant downloaded sources, commits, raw stock inventory and validation logs are
kept in `out/checkpoints/20260925-hardware-pipeline/`. Kernel base remains pinned by
`devices/pixel7pro/kernel/kernel-base.txt`. This work made no OnePlus changes.
