# Pixel display pipeline — September 25, 2026

Hardware rendering now works through Panthor and the isolated Mesa G710 build.
The remaining display bridge still converts and copies pixels into ABL's single
retained buffer. It does not provide real page flips or hardware vblank events.
Image D fixes the separately validated color-layout and shared-buffer cache bugs.
The user confirms clean moving edges; pauses and frame rates below 60 fps remain.
The investigation below preserves the intermediate hypotheses and measurements.

## Measured bottleneck

With v16 image A, bounded CPU schedutil and the validated GPU clock pair, a
12-second full-screen `weston-simple-egl -f` run under Hyprland produced:

| Measurement | Result |
|---|---:|
| Driver update count delta | 275 |
| Mean CPU conversion/copy wall time | 21.16 ms |
| Mean retained refresh/trigger wait | 12.21 ms |
| Application frame counts, two 5-second windows | 22.8 and 23.4 fps |
| G3D temperature after the run | 41°C |

An independent native dumb-buffer test measured 22.39 ms mean copy time and
7.18 ms refresh time over nine updates, without GPU rendering. These are short
diagnostics, not optical latency measurements or sustained performance results.
The Hyprland counter delta can include incidental shell commits.

A 120 Hz frame has 8.33 ms total; even 60 Hz has only 16.67 ms. The copy alone
exceeds both budgets. Raising GPU clocks cannot remove this display-side cost.
Google specifies an up-to-120-Hz panel, and the pinned S6E3HC4 driver contains
1440×3120 modes at both 60 and 120 Hz. The retained bridge's synthetic 60-Hz
mode does not establish the actual panel timing.

## Synchronization investigation

The bridge waits for DECON shadow-register requests to clear, then restores the
masked hardware TE trigger. Register latching is not proof that the frame has
finished reading memory. The vendor driver separately checks GLOBAL_CON's idle
bit (bit 5) and frame completion. Overwriting the sole buffer before completion
could explain tearing; this remains a hypothesis until measured.

The upstream sysfb helper already brackets framebuffer CPU reads with
`drm_gem_fb_begin_cpu_access` / `end_cpu_access`. Do not diagnose missing DMA
cache synchronization merely because this is a temporary bridge.
The DRM atomic helper also defaults to GEM fence preparation when the plane
does not supply `prepare_fb`, then waits for those fences before commit.

Image B adds counters for display-busy status before copying and after refresh.
Its runtime `pixel_handoff.wait_idle` diagnostic defaults off, preserving the
baseline. When enabled it requires the hardware trigger to be masked and waits
at most 100 ms for DECON idle before writing (including plane disable). A failed
wait skips the write and logs an error; this diagnostic failure path is not a
complete DRM error-recovery implementation. No DMA address, display mode, clock,
panel command or interrupt configuration is changed by this experiment.

Image B runtime results, idle wait disabled/enabled/disabled:

| Run | Updates | Busy at update entry | Idle-wait timeouts |
|---|---:|---:|---:|
| Separate launches, off | 306 | 160 | 0 |
| Separate launches, on | 299 | 0 | 0 |
| Separate launches, off again | 304 | 0 | 0 |
| Continuous animation, off | 299 | 1 | 0 |
| Continuous animation, on | 309 | 0 | 0 |
| Continuous animation, off again | 316 | 0 | 0 |

Every measured refresh returned before the idle bit asserted. Busy-at-entry is
sampled before the sysfb helper, not at the first actual framebuffer store; it
establishes a missing completion guarantee but does not prove that a particular
visible artifact came from simultaneous memory access. The intermittent baseline
prevents claiming the idle guard fixes all tearing. Continuous-animation output
was 25.0–26.8 fps in five-second windows; G3D was 40°C after all six phases.
The guard remained enabled for the subsequent thermally monitored visual test.

The user supplied four photos (`IMG_20260925_1307*.jpg`) showing streaked triangle
edges and a strongly blue background. A frozen compositor screenshot and a
read-only capture of the retained framebuffer match **exactly for all RGB
components** when the buffer is decoded as the bridge's intended BGRA format
(4,492,800 pixels). This verifies that frozen-frame conversion/copy, not the
physical panel's interpretation. The blue photo colors warrant a separate format
investigation. The previous September 24 standalone probe used `0xff181818`
for gray and its physical photo appears gray, despite the same DPP format code 0.
The apparent mismatch must be resolved with explicit color/alpha validation.
The user then confirmed the background is blue in person, with cyan/pink,
glitchy/flashy triangle colors. Thus this is not merely a camera color cast.

Image C replaces the channel rotation with opaque ARGB words (`0xffRRGGBB`),
matching the original standalone probe, and defaults the idle guard on. Its
diagnostic `legacy_bgra` parameter reproduces the old rotation for comparison.
Probe guards now also check active-shadow DPP format/base/dimensions. This
changes framebuffer contents only; no display register format is reprogrammed.
**Physical labeled-color validation passes:** the user reports the new card
looks right, and `IMG_20260925_132200_634.jpg` shows red/green/blue bars matching
their labels, a dark background, white checkerboard and amber block. The native
DRM test also passes its modeset and all eight flip events. Motion validation is
the next check. This establishes the byte layout of this retained ABL path,
not a universal reinterpretation of the vendor driver's format constants.

Image C also passes the hardware Mali shader/readback test before starting
Hyprland. A subsequent animation sample spans 1,357 updates with a 14.43 ms mean
copy and 13.71 ms refresh wait, zero busy-at-update-entry samples and zero idle
timeouts. Application windows report 24.6–27.6 fps; G3D is 41°C. This is a
separate short diagnostic, not a controlled speedup benchmark. It still exceeds
the 120-Hz frame budget before rendering cost is counted. Evidence:
`c-hyprland-start.txt`, `c-animation-sample.txt`, `c-timing-results.json`.

The image-C touch module was rebuilt and restored after this measurement for a
bounded 600-second input session; it is still the temporary GPIO SPI transport.
The visual demo is separately limited to 300 seconds. Physical moving-image
feedback confirms the black background and better colors, but **motion remains
glitchy** (`IMG_20260925_132544_301.jpg`). The idle guard did not cure the main
artifact. A subsequent 60-second direct KMS test, with eight immutable CPU-made
buffers and no GPU/compositor, completes 1,530 flips in 60.026 seconds. The user
reports perfectly clean edges with no trails. The GPU desktop restarts afterward.
This redirects investigation to rendered-buffer sharing rather than panel timing.

`mainline/pixel-gpu-scanout-test.c` creates a display-owned dumb buffer, exports
it as DMA-BUF, imports it as an EGL render target, warms a CPU mapping, then
clears it red/green/blue with `glFinish()` and standard DMA-BUF CPU-access ioctls.
Image C fails all 1,024 pixels in each phase: CPU reads remain zero. An initial
run was partly stale (912/1,024), consistent with a cache-dependent failure.
Imported linear-image `glReadPixels` may itself use CPU mappings and is not an
independent GPU-side oracle in this test. Evidence: `c-gpu-scanout-cache*.txt`.

Source review reveals the earlier CPU-access conclusion was incomplete:
`drm_gem_fb_begin_cpu_access()` only synchronizes **imported** objects. Mesa kmsro
allocates these buffers through the display device and exports them to Panthor,
so they remain locally owned by the bridge. Default shmem vmap is cached, and
the default GEM DMA-BUF exporter has no begin/end CPU-access callbacks. The GPU
overlay does not claim DMA coherency. Image D tests the standard shmem `map_wc`
allocation path for local objects, with counters distinguishing local cached,
local write-combined and imported updates. **Image D passes the identical
regression: zero mismatched pixels in all three phases, with correct GLES
readback as well.** This confirms the cache-coherency correction for the
display-owned buffer path. Evidence: `d-gpu-scanout-cache.txt`. The same pinned
Mesa build and test binary were used on C and D. **The user confirms the GPU
triangle's moving edges are now clean and the glitchy issue is fixed.** Slight
pauses and a frame rate clearly below 60 fps remain. Thus the byte-layout fix
and shared-buffer cache fix are separately validated, while smooth 120 Hz is
still unfinished.

Image D counters confirm the compositor uses local write-combined objects,
with zero local cached or imported update samples in the initial run. The first
animation windows were about 4.4 fps, then 17.4–19 fps; G3D remained 41°C and
the idle guard had no timeouts. This correct mapping makes every read reach
memory instead of reusing stale cached pixels, exposing the cost of the temporary
CPU-copy bridge. Startup and steady-state windows differ; do not present this as
a stable benchmark or claim all remaining pauses have been explained. True
buffer import/scanout and completion IRQs remain the intended performance path.
The completed demo is stopped and the rebuilt touch module enabled for a
600-second session, leaving the hardware-rendered mobile UI running in RAM.
The regression can be built with cross GCC using `-O2 -Wall -Wextra -Werror
-I/usr/include/libdrm -idirafter /usr/include` and `-ldl`; the last include path
supplies graphics API declarations without replacing the target libc headers.
Run it with the same isolated Mesa environment as the normal shader test. It
never acquires DRM master, changes scanout, or maps hardware registers.

Evidence: `b-sync-aba.txt`, `b-sync-continuous.txt`, `b-frozen.png`,
`b-scanout.bin`, `pixel-compare.json`, and `b-display-shadow.txt`.
Both regular and active-shadow DPP registers report format 0 and the same
retained buffer. Vendor `Kbuild` selects the shared cal_9845 implementation plus
GS201-specific cal_9855 additions; those additions are now pinned too.

## Read-only register inventory

`mainline/pixel-display-inspect.c` checks machine identity, the bound retained
driver, exact DT register ranges and DPU/DISP power before reading known active
DPP0, DECON0 and DSIM0 registers. The safe inventory confirms the retained
buffer at `0xfac00000`, 1440×3120 dimensions and powered display domains.

An earlier inventory attempt included unvalidated SysMMU offsets. Its SSH command
ended with status 255 after reading offsets 0/4/8 and before printing offset 0xc.
The kernel, USB, subsequent SSH and compositor remained alive; no reboot or kernel
fault was recorded. The cause is unconfirmed. SysMMU reads were removed from the
tool. Those zero values are **not evidence that the display IOMMU is disabled**.
The GS201 vendor driver has a virtualized register layout and access dependencies
that must be understood before further probing.

## Next production driver work

Replace the copy bridge with DPU/DPP scanout, display SysMMU mappings, atomic
buffer lifetime/fence handling and real completion interrupts. Then implement
DSI/PHY and panel ownership, including coordinated DSC/TE/clock changes for
120 Hz. The panel's vendor sequence is more than changing a DRM mode clock.
Standard hardware SPI/IRQ touch remains a separate latency dependency.

## Checkpoints and sources

- Evidence: `out/checkpoints/20260925-display-v16/`, including timing logs,
  `timing-results.json`, safe/failed inventories and pinned research manifests.
- Image A: `image-a/boot-pixel-shell.img`, SHA256
  `4d828ca51fc0f170273a6af5ea695792b9f63cc2b6ae98aa414a7d734cb78118`.
- Image B: `image-b/boot-pixel-shell.img`, SHA256
  `e51db556a438071d3a3ec77064b81dccde91aee36cb342ea49823981a434fa4f`.
- Image C: `image-c/boot-pixel-shell.img`, SHA256
  `53675aca969bf6714ee4a1ef318ffd52fb2566a2522e3d658c3d5b1a1cf579d1`.
- Image D: `image-d/boot-pixel-shell.img`, SHA256
  `b8479c90bfb58f9758f597393d56205794f0989fce1aa12466647b9c5480d2de`.
- Kernel: `7.3.0-rc2-pixel-display16-g5225b8eec4c9-dirty`; 1800-second
  automatic reboot. All phone userspace is in RAM. No partitions flashed.
- Image A cumulative source/config: `devices/pixel7pro/kernel/display-v16/image-a/`;
  clean-base patch apply verified. The prior v15 checkpoint remains independent.
- Image B source/config is saved alongside it in `image-b/`; clean-base patch
  apply and compilation pass. The B-only change passes checkpatch with no errors
  or warnings. Image A's timing patch had two pre-existing style warnings.
- Image C has its own cumulative source/config checkpoint, clean-base apply
  verification, successful compile and a clean checkpatch for the C-only change.
- Image D also has a full clean-base-checked patch/config and successful compile.
  Its incremental checkpatch has no errors and one style warning preferring
  `kzalloc_obj` over the equivalent explicit-size `kzalloc` allocation.
- Final evidence: `d-gpu-scanout-cache.txt`, `d-hyprland-start.txt`,
  `d-animation-sample.txt`, `d-final-health.txt`, and the user's explicit clean-edge
  confirmation. Both the original shader test and the new sharing regression pass.
- [Google Pixel specifications](https://support.google.com/pixelphone/answer/7158570?hl=en).
- [Pinned Google display source](https://android.googlesource.com/kernel/google-modules/display/+/0137241105270acf53c329e899ea9c4b6b1c8e66/),
  especially `samsung/cal_9845` and `samsung/panel/panel-samsung-s6e3hc4.c`.
- Pinned GS201 `samsung-iommu` sources at kernel/gs commit
  `b3c9095e01cefb36f35723b5c66638bf15f5144a`; research manifest records hashes.
  Do not substitute the older `exynos-iommu` driver based on its name.

## Image D replay notes

Use the existing checked RAM boot helper with image D and its hash above.
Activate ACPM first, wait for seven thermal zones and inspect temperatures before
enabling bounded CPU scaling. Enable the GPU domains in a separate command and
wait for their provider to bind before the validated cycle/render sequence.
Set each CPU policy to `schedutil`; keep the GPU at the v15 validated clock pair.
Do not collapse these asynchronous probe steps into a single immediate sequence.

Restore the unchanged mobile archive via `scripts/start-pixel-arch.py` (SHA256
`9b204df8aff3f54625f347d11d4e1370b44a83aef12e6371d588c8581ba54e57`). Install
the isolated Mesa package and shader test from the v15 checkpoint into RAM, then
use `scripts/pixel-gpu-session-start.sh`. Mount debugfs inside the Arch chroot
to read `/sys/kernel/debug/dri/0/pixel_timing`. Image D defaults to
`wait_idle=Y`, `legacy_bgra=N` under `/sys/module/pixel_handoff/parameters/`.

`scripts/pixel-display-sync-test.sh` runs a bounded off/on/off idle-wait comparison
with one renderer and restores the prior setting on exit. It should only be
repeated to answer a new synchronization question. The completed baseline tests
are already preserved. The separate `visual-check.sh` in the evidence directory
limits the demo to five minutes and stops if any checked thermal zone reaches
55°C or returns an invalid reading; normal kernel thermal protection stays active.

The current session's private USB SSH wrapper and NetworkManager UUID live in
`arch-session-d/`. A/B/C host profiles were removed after their sessions rebooted.
After the current RAM session ends, remove its temporary host network profile
using the UUID in `arch-session-d/session.json`; phone files vanish on reboot.
