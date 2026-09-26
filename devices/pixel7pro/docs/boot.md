# Boot chain (Pixel 7 / Tensor G2)

Pixel 7 launched on Android 13 GKI. The kernel is in `boot`, the generic
ramdisk is in `init_boot`, vendor bits are split across `vendor_boot`
and `vendor_kernel_boot`. The bootloader concatenates ramdisks:

```
vendor_boot ramdisk
  + vendor_kernel_boot ramdisk  (modules)
  + init_boot ramdisk           (first-stage init)
→ kernel cmdline + DTB from boot/dtbo
```

## Why `fastboot boot` is a trap here

**Verified on this unit 2026-09-08.** `fastboot boot` of the live
kernel plus a marker ramdisk (`sleep 86400` as `/init`) still reached
Evolution X in 11 seconds. The ramdisk was ignored; the bootloader
kept on-device `init_boot` + `vendor_boot` + `vendor_kernel_boot`.

A custom `/init` therefore means flashing `init_boot` (Magisk-style).
That is reversible **only if** we have the current `init_boot.img` on
disk. Restore set:

`out/RESTORE-init_boot.img` (sha256 `693be737…0902f4`, fetched from
slot `_a` before any flash).

First flash of a marker `init_boot` (legacy LZ4 ramdisk, busybox
`/init`) **did leave Android**. USB gadget did not enumerate; BCB
`bootonce-bootloader` did not bring us back. Recovery was Power +
Volume Down, then `fastboot flash init_boot_a` **and**
`init_boot_b` — flashing only `init_boot` follows the *current* slot,
which had switched to `_b`. Always name the slot.

Source for the restore image:

1. Evolution X 10.3 zip for this build (best match)
2. Google factory `AP4A.250205.002` (stock, also the wipe-back-to-Google
   parachute)

## What we will try, in order

1. `adb reboot bootloader` → `fastboot devices` → `getvar all`.
   Confirm `unlocked: yes`. If the bootloader is actually locked, stop
   and unlock (this wipes userdata; user files are already copied).
2. `fastboot boot` a Lineage/Evolution recovery image. Does not flash.
   Success = we can run foreign code. Then `fastboot reboot`.
3. Unpack factory `init_boot.img` with `unpack_bootimg`. Replace `init`
   with a static aarch64 busybox + USB gadget / adbd. Repack.
4. If `fastboot boot` ignores that ramdisk, flash it to `init_boot` on
   the **current slot only**, reboot, get a shell over USB. Restore
   stock `init_boot` the moment we have a shell or if it loops.
5. Only after a shell: mount modules, bring up DRM, try `cat
   /sys/class/drm/card0-DSI-1/modes`, then a tiny Wayland compositor.

## Restoring Evolution X

Sideload the matching ROM zip from recovery, or fastboot-flash the
extracted `boot` / `dtbo` / `vendor_boot` / `vendor_kernel_boot` /
`init_boot` from that zip plus `adb sideload` the payload. Factory
`flash-all` is the nuclear option and **wipes userdata**.

## Kernel strategy

First boot uses the **already-running 5.10 GKI** on the phone. We are
not mainlining Tensor. Userspace is Arch aarch64. Display via existing
DRM/KMS; GPU via Mali blob or Mesa later.
