# Native display preparation — 2026-09-17

**Native2 #179 is flashed and boot-verified on slot B.** Native DSI-1 runs at
1440x3120@60, scale 3; Hyprland and Quickshell both report FD640. The panel
connection is embedded in the DTB, and the mobile desktop, touchscreen and
patched keyboard all start automatically. No live graph overlay or manual
reprobe/session launch was needed on this boot.

The user confirmed clean static colors on native1 and accepted the native2
desktop, gestures and focus-flash fix after reboot ("yeah that looks good to me").
The focus fix
passed controlled focus, automatic-hide and manual visibility tests before
reboot; its exact binary and automatic startup are verified on native2.
See [keyboard focus fix](keyboard-focus-fix-20260917.md).
90 Hz and new drawer animations are not implemented, and smoothness under
real interactive loads still needs measurement and user feedback.

Verified image/evidence checkpoint: `out/checkpoints/20260917-native2-verified/`.
The original preparation bundle remains unchanged at
`out/checkpoints/20260917-native2-test/` (same boot/DTBO hashes); the flash
helper still selects that pair. Native1 is frozen at
`out/checkpoints/20260917-native1-test/`; verified simpledrm rollback:
`out/checkpoints/20260916-touch1/`.

## Native2 automatic boot validation

Boot ID `e38aa15d-a549-42a7-b98a-b4d9df657096`; release
`6.17.0-sm8150-codex-native2-g379d8fe35c7c-dirty`, #179.

- Flash verified both prepared and rollback hashes, wrote only boot_b/dtbo_b,
  selected B and rebooted. Slot A was untouched.
- Eight CPUs online. USB SSH started itself before display initialization;
  the host helper subsequently corrected the clock and checked DNS.
- GPU initialized at kernel log time ~108 seconds, touch at ~109, native DSI
  bound at ~137, panel DSC prepared at ~139 and desktop/touch ready at ~141.
  These bring-up delays remain intentional and can be shortened separately.
- `NATIVE_DESKTOP_STARTED`, `NATIVE_TOUCH_MODULES_LOADED` and
  `TOUCHSCREEN_READY` appeared in fresh startup logs. `panel_graph` is absent;
  the embedded graph alone binds DSI successfully.
- Native DSI-1: 1440x3120@60, XRGB8888, scale 3. FD640 is reported by both
  Hyprland and Quickshell (OpenGL, Mesa 26.2.2). Quickshell reports vsync
  16.67 ms and swap interval 1; this is not an optical or full UI frame-rate
  measurement. Wallpaper, mobile status/navigation layers and touch loaded.
- Hyprland config errors are empty. The keyboard starts hidden automatically,
  exposes its virtual input device, and retains the verified focus-fix SHA256
  `50a9a232d7b528e8520325b6fa5a13f2bd88c65ccb1f3d1c828c9516192711e1`.
- Landlock ABI 7, active LSM capability/landlock, and ordinary pacman sync to
  a temporary database passed without a sandbox bypass or installed-package
  changes. DNS and clock were verified first.
- No DSI timeouts/FIFO errors, DPU underruns, IOMMU faults or kernel oops
  appeared in the captured native2 boot. Existing touch-overlay removal
  warnings and unused peripheral deferred probes remain bring-up limitations.

Evidence: `out/native-display-test/flash-native2.log`, `native2-early.log`,
`native2-usb.log`, `native2-auto-start.log`, `native2-boot-validation.log`,
`native2-pacman.log`, `native2-renderer-final.log`, `native2-runtime/`.

## Native1 hardware results

Native1 initially failed panel/DSI binding with -ENODEV. The frozen touch1
DTB lacked the panel endpoint and reciprocal DSI output connection, although
the working DTS contained them. The first overlay incorrectly assumed they
were retained. Applying `guacamole-panel-graph.dts` through `panel_graph.ko`
and reprobeing `ae94000.dsi.0` registered native msm-kms successfully.
Native2 integrates those reciprocal endpoints into `guacamole-native-panel.dts`;
the verifier now explicitly checks them. The runtime graph module is only
for reproducing the native1 repair, not required by native2.

- Native KMS: card1/DSI-1 on this boot; GPU: card0/renderD128. Discover nodes
  on every boot. Use `modetest -M msm-kms -c -p`; this installed libdrm treats
  `-D /dev/dri/card1` as a bus ID and fails to open it.
- The 50-second legacy page-flip test reported mostly 59.94 Hz. Its `-v`
  mode deliberately alternates the pattern with a plain buffer, explaining
  the initial muted/flickering test. Static SMPTE bars without `-v` produced
  user-confirmed good colors and no flicker. Do not interpret that deliberate
  alternation as a panel fault or use it for judging color stability.
- Hyprland and Quickshell report FD640; Hyprland exposes native 60 Hz,
  XRGB8888, and no config errors. S6SY761 and the virtual keyboard are present.
  No new DSI FIFO/timeout, DPU underrun or IOMMU faults appeared during these
  tests. The original failed bind remains in the boot log as history.
- Landlock ABI 7 and active LSM `capability,landlock` verified. Ordinary pacman
  repository sync to a temporary database completed with exit 0, without the
  filesystem-sandbox bypass and without changing installed packages.
- Fresh-boot automatic display startup subsequently passed on native2 above.

Evidence: `out/native-display-test/native1-{graph-apply,modetest-resources,
scanout-50s,static-scanout,hypr-start,mobile-start,desktop-health,final-health,
pacman}.log`. Boot ID: `3fd2b6b0-815e-4bd0-996a-fe5d8d7a092e`.

## Native1 test image

- Real 60 Hz Samsung DSC panel, two-slice DSI packets, GPIO6 reset, GPIO8 TE,
  GPIO130 panel supply control, corrected L3C controller supply, brightness
  320/1023 and backlight mode flags restored even after a write failure.
- Native activation remains delayed 120 seconds after late init, with GPU at
  90 seconds. No simpledrm device is created in this test; the early framebuffer
  console is unregistered before display clocks change. Removed the previous
  direct register writes that disabled the new timing/tear engines.
- Restored upstream KMS IOMMU selection and GEM-backed DSI command buffers.
  DSI initialization fails explicitly if no display VM exists. Retained the
  verified GEM GPUVA feature/initialization and imported dma-buf release fixes.
  No manual IOMMU group attachment.
- Restored upstream fbdev source and disabled its automatic client via the
  effective `drm_kms_helper.fbdev_emulation=0` argument. `msm.fbdev=0` is
  insufficient in this source: its variable is declared but never consulted.
- Diagnostic init mounts persistent Arch, starts USB SSH and udev/seatd, and
  loads matching touch modules. It does **not** overwrite the mobile configs
  or automatically launch Hyprland. Start a DRM test pattern over SSH first.
- Landlock enabled with `landlock` in the effective configured LSM list;
  normal pacman passed runtime verification above. Power-saving workarounds
  remain unchanged in this display test.

Build native2 (the default): `bash scripts/build_native_display.sh`; packaging verification:
`python3 scripts/verify_native_display.py native2`; flash once the handset is in
fastboot: `bash scripts/flash_native_display.sh`. The flash helper verifies
test and rollback hashes and changes only boot_b/dtbo_b and active slot B.
Rollback: `bash scripts/flash_touch_desktop.sh` from fastboot.

The verifier checks the packaged kernel and embedded/external DTB, exact
embedded initramfs scripts/modules, module release strings, CPU/USB DT subtree
preservation, delayed display nodes, framebuffer-client suppression, and
Landlock/panel config. Both panel and Landlock symbols are present in vmlinux.
Packaging checks establish image consistency. Hardware evidence is recorded above;
native2 automatic startup has now passed the hardware checks above.

On test boot: USB should precede native activation. Inspect `dmesg`,
`/sys/class/drm/card*-DSI-*`, and `modetest -M msm-kms -c -p` to identify
the actual display device/connector/CRTC; do not assume a fixed card number.
Use the installed modetest's 60 Hz mode and vsynced page-flip test, watch for
DSI timeout/FIFO, IOMMU, and DPU errors, then test Hyprland and touch only after
clean scanout. A frozen early boot framebuffer or a dark panel before this
test does not by itself mean the kernel failed.

## Source checks completed

The related [hotdog bring-up project](https://github.com/Sr-0w/hotdog-linux-bringup)
provides a real Samsung DSC command-mode panel driver and DSI packet changes.
Its own display evidence still records transport errors, so related-device
success is not proof of reliable guacamole support.

Compared that driver with our saved Lineage vendor source:
`.work/lineage-kernel/src/arch/arm64/boot/dts/18821/dsi-panel-samsung_oneplus_dsc.dtsi`.

- All **38** initial 60 Hz on-command payloads and explicit post-command
  delays match. The comparison decoded the vendor's seven-byte packet
  headers and the driver's helper calls; evidence is in
  `out/native-display-test/panel-on-audit.json`.
- This comparison does **not** establish equal generic/DCS wire packet
  types or downstream command batching, and does not validate the generated
  PPS, alternate oscillator sequences, or actual hardware behavior.
- Native timing: 1440x3120; horizontal front/sync/back 16/8/8; vertical
  front/sync/back 400/28/1156 at 60 Hz.
- DSC: 720x65 slices, two slices per packet, 8 bits/component and
  8 bits/pixel, block prediction. The reference supplies the missing
  two-slice DSI packetization; our existing stub supplies no real panel init.
- Vendor GPIOs: TE 8, reset 6, panel power-control 130, **alternate TMO reset
  78**. Saved Android records in `bringup.md` identify this handset as GM1911,
  and `device.md` identifies this Samsung DSC panel. Use the regular GPIO6
  reset for this test. Vendor panel vendor-name is S6E3HC2.
- Vendor display source maps panel VDDIO to PM8150 L14 at 1.8 V and drives
  GPIO130 high for its external panel supply. The existing stub's DSI host
  `vdda` uses L5A 0.875 V, whereas the hotdog reference uses L3C 1.2 V.
  **Resolved from vendor `qcom/sm8150-sde.dtsi`:** DSI0 controller at line 431
  uses PM8150L L3 (`vdda-1p2`); PHY at line 522 uses PM8150 L5 (`vdda-0p9`).
  Native1 corrects controller VDD to L3C and retains L5A for the PHY.

## Isolated compile checkpoint

Copied the working source/build tree into `.work/linux-sm8150-codex-native`.
Extracted only the panel, DSI host, and DSC header portions of the reference
patch into `devices/oneplus7pro/kernel/display/hotdog-dsc-reference.patch`.
Applied it there and compiled the panel and DSI host objects successfully.
The build log is `out/native-display-test/compile-reference.log`.

The initial object-only checkpoint has now been extended into the native1
image above. The verified `.work/linux-sm8150-codex-cpu` tree remains unchanged.
The adapted DT is an overlay on the frozen touch1 embedded DTB, preserving its
binary CPU/USB fixes rather than assuming the old DTS reconstructs them.

## Original review checklist and remaining validation

1. Resolve handset reset selection and panel host/PHY supplies. Compare
   oscillator variants and generated DSC PPS with the intended stock mode.
   Use a moderate initial brightness (vendor override 320/1023), rather than
   the reference driver's maximum-brightness default.
2. Audit inherited display experiments in the working kernel:
   DSI coherent-buffer fallback, KMS VM/IOMMU selection, GEM initialization,
   disabled fbdev, and delayed DPU population. Preserve the independently
   verified imported dma-buf release fix that keeps Adreno stable.
3. Remove or gate the old `bringup_halt_leftover_mdp()` call appropriately
   in the native test path. It writes DPU timing/tear registers **after**
   population, and must not shut down a newly initialized native pipeline.
   Do not reintroduce the prior manual DPU-to-MDSS IOMMU group attachment;
   that experiment crashed into Qualcomm 900e.
4. Integrate the real panel and guacamole DT with delayed activation after
   USB recovery is available. Make simpledrm-to-native handover and desktop
   device selection explicit, avoiding concurrent ownership of scanout.
5. Build a complete recoverable image with matching touch modules and saved
   boot/DTBO rollback pair, then request fastboot for the concrete test.
   First validate panel commands, stable test-pattern scanout and vblank at
   60 Hz; check DMA/IOMMU/DSI error logs before starting Hyprland.

The related project's experiment resetting DSI on every FIFO error worsened
its failures. Do not copy that rejected workaround. Clean static native scanout and one native2 automatic boot are now confirmed.
Repeated-boot reliability and real UI frame pacing remain to be measured;
90 Hz comes afterward.
