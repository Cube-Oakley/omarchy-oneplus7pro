# Mainline GS201 / cheetah

Vendor GKI ramdisk USB is stuck (I2C hang, dummy UDC). This path boots
**upstream Linux** on slot `_a` only. Slot `_b` stays Evolution X.

## Safety

- Never flash `boot_b` or `init_boot_b`.
- Restore kernel: `out/RESTORE-boot_a.img`
- Restore ramdisk: `out/RESTORE-init_boot-compact.img`
- Pixel 6+ will mark a slot unbootable if it fails without `successful`.
  If both slots are unbootable the phone bricks. Keep `_b` as a known-good
  Evolution X boot that has already succeeded.
- `fastboot boot` **ignores** a custom ramdisk on this unit (see `boot.md`).
  A mainline kernel therefore means flashing `boot_a` + `init_boot_a`.

## First image

1. `mainline/build-kernel.sh` — arm64 defconfig + `kconfig.fragment`
2. `mainline/pack-boot.sh` — LZ4 `boot-mainline.img` + `init_boot-mainline.img`
3. Initramfs logs to kmsg, binds ACM if a `*.dwc3` UDC exists, otherwise
   `rebootbl` after 20s.

First boot uses the **vendor DTB** from `vendor_boot` (not a new cheetah
DT yet). Goal: kernel reaches `/init` and returns to fastboot.

## Flash

```
adb reboot bootloader
fastboot flash boot_a out/mainline/boot-mainline.img
fastboot flash init_boot_a out/mainline/init_boot-mainline.img
fastboot set_active a
fastboot reboot
```

## Restore

```
fastboot flash boot_a out/RESTORE-boot_a.img
fastboot flash init_boot_a out/RESTORE-init_boot-compact.img
fastboot set_active a
fastboot reboot
```

If the logo sits past ~45s, hold Power+Vol Down through to fastboot.
