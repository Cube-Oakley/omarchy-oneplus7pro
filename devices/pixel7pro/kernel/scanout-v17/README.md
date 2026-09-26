# Pixel retained-mode native DMA scanout v17

Each image directory is a complete cumulative patch/config checkpoint against
`5225b8eec4c9bb21aecff6295fab6346a3c3738e`; apply to a clean base, not over v16.
The saved build helper expects the project layout and pinned firmware/BusyBox.

Image B proves native DMA modeset and flips but exposes an inappropriate generic
wait for another vblank while the command-mode panel is idle. Image D replaces
that with the actual flip-completion wait. Both have clean-base apply checks.
Image D passes the native KMS, Mali shader and GPU-sharing regressions; the user
confirms correct, much smoother GPU animation at measured roughly 57–60 fps.
The v16 D CPU-copy fallback remains independent and physically validated.

See [evidence and limitations](../../docs/display-direct-20260925.md).
This implements native DMA allocation/import and hardware frame completion while
preserving the ABL panel mode and disabled SysMMU state. Full DSI/DSC/panel and
power ownership, continuous TE accounting, arbitrary scattered imports and 120 Hz
remain unfinished. No phone partition is flashed by the build helper.
