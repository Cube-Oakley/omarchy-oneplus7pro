# Display timing measurement — 2026-09-17

**Update:** native2 #179 now boots native DSI at 1440×3120@60, with FD640
rendering and Quickshell reporting vsync 16.67 ms/swap interval 1. Native1
page flips measured mostly 59.94 Hz and static colors were user-confirmed.
See [native display evidence](native-display-work-20260917.md). The simpledrm
measurements below are historical; do not use their `/dev/mem` sampler on the
new native buffers. Real interaction frame pacing and 90 Hz remain future work.

## Historical simpledrm baseline

Linux reports 1440×3120@60 Hz as the only available output mode. This is the
simple-framebuffer driver, not native MSM DPU/DSI panel control. Its 60 Hz
mode is synthesized by `DRM_MODE_INIT(60, ...)` in the current kernel's
`drivers/gpu/drm/sysfb/drm_sysfb_modeset.c`; it is not a measurement of the
physical panel's refresh. That driver copies damage using `drm_fb_blit`.
The Adreno driver supplies GPU rendering separately.

The OnePlus 7 Pro panel supports 90 Hz:
<https://www.oneplus.com/7pro>. No 90 Hz mode is currently exposed to Hyprland.

## Short live measurement

A separate, self-closing Quickshell animation rendered a tiny changing color
marker, while a read-only `/dev/mem` sampler watched the corresponding pixel in
the retained framebuffer. No display registers or compositor settings changed.
The sampler validates the device-tree framebuffer address/geometry first.
The keyboard and normal desktop remained running during the test.

- 750 observed marker changes over 11.994 seconds: 62.53 changes/second.
- Median interval 16.068 ms; p95 17.199 ms; maximum 41.891 ms.
- One interval exceeded 25 ms (also the only interval exceeding 40 ms).
- Five marker changes briefly went backward by two animation counts, followed
  by a forward jump of four. This observation needs further investigation;
  the measurement does not establish why an older marker reappeared.

This is approximately 60 framebuffer updates/second under a light animated
load, **not optical panel FPS**, and not a profile of every overview/scrolling
interaction. Polling adds roughly 1 ms timing granularity. The >60 update rate
is possible because writes to this framebuffer are not proof of synchronized
physical presentation. Earlier Qt logs explicitly detected broken vsync
throttling and switched GUI animations to a timer.

The evidence does not support a universal 30 FPS cap. It does support treating
presentation timing as unfinished, and prioritizing native DPU/DSI/DSC and
proper display timing before claiming smooth 60/90 Hz behavior. CPU frequency
policy nodes were absent; GPU devfreq was present (257–585 MHz, simple_ondemand),
but the idle sample is not evidence of a GPU-frequency performance bottleneck.

## Reproduce and evidence

- `scripts/quickshell-frame-test.qml`: 16-second temporary animation.
- `scripts/measure-scanout.c`: 12-second, read-only marker sampler at physical
  pixel 30,30; only run with the matching test surface at the top of the panel.
- `out/performance-test/frame-timing.log`, `summary.json`, `final-state.log`.
- `out/gestures-test/performance-baseline.log`: modes, driver/system data.
- `out/cpu-test/gpu1-quickshell-animation.log`: earlier broken-vsync warning.

The temporary test exited normally; the mobile shell remained running and
Hyprland reported no configuration errors. No performance tuning or flashing
was performed in this diagnostic pass.
