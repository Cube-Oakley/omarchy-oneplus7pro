# V19: panel DPMS for shared CRT sleep/wake

Apply `panel-v18/image-d/native-bringup-v18.patch` to the pinned kernel base,
then `0001-panel-dpms-crt.patch` here. The v18 ACPM/GPU overlays and isolated Mesa
inputs remain unchanged. Build with the current `scripts/build-pixel-shell.py
--panel120 --seconds 1800 --output <new-output>` after restoring local inputs.
`kernel.config` replaces the local workspace prefix with `@PIXEL_ROOT@`.

The DRM driver sends DCS 0x28/0x29 under serialized commit ordering and checks
power-mode bit 2. It leaves panel timing, rails, DSC, PLL and PHY powered. DPMS
off restores 60 Hz and releases the 120 Hz bandwidth floor. Keep the final
compositor image in panel memory and retain its DMA reference until the next
successful transfer; restoring the bootloader framebuffer flashes console text
through the shared CRT animation. This does not implement system suspend.

Image A verified physical power-key sleep/wake but had the console flash.
The user confirms image B removes the console flash and both CRT transitions are clean.
Image B SHA256: `c75f69b79f6a79f239d9d1df1f25a4c964f19e72b897d524e046ba1645381e24`.
Both use the `pixel-panel19` release suffix. Always hash the actual boot image;
the release string alone does not distinguish iterations.

Power-key module: `../powerkey/`. Full evidence and chronology:
[implementation record](../../docs/persistence-power-20260925.md).
