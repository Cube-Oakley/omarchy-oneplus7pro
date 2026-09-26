The OS inventory, milestones and procedures below predate the restart above.

Native Arch Linux + Omarchy 4 on a spare Pixel 7 Pro. Android kernel
(Evolution X / gs201), GNU userspace, Hyprland when the panel comes up.

This is **not** a Termux demo. It is also **not** a flash-and-go port.

**Status 2026-09-09:** Evolution X + Magisk is the running OS. Custom
`init_boot` ramdisk experiments are documented in
`docs/bringup-log.md` (read the “Paused” section first). Restore with
`scripts/restore-init-boot.sh` (compact Magisk image only).

## Device (this unit)

| | |
|---|---|
| Model | Pixel 7 Pro (`cheetah`), SKU `GE2AE` |
| Serial | `<serial>` |
| SoC | Tensor G2 (`gs201`) |
| RAM / UFS | 12 GB Micron LPDDR5 / 256 GB Micron |
| Panel | Samsung S6E3HC4, 1440×3120 @ 120 Hz, DRM `card0-DSI-1` |
| GPU | Mali-G710, `/dev/mali0` + `/dev/dri/card0` (world-rw on this ROM) |
| Current OS | Evolution X 15.0 10.3 (2025-02-06), build `AP4A.250205.002` |
| Kernel | `5.10.214-android13-4` GKI |
| Slot | `_a` |
| Bootloader | `cloudripper-15.1-12292122` |

User files backup: `~/Downloads/pixel7pro-backup-2026-09-08`

## Safety rules

1. Keep the Evolution X zip **and** the matching Google factory image
   under `parachute/` before any `fastboot flash`.
2. Prefer `fastboot boot` (ramdisk in RAM). Pixel 7 often **ignores** a
   ramdisk passed to `fastboot boot` and still concatenates on-device
   `init_boot` + `vendor_boot` + `vendor_kernel_boot`. If that is true
   here, a custom ramdisk requires flashing `init_boot` — only after we
   have the original `init_boot.img` to flash back.
3. Never flash `bootloader`, `radio`, or both slots at once on the first
   try. Never relock the bootloader until Evolution X boots again.
4. Volume Down + Power = bootloader. Volume Up + Power from bootloader
   start = recovery. Leaving the cable in, `fastboot reboot` from the PC
   is the normal way back to Android.

## Layout

```
docs/device.md     live inventory from ADB
docs/boot.md       Pixel 7 GKI boot chain and what we will change
scripts/           download parachute, dump inventory
parachute/         factory + Evolution X zips (gitignored, ~6 GB)
out/               unpacked images and ramdisks (gitignored)
```

## Current milestone

**0 — parachute + inventory + fastboot prove-out** (done 2026-09-08)

- User files backed up to `~/Downloads/pixel7pro-backup-2026-09-08`
- Google factory `AP4A.250205.002` in `parachute/` (sha256 verified)
- Factory `boot` / `init_boot` / `vendor_boot` unpacked under `out/factory-images/`
- Fastboot: **`unlocked: yes`**, slot `_a`, both slots bootable
- Live copies of the *currently running* boot images via `fastboot fetch`
  (no flash) in `out/device-slot-a/` — this is the restore set
- Phone rebooted back to Evolution X 10.3

**1 — ramdisk vector** (done 2026-09-08)

- `fastboot boot` of dumped `boot.img` → Evolution X in 11s.
- Same kernel plus a marker ramdisk → still Evolution X in 11s.
  `fastboot boot` **ignores** the ramdisk on this phone.
- Flashing busybox `/init` to `init_boot` **does** take over (Android
  USB disappears). USB gadget did not enumerate; Power + Vol Down is
  the way back. Restore both slots: `scripts/restore-init-boot.sh`.

Phone is back on Evolution X 10.3 slot `_a` with Magisk 28.1 root.

**2 — live USB recipe** (done 2026-09-08, Magisk root)

- Controller is `11210000.dwc3`. Dummy UDC must never be bound.
- `svc usb setFunctions rndis` → host `18d1:4ee4` (RNDIS+ADB).
- Stop gadget HAL, bind ACM only → host `/dev/ttyACM0`, root shell.
- See `docs/usb.md`. Next ramdisk is `out/ramdisk-usb/init_boot-usb.img`
  (Magisk no-PIE busybox + C `/init` that mounts `/dev` first).
  Flash both slots by name; restore with `scripts/restore-init-boot.sh`.
