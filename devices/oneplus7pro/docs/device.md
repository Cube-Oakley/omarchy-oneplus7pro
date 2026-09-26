# This handset

Captured 2026-09-13 over adb while the phone was running.

| Field | Value |
|---|---|
| Marketing name | OnePlus 7 Pro |
| Codename | `guacamole` |
| SoC | Qualcomm SM8150 (msmnile), Snapdragon 855 |
| GPU | Adreno 640 |
| Display | 1440×3120 AMOLED, DSC, panel `dsi_samsung_oneplus_dsc_cmd_display` |
| RAM | ~8 GB (3.6 GiB tmpfs reported; typical 8/12 GB SKU) |
| UFS | 256 GB class (`sda` 234.26 GiB + `sde` 4 GiB + tiny LUNs) |
| Slot | A/B, currently `_a` |
| OS as found | Havoc OS (`havoc_guacamole-user`), Android 9, 2019-08-01 patch |
| Kernel as found | `4.14.83-perf` |
| Root | Magisk 19.4 (`uid=0 context=u:r:magisk:s0`) |
| Encryption | File-based (`ro.crypto.type=file`) on `userdata` |
| Recovery | No dedicated `recovery` partition (`BOARD_USES_RECOVERY_AS_BOOT`) |
| Project / RF | `androidboot.project_name=18831`, `rf_version=2`, `hw_version=21` |

`sys.oem_unlock_allowed` is `0` in getprop. Magisk is installed, so the bootloader was unlocked at some point. Confirm `fastboot oem device-info` / `fastboot getvar unlocked` before the first flash.

## UFS map

| LUN | Size | What lives here |
|---|---|---|
| `sdb` / `sdc` | 8 MiB each | `xbl_a` / `xbl_b` + config. Do not flash casually. |
| `sdd` | 32 MiB | `cdt`, `ddr` |
| `sdf` | 32 MiB | **EFS**: `modemst1/2`, `fsg`, `fsc`. IMEI. Device-specific. |
| `sde` | 4 GiB | `boot_*`, `dtbo_*`, `vbmeta_*`, `vendor_*`, `modem_*`, `dsp_*`, `abl_*`, … |
| `sda` | 234.26 GiB | `system_*` (3.39 GiB each), `odm_*`, `persist`, `metadata`, **`userdata` 226.8 GiB** |

There is no `super` partition. That is a 7 / 7 Pro vs 7T difference: guacamole still has real `system`/`vendor` partitions.

## Why the current Android build matters

The phone is on a 2019 Havoc 9 userdebug-ish user build, not OxygenOS 11/12. Mainline SM8150 bring-up (especially sensors, modem, Wi-Fi firmware) usually wants blobs from a much newer vendor image. First Linux boots may need:

1. this backup (so we can always return),
2. a newer firmware extract (Lineage 23 / OOS 11–12),
3. then a mainline boot image.

Do not update firmware until the UFS backup has finished and checksums match.
