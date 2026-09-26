# Cheetah RAM display probe

This is a standalone AArch64 payload in an Android boot-v4 / Linux Image
envelope, **not a Linux kernel or an Omarchy installation**. Build locally with
`python probe/build.py`; the build script never communicates with a phone.

It is specific to this project's Pixel 7 Pro, cloudripper 15.1 and the live
AP4A.250205.002 device tree captured on 2026-09-24. Read
[the current restart notes](../docs/restart-20260924.md) before device operations.

The probe:

- Requires EL1 or EL2 with MMU and data cache disabled, as in the arm64 boot
  protocol; uses a private stack and exception vectors that attempt PSCI reset.
- Reads DPP0 at `0x1c0b0000` and DECON0 at `0x1c240000`, verified in the live DT.
- Refuses framebuffer writes unless the scanout is `0xfac00000`, 1440x3120,
  uncompressed 32-bit RGB with zero crop, matching stride, command mode, and
  hardware trigger selected. The address comes from this unit's ABL display
  surface function; it lies within the live reserved TUI allocation.
- Draws a center-screen banner, then follows the ABL's shadow-update, enable,
  and hardware-trigger sequence. It preserves the trigger source and restores
  the old trigger mask after a bounded update wait.
- Attempts reset after 40 seconds of display time, or 12 seconds on a guard
  mismatch. An exception attempts immediate reset. A hardware bus stall can
  still prevent automatic reset; Power + Volume Down is the manual fallback.
- Initializes and logs into the stock ramoops console at `0xfd3ff000`.
  The live DT and stock boot log confirm a 2 MiB console and ECC=0.
  This replaces the previous volatile console log, so save
  any wanted diagnostics before testing. It never accesses storage.

Register evidence is in `out/restart-20260924/display-source/` and the saved
ABL disassembly. Google's cal_9845 common definitions plus cal_9855 overrides
describe GS201; do not confuse the GS101 DECON base with GS201's.

The generated font is extracted from Linux `lib/fonts/font_8x16.c` (GPL-2.0).
Output includes ELF, disassembly, image, boot wrapper and SHA256 manifest.
ELF RWX segment warnings are expected for an MMU-off payload; no ELF loader
or executable mappings are installed on Android.

The bootable candidate is `boot-probe-avb-envelope.img`. Its stock AVB
metadata/footer and OS-version properties are retained, but the payload hash
does not match: this is an experimental image for the unlocked unit, not a
Google-signed payload. Bare `mkbootimg` output and zero-padding alone stayed
in fastboot. Retaining the metadata allowed the phone to leave fastboot.
**Version 2 is verified:** photo and recovered console log confirm the banner,
frame counter 5 -> 6, update request cleared, and the planned reset to Android.

Version 2 accepts the bootloader's normal masked hardware-trigger state
(`TRIG_CON` bit 4 set, bit 0 clear), initializes the RAM log explicitly, and
attempts to record exception syndrome/address before resetting. Earlier
version 1 required bit 0 set and only logged if an old signature existed.
Build artifacts and source snapshots are separated by version.

No flashing command is provided here. The intended test transport is temporary
`fastboot boot` after serial/product/bootloader/successful-slot checks.
