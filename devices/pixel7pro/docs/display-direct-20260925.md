# Pixel native DMA scanout — September 25, 2026

The v16 D color/cache fixes remain the independently saved visual baseline.
The user confirmed its GPU animation has clean edges but remains below 60 fps.
This continuation removes the CPU-copy bridge in stages, using RAM boots only.

## Verified prerequisites on v16 D

`mainline/pixel-decon-irq-probe.c` observes DECON0 frame-start and frame-done
interrupts for 30 seconds, automatically restoring the original interrupt mask.
It checks cheetah identity, the retained driver, live DT register/IRQ resources,
display power and retained DPP state. Only the global interrupt enable and the
two write-one-to-clear pending bits are changed. The test recorded 67 starts,
67 completions and 67 paired transfers, with no unpaired interrupt. Mean paired
start-to-done time was 7.109 ms, maximum 9.314 ms. These are controller transfer
times, not optical latency or panel refresh measurements. Restored mask: 0x3000.

`mainline/pixel-sysmmu-inspect.c` first reads the hardware version and capability
registers used by the pinned Samsung driver's probe. Only after validating these
does it select the VM register layout. This resolves the earlier unknown-layout
probe without repeating the unsupported non-VM page-table-base read at 0x000c.

DPU0 SysMMU results:

| Register | Value | Meaning |
|---|---|---|
| VERSION | 0x80200001 | SysMMU 8.1.0 |
| CAPA0 | 0x41085800 | CAPA1 present |
| CAPA1 | 0x0000e0a1 | VCR, no-block mode, 10 TLBs, 1 port |
| GLOBAL_CTRL / CFG / STATUS | 0 / 0 / 0 | Non-secure global controls disabled |
| VM0_CTRL / CFG | 0 / 0x00020000 | VM0 translation disabled |
| VM0_FLPT_BASE | 0 | No VM0 page-table base |

No SysMMU, secure-alias or S2MPU register is written. This inventory does not
establish general IOMMU or protected-memory support. The guarded retained path
can test physically contiguous DMA allocation without changing these controls.

`mainline/pixel-dma-scanout-probe.c` uses `dma_alloc_wc` and a 32-bit DMA mask
for an immutable 1440×3120 RGB/checkerboard buffer. Hyprland is paused throughout.
The display changes only its RGB base and the previously validated refresh/IRQ
registers. It waits for real frame-done, idle and matching active-shadow address.
After 15 seconds it restores the original buffer with the same checks; only then
may the DMA allocation be freed. Failure retains potentially active memory until
reboot instead of risking DMA access to freed pages.

The 17,973,248-byte allocation at **0xfe400000** scanned out successfully. The
user confirmed the three colored bars and bottom checkerboard. The original
**0xfac00000** framebuffer was restored successfully, with two starts and two
matching completions. Both probe modules were unloaded and Hyprland resumed.
This establishes actual scanout from a Linux-owned buffer without a pixel copy.

Evidence: `out/checkpoints/20260925-display-direct/irq-{load,motion,result}.txt`,
`sysmmu-caps.txt`, `memory-layout.txt`, `dma-first.txt` and `d-health.txt`.
Both kernel probes compile and pass checkpatch with zero errors/warnings; the
read-only userspace inspector compiles with `-Wall -Wextra -Werror`.

## Native DRM implementation

`drivers/gpu/drm/sysfb/pixel_scanout.c` is a separate driver selected by
`CONFIG_DRM_PIXEL_SCANOUT`; the v16 retained-copy source and image are preserved.
The build helper's `--direct-scanout` enables v17 and the full validated thermal,
CPU and GPU chain. A 128-MiB CMA pool below 4 GiB backs standard GEM DMA buffers.
The actual boot reservation is 0xeb200000–0xf31fffff.

The driver uses the normal GEM DMA allocation/export/import helpers and simple
KMS atomic helpers, including the normal implicit-fence preparation. It accepts
only full-screen linear XRGB8888 at the validated pitch/dimensions and a 32-bit
contiguous DMA address. It never maps framebuffer pixels for a CPU copy.
The actual DECON frame-done interrupt updates DRM completion accounting. An
update waits for frame-done, idle and the expected active DMA address before
releasing its prior framebuffer reference or reporting its page-flip event.
Failure rejects later commits and retains potentially active objects; disabling
restores the original ABL buffer before dropping those extra references.

The completion counter is **on-demand frame-done**, not continuous TE/vblank
while idle. The advertised fixed mode remains nominal 60 Hz. Real panel-mode
ownership, 120 Hz, DSI/DSC/PHY, display power/clock management and SysMMU mappings
are still separate work. Contiguous imports are supported through the standard
DMA helper; arbitrary scattered buffers require the future IOMMU work.

Image A was a compile-only attempt missing the DRM print header; no phone boot.
Image B builds without compiler warnings and passes checkpatch. Its complete
patch passes a clean-base apply check and is saved in
`devices/pixel7pro/kernel/scanout-v17/image-b/`.

- Image: `out/checkpoints/20260925-display-direct/image-b/boot-pixel-shell.img`.
- SHA256: `00132ed2bd1e45258b053afceb35e8a49e592dcae307d1a4fbca83593bc2addb`.
- Kernel: `7.3.0-rc2-pixel-scanout17-g5225b8eec4c9-dirty`.
- Base: `5225b8eec4c9bb21aecff6295fab6346a3c3738e`.
- Automatic reboot: 1800 seconds; no flash, slot change or OnePlus modification.
- D's temporary host network profile was deleted after that RAM boot ended.

The isolated DMA test is followed below by native KMS, GPU-sharing and desktop
validation; each establishes a different part of the pipeline.

Primary register sources remain pinned in the v16 research manifests:
[Google display](https://android.googlesource.com/kernel/google-modules/display/+/0137241105270acf53c329e899ea9c4b6b1c8e66/)
and [GS201 Samsung IOMMU](https://android.googlesource.com/kernel/gs/+/b3c9095e01cefb36f35723b5c66638bf15f5144a/drivers/iommu/samsung-iommu.c).

Image B's native KMS test passed the modeset and eight page flips, with ten
completed transfers including disable/restore, zero DMA failures and no CPU
copies. It nevertheless produced `drm_atomic_helper_wait_for_vblanks` warnings:
the generic commit tail awaited a *subsequent* vblank after the synchronous
command-mode transfer was already complete. A panel idle between requested
updates need not produce another completion. This is not a DMA timeout.

Image D replaces that tail wait with `drm_atomic_helper_wait_for_flip_done`,
using the event already delivered after confirmed hardware completion. It also
sets the fixed mode's human-readable name. Image C was a compile-only attempt
missing the atomic state declaration header. D builds without compiler warnings,
passes checkpatch and a clean-base cumulative patch check. D image SHA256:
`8f8c6ae4d353452c6e76ecfc7ff086abd297cf81d844541fadddc83f8fef0fb0`.

Image D's native KMS retest passes all eight page flips and restore, again with
10 matched starts/completions, zero DMA failures, and zero CPU pixel-copy bytes.
The generic post-transfer vblank timeout is gone. The fixed mode is named
1440x3120. Thermal sensors, bounded schedutil CPU policies and Panthor activation
work as in v16. Evidence: `d-kms.txt`, `d-power.txt`, `d-gpu-enable.txt`.
The GPU provider's actual driver name is `gs201-g3d-pd`; the preliminary listing
in the GPU-enable log used `gs201-g3d-pmu` and is not a provider failure. The
subsequent successful power cycle, GPU_ID and Panthor bind verify activation.

## Replay and lifetime constraints

Build with `python scripts/build-pixel-shell.py --output <new-directory>
--direct-scanout --seconds 1800`. Boot only through the existing checksum-guarded
`scripts/boot-pixel-shell.py`. Activate ACPM, inspect all seven temperatures,
then enable bounded cpufreq and GPU domains. Wait for the `gs201-g3d-pd` provider
before cycle/render activation; set each CPU policy to schedutil.

The source probes are development experiments, not concurrent production
owners of the display. Never load either IRQ probe alongside v17: v17 owns those
interrupts and its DMA base is no longer the fixed ABL address. The DMA probe
requires the v16 compositor stopped for its entire lifetime. The automatic timer
restores the old base; unload only after checking the restore log. Any failed
restore retains memory until reboot. No probe uses a partition or block device.

For v17, provision the unchanged mobile archive with `start-pixel-arch.py`, install
the pinned `/opt/pixel-mesa` archive and run the shader/sharing regressions before
launching the desktop. `scripts/pixel-gpu-session-start.sh` accepts scanout17 and
still enforces the hardware shader gate. Debugfs statistics are now
`/sys/kernel/debug/dri/0/pixel_scanout`, replacing the copy-specific `pixel_timing`.

The old CPU motion diagnostic requires eight full-resolution buffers (about
137 MiB), exceeding the new 128-MiB low-address DMA pool. The checkpoint contains
`pixel-kms-motion-four.c`, a four-buffer derivative (about 69 MiB) with unchanged
immutable-buffer flip/event validation. This pool is for scanout allocations;
it does not reduce all GPU memory to 128 MiB.


## Hardware-rendered userspace on image D

The unchanged shared mobile rootfs and isolated Mesa build restore successfully.
Both the Mali-G710 shader test and the identical three-phase shared-buffer test
pass (zero mismatches in all 3,072 checked pixels). The four-buffer native KMS
motion control completes **721 flips in 12.002 seconds, about 60 fps**, with
zero hardware transfer failures and successful return to the ABL buffer.
This is a short throughput test, not a sustained latency measurement.

Hyprland starts with the standard hardware gate, followed by the same shared
mobile shell, Kitty and keyboard. A Weston EGL animation, later confirmed tiled and translucent, initially
reports **46.2 and 53.8 fps** in five-second windows. The driver reports native
DMA addresses alternating between Linux-owned buffers, no pixel-copy path and
zero failed transfers. G3D is 42°C; all seven zones are 42–46°C in that capture.
The CPU policies remain bounded schedutil and GPU clocks remain at the validated
302/202-MHz pair. This does not yet establish perfectly paced 60 Hz or 120 Hz.
The subsequent physical feedback below confirms the GPU animation.

Evidence: `d-gpu-and-motion.txt`, `d-hyprland-start.txt`,
`d-animation-initial.txt`, `d-animation-sample.txt`, and
`d-animation-screenshot.png`. The visual test has a 180-second deadline and
checks every thermal zone every two seconds, stopping at 55°C or invalid data.
Kernel thermal protection remains active. The desktop remains in RAM afterward.

A longer sample reaches 58.0–60.2 fps in multiple five-second windows, with one
56.2-fps window and the lower startup windows above. There are 4,290 matched
starts/completions, zero failures and no CPU pixel-copy path at uptime 350.76s.
The screenshot shows a clean RGB triangle in a translucent tiled window beside
Kitty. Hyprland did not honor the initial fullscreen request. These measurements
are for that composed desktop scene, not a full-screen opaque GPU test. A screenshot alone cannot validate panel presentation; see the subsequent
physical confirmation below.


The second run uses `weston-simple-egl -f -o` after Kitty is fully mapped.
Hyprland confirms fullscreen=2, position 0,0 and size 480×1040 at scale 3
(the 1440×3120 output). A second screenshot shows the RGB triangle on black.
Two attempted legacy `hyprctl dispatch` commands were rejected by this Lua
Hyprland build and made no changes; the client's own fullscreen request was
already effective, as the captured client state confirms.

The verified fullscreen opaque run initially reports 56.2, 60.2 and 57.2 fps.
Driver failures remain zero, G3D 42°C. A live sample may contain one more start
than done because a transfer is in progress; that is not a dropped frame.
Evidence: `d-fullscreen-state.txt`, `d-fullscreen-sample*.txt`,
`d-fullscreen-screenshot.png`. The windowed and fullscreen samples are kept
separate. These are application five-second averages, not proof of perfect
frame pacing or optical refresh timing.


**Physical GPU validation passes:** the user reports that the image looks right
and is now pretty smooth, clearly smoother than before. 120 Hz remains the goal.
The longer opaque fullscreen sample spans 56.2–60.2 fps in five-second windows,
mostly 57–60 fps; this does not claim perfect pacing. The animation is stopped
and the exact-kernel touch module restored for a bounded 600-second session,
leaving the hardware-rendered shared mobile UI available. Final evidence is
`d-final-health.txt`; no flash or slot change occurred.

The repeatable diagnostic is `scripts/pixel-direct-display-test.sh`. It requires
the validated scanout17 RAM kernel, checks temperatures and refuses to label a
run fullscreen unless Hyprland reports fullscreen=2. Let desktop startup settle
before invoking it. The session's temporary host profile UUID is
`4456097d-ac96-41e1-9430-086058b67457`; remove it after this RAM session ends.

Next work: full panel/DSI/DSC/TE and display clock/power ownership for 120 Hz,
continuous timing instrumentation and frame pacing; then standard display IOMMU
mappings for scattered buffers and hardware SPI/IRQ touch. Native DMA scanout
removes the measured CPU-copy bottleneck without solving all those dependencies.

Final health at uptime 576.53s: **16,197 starts, 16,197 completions, zero failed
transfers**, no CPU pixel-copy path, G3D 42°C and all zones 42–46°C. The exact
scanout17 touch module registers successfully for 600 seconds. A final shared
mobile UI screenshot is saved as `d-mobile-screenshot.png`. The boot's automatic
reboot remains at 1800s; phone files and the userspace install are entirely RAM.
