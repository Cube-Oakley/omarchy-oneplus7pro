# Pixel native kernel checkpoints

Current display baseline: [v19](panel-v19/README.md), applied after the cumulative
v18 image D patch. It adds clean shared CRT screen off/on. The
[power-key module](powerkey/README.md) supplies Linux input events; the
[UFS handoff driver](storage/README.md) and `--persistent-root` build option are
under installation validation. The Arch root is installed on ext4 userdata and
the shared desktop runs from it. [Reboot target selection](reboot/README.md) is
experimental: its bootloader-mode test entered Android recovery, where ADB
successfully restored fastboot. Full CPU suspend remains unimplemented. Earlier
checkpoints below are preserved for reproduction. Persistent builds now embed
their required command line before early parsing; image H tests whether normal
ABL boot was omitting the boot-header arguments. H is not hardware-validated yet.

`kernel-base.txt` records the exact upstream commit. `native-bringup-v9.patch`
contains all local source changes relative to it, including the preexisting
embedded initramfs/bootconfig changes and the new framebuffer, USB and watchdog
code. `native-bringup-v9.config` is the tested configuration; the build helper
replaces its absolute initramfs path with the selected output directory.
Recorded configurations name this workspace as `@PIXEL_ROOT@` in place of the
local absolute path; the helpers set both paths again at build time.

Apply one checkpoint patch to a clean checkout of that commit. The v11 checkpoint
used the complete patch below. Reverse
`git apply --check` was tested against that working source, including added files.
Do not stack checkpoint patches or apply twice.

The low-level instrumentation is specific to this Pixel's verified bootloader
handoff; this is a bring-up patch, not an upstream-ready multi-device driver.
The framebuffer and reserved-RAM startup markers use fixed addresses. Normal
DRM, USB PHY/clock, watchdog and power drivers remain future integration work.

Use `scripts/build-pixel-shell.py` from the project root to rebuild. See
[the dated milestone](../docs/native-shell-20260925.md) for dependencies,
commands, artifact hashes and on-device evidence.

The v10 network variant uses the same hardware patch, disables `USB_G_SERIAL`
and enables `USB_CDC_COMPOSITE`. Build it with `--usb-network`; the helper selects
the composite gadget and adds the USB network setup script to the initramfs.
See [network/Arch validation](../docs/native-arch-20260925.md).

## v11 retained-display bridge

`native-bringup-v11.patch` is a complete alternative patch against the same pinned
upstream commit, including the v9 work plus the guarded DRM bridge and console
handoff. Do not stack it on top of v9. The v11 working kernel passed
reverse-apply validation. `native-bringup-v11.config` records the tested
v11d configuration. The build helper still starts with v9's config and applies
the display options when passed `--drm`.

The native DRM test card is user-confirmed visible, with successful modeset,
eight page-flip events and advancing DECON frame counters. This is fixed-mode
CPU-copy display support, not GPU acceleration or a complete native panel driver.
See [display milestone](../docs/display-drm-20260925.md).
