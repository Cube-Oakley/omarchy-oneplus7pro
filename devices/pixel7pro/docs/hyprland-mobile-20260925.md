# Native Hyprland and shared mobile shell — September 25, 2026

## Verified result

The Pixel runs Hyprland 0.56.2 with Mesa llvmpipe on the v11d native DRM bridge.
The user confirmed both `HYPRLAND-ON-PIXEL-7-PRO` and
`pixel-hyprland-input-ok` were visible in its terminal. A USB-fed uinput command
created the proof file from inside that graphical terminal. `hyprctl` reports
DSI-1 active at 1440×3120, scale 3, XRGB8888, and no configuration errors.

The same shared mobile shell used by the OnePlus project was then installed into
Pixel RAM. Quickshell 0.3.1 loads its wallpaper, status, drawer, shade and navigation
layers. Host-captured Wayland screenshots verify the Applications page, themed
Kitty terminals, on-screen keyboard and Settings page. Launcher actions were
exercised via its existing IPC interface. Physical touch is **not** working yet.
This is Arch Linux ARM with the shared Omarchy mobile layer, not a completed
standard Omarchy installation or a persistent phone OS.

The kernel/image were unchanged. `fastboot boot` used the previously verified
v11d SHA256 `ffcce07048c1924cd903d8550debd433d3a8baccb0f0eb777dd3820aa750ba95`.
The prior automatic reboot returned the phone to Android; ADB was available to
enter fastboot without user intervention. No flash, slot switch or bootloader
change occurred. Slot A remains the only known bootable slot.

## Why EGL failed, and the fix

Mesa's `gbm_dri.c` has separate ordinary-driver and software-driver creation paths.
Setting `MESA_LOADER_DRIVER_OVERRIDE=kms_swrast` alone selects that driver through
the ordinary path, leaving the GBM `software` flag false. EGL's `platform_drm.c`
then tries to find a compatible render device for this display-only DRM node.
There is no such render node in this kernel.

`GBM_ALWAYS_SOFTWARE=1` selects Mesa's software path and sets the flag. The Pixel
launcher also uses `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe`, and
unsets the loader override. No Mesa, Aquamarine or kernel patch was needed.

`mainline/pixel-egl-probe.c`, adapted from the read-only OnePlus shader probe,
opens card0 through GBM, compiles a shader into a 16×16 offscreen framebuffer and
reads back a pixel. It never modesets. On the same live kernel/libraries:

- Previous environment: `eglInitialize` failed with `EGL_NOT_INITIALIZED`.
- Corrected GBM software environment: EGL 1.5, GLES 3.2, llvmpipe LLVM 22.1.8;
  pixel RGBA **64,128,191,255**, GL error 0, PASS.

Primary sources, pinned to installed Mesa 26.2.3:
[GBM driver selection](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.3/src/gbm/backends/dri/gbm_dri.c),
[EGL DRM initialization](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.3/src/egl/drivers/dri2/platform_drm.c),
[loader override](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.3/src/loader/loader.c).
Downloaded copies and hashes live in the checkpoint's `mesa-source/`.

Aquamarine still emits errors from its optional EGL device-matching renderer;
the primary compositor successfully uses its GBM software path and presents.
Quickshell falls back to SHM when it cannot find a DMA-BUF render device.
Xwayland disables glamor. These logs do not establish GPU acceleration.

## Shared-source boundary

No OnePlus files were modified. `overlay/mobile/` was read and snapshotted into
`out/checkpoints/20260925-hypr-v11d/shared-mobile-source.tar.gz`. Its 237 files are
identified individually in `shared-mobile-source.json`, alongside reference HEAD
`656ab62ff62335f80e9f6d54e3ab8e8dc74e86e9`. The archive SHA256 is
`f23e474794434a9d86a4ac2ea9e2f184e04855bbaa8905327b5999f2dca07d4f`.
Hashes identify the working files independently of the repository commit.
The archive also includes this Pixel's three small device adapter files.

`devices/pixel7pro/adapter/mobile.json` uses the preferred display mode and scale 3.
`desktop-prepare.sh` loads generated shared theme/session configuration into the
known Pixel Hyprland config. It checks for the RAM root and v11 kernel and performs
no hardware writes. No OnePlus radio, boot-slot, charging, suspend, camera or
clock control script is installed as a Pixel adapter.

This is a pinned integration experiment, not a fork of shared UI sources. The
accepted monorepo consolidation still needs an isolated destination and review.
Do not edit the archived UI to create a separate Pixel product implementation.

The keyboard was built on-device from a read-only snapshot of OnePlus's
`.work/wvkbd-focus-fix`, based on upstream commit
`6b41504a0cb58fd1163fa44692398fbd61f8905f` plus its existing focus grace change.
`wvkbd-source.json` records every source hash; `wvkbd-source.tar.gz` preserves the
exact build input. `make -j2 wvkbd-mobintl` succeeded with signed Arch GCC/make
packages, and the binary was installed in RAM at `/usr/local/bin/wvkbd-mobintl`.
Its on-screen rendering and show/hide actions work; physical touch-to-key events
remain untested because the touch controller is not brought up.

## Checkpoints and replay

All current evidence is under `out/checkpoints/20260925-hypr-v11d/`.
The previous Weston archive was restored on a fresh boot successfully: USB
transfer, hash check, extraction, fresh SSH credentials, Weston and virtual
keyboard all worked. The bootstrap now waits up to 30 seconds for USB enumeration
and removes its transfer archive only after successful verification/extraction.
Both refinements subsequently passed in the complete mobile archive replay.

Before adding the mobile shell, a separate Hyprland baseline was saved:

- `arch-hyprland-rootfs.tar.zst`: SHA256
  `33956acbfe7cef25a82d7f12ff1709603c85b3222815c1e6495d5d869ca2489d`.
- `arch-hyprland-rootfs.tar.gz`: SHA256
  `2dc81a46373f43471aa248f3ae0d3e0822bc8bd3603e67ce15c896daa49cdc23`.
- zstd integrity passed; expanded tar size 2810449920 bytes.

The complete mobile checkpoint was subsequently saved:

- `arch-mobile-rootfs.tar.zst`: SHA256
  `032d317ba7c299abe762d931ed1325e063793ea873d1ef3d0c5c29baa9baaeaa`.
- `arch-mobile-rootfs.tar.gz` (1738233880 bytes): SHA256
  `9b204df8aff3f54625f347d11d4e1370b44a83aef12e6371d588c8581ba54e57`.
- zstd integrity passed; expanded tar size 4018165760 bytes; snapshot stderr empty.

Restore a selected checked gzip archive with `start-pixel-arch.py --archive ...
--archive-sha256 ... --output NEW_SESSION_DIRECTORY` after RAM-booting v11d.
Then use the new session SSH wrapper, in order:

```sh
NEW_SESSION_DIRECTORY/ssh 'bash -s' < scripts/pixel-weston-start.sh
NEW_SESSION_DIRECTORY/ssh 'bash -s' < scripts/pixel-terminal-start.sh
NEW_SESSION_DIRECTORY/ssh 'cat > /root/pixel-hyprland.lua' < mainline/pixel-hyprland.lua
NEW_SESSION_DIRECTORY/ssh 'bash -s' < scripts/pixel-hyprland-start.sh
# For the mobile archive only (shared shell/dependencies already installed):
NEW_SESSION_DIRECTORY/ssh 'bash -s' < scripts/pixel-mobile-start.sh
```

`pixel-hyprland-start.sh` waits for the exact compositor PID's Wayland socket.
Hyprland's `--socket` option is for socket handover paired with `--wayland-fd`;
it cannot simply choose a socket name. An initial helper using it was rejected
before startup, corrected, and the working helper was tested live.
`pixel-mobile-start.sh` requires exactly one Hyprland instance and discovers its
socket/signature rather than hardcoding a prior boot's identifier. Re-running
it against the current shell cleanly reports that the instance already exists.

Archives exclude virtual filesystems, runtime state, package caches, root SSH
credentials, Pixel SSH host/config files, and pacman's generated keyring. The
mobile archive also excludes root caches. They are local development snapshots,
not redistributable OS releases. Pacman's mirrorlist still points at the temporary
localhost package tunnel; regenerate signing keys and restore transport before
installing more packages. Signed package sources remain cached in the v11d
`packages/` directory with URL/hash records. No signature checks were disabled.

## Evidence and remaining limits

- `egl-comparison.txt`: failing and passing GBM paths plus actual shader readback.
- `hyprland-input-proof.txt`, `hyprland-verified.txt`: input, monitor, kernel logs.
- `pixel-mobile.png`: Applications page.
- `pixel-mobile-now.png`: themed Kitty terminals and on-screen keyboard.
- `pixel-settings-ready.png`, `settings-ready.txt`: mapped Settings interface.
- Package logs, source manifests and snapshot checksums accompany these files.

The displayed time is currently UTC. Software rendering is expensive: the sampled
process averages included roughly 176% CPU for Hyprland and 30% for Quickshell;
these are not controlled performance measurements. First launches can take several
seconds while shaders and QML initialize. A blank initial window alone is not a
failed app: both Kitty and Settings later mapped and rendered correctly.

The RAM chroot lacks a complete systemd session, desktop portals and hardware
services. Kitty logs a failed systemd-scope/portal request but runs. Settings logs
two undefined-to-bool warnings when Wi-Fi metadata is absent. The shell's audio
subscriber cannot start without pactl; audio hardware is absent anyway. Its UI
pages and app launchers do not imply Wi-Fi, Bluetooth, camera, audio or charging
functionality. GPU acceleration, real display power control, physical touch,
thermal/charging support, storage and persistent boot remain future work.

### Complete fresh-boot mobile replay

`out/checkpoints/20260925-mobile-replay/` records a third boot using the same
v11d kernel, the full mobile gzip archive, and the documented launch sequence.
Phone-side SHA256, extraction, removal of the transfer archive, fresh SSH keys,
Weston, Hyprland and the shared mobile shell all passed. No package download or
rebuild was needed. The new network profile is
`9fefb875-70c9-4334-96a7-7d0a269e400f`; previous temporary profiles and the package
cache server were stopped/removed. The current SSH wrapper is in that directory's
`arch-session/`. Private session credentials remain local.

The restored uinput and wvkbd keyboards are both listed by Hyprland. A command
sent through the displayed terminal created `/run/mobile-replay-input-proof`
containing `mobile-replay-input-ok`. The first attempt ran during the mobile
drawer's focus transition and did not create the file; after dismissing the
drawer and verifying the terminal's focus, the input proof passed.
`pixel-mobile-start.sh` now explicitly starts the hidden keyboard as well as the
shell so replay does not depend on its asynchronous setup finishing first. Its
idempotent path was verified against the live restored session.

Replay evidence includes `input-final.txt`, `input-final.png`,
`mobile-replay-proof.txt`, `final-state.txt` and `mobile-final.png`. The Applications
page is left open. Physical confirmation of the initial Hyprland terminal is
recorded above; the mobile UI has screenshot verification and a visual question
was sent to the user, whose response remains pending.

The original **1800-second kernel reboot limit remains active** throughout.
This session does not make any of those capabilities persistent.
