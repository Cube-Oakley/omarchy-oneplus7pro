# Device inventory

Captured over ADB on 2026-09-08 from Evolution X, before any fastboot work.

## Identity

```
model          Pixel 7 Pro
device         cheetah
sku            GE2AE
serial         (kept locally in out/device.serial)
hardware       cheetah / gs201
revision       MP1.0
color          BLK
radio sku      GE2AE
```

## Software

```
rom            EvolutionX-15.0-20250206-cheetah-10.3-Official
flavor         lineage_cheetah-user
android        15 (API 35)
build id       AP4A.250205.002
fingerprint    google/cheetah/cheetah:15/AP4A.250105.002/12701944:user/release-keys
security patch 2025-02-05
kernel         5.10.214-android13-4-00015-g54748cd9e76c-ab12786721
bootloader     cloudripper-15.1-12292122
slot           _a
```

Android reports `ro.boot.flash.locked=1`, `vbmeta.device_state=locked`,
`verifiedbootstate=green`. That is a Play Integrity spoof.

**Fastboot (2026-09-08) says `unlocked: yes`**, `get_unlock_ability: 1`.
Both slots `successful:yes` / `unbootable:no`. Current slot `a`.
Battery was 100%. Bootloader `cloudripper-15.1-12292122` matches the
factory image we downloaded.

Live copies of slot `_a` boot images (via `fastboot fetch`, no flash)
are in `out/device-slot-a/`: `boot`, `init_boot`, `vendor_boot`,
`vendor_kernel_boot`, `dtbo`, `vbmeta`. Those are the restore set for
any `init_boot` experiment.

`/system/bin/su` exists but `su -c id` is denied (no Magisk grant).
Rooted debugging is off. We cannot `dd` partitions until that changes.

## Panel / GPU (this is the good news)

```
DRM            /dev/dri/card0          crw-rw-rw-  graphics_device
render         /dev/dri/renderD128     crw-rw-rw-
mali           /dev/mali0              crw-rw-rw-  gpu_device
connector      card0-DSI-1
panel driver   panel-samsung-s6e3hc4
mode           1440x3120 @ 120 Hz (also 1080x2340 @ 60/120)
GLES           3.2 (ro.opengles.version=196610)
```

The Android 5.10 kernel already has KMS on the built-in DSI panel and a
Mali node. Hyprland's GLES 3.0 floor is reachable **if** we can start a
session that owns DRM. First userspace will likely need SELinux
permissive or disabled; labels are `u:object_r:graphics_device:s0`.

## Memory / storage

```
RAM            11742364 kB (~12 GiB LPDDR5 Micron)
UFS            256 GB Micron
userdata       /dev/block/sda31
super          /dev/block/sda30   (dynamic: system, vendor, product, …)
```

## Boot partitions (A/B)

| Name | A | B |
|---|---|---|
| boot | sda10 | sda20 |
| init_boot | sda11 | sda21 |
| vendor_boot | sda12 | sda22 |
| vendor_kernel_boot | sda13 | sda23 |
| dtbo | sda14 | sda24 |
| vbmeta | sda15 | sda25 |
| vbmeta_system | sda16 | sda26 |
| vbmeta_vendor | sda17 | sda27 |
| pvmfw | sda18 | sda28 |
| modem | sda19 | sda29 |

Bootloader pieces live on `sdb`/`sdc` (`bl1`, `pbl`, `bl2`, `abl`,
`bl31`, `tzsw`, `gsa`, `ldfw`, `dpm`). Do not touch those until we have
a tested factory `flash-all`.

## Modules of interest

Vendor ramdisk already ships `aoc_*.ko` (Pixel audio DSP), plus the
usual gs201 set under `/vendor_dlkm` / first-stage ramdisk.
