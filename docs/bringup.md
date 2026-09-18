# Bring-up log

**Current checkpoint: [status.md](status.md) (2026-09-16).** 6.17 on slot B, USB gadget `1d6b:0104`, ping `172.16.42.1`, shell `nc 172.16.42.1 23`. This file is the historical log; do not treat early “returns to fastboot” rows as the present state.

---

# First boot attempt (2026-09-13)

Android is back on slot `_a` (Havoc). Slot `_b` images were restored from the firmware backup.

## What we proved

- Bootloader **unlocked**. `Device critical unlocked: false`.
- This 2019 ABL (`op_abl_version: 0x31`) does **not** implement `fastboot boot` (`FAILED (remote: 'unknown command')`).
- Dual-boot on `_b` works: a stock Magisk `boot_a` flashed to `boot_b` + `fastboot --disable-verity --disable-verification flash vbmeta_b` **did boot Android on slot B**.
- So slot switching and AVB disable are fine. The mainline payload is what ABL bounced.

## What failed

Every mainline `boot_b` we flashed returned to fastboot in a few seconds (USB `18d1:d00d`). Variants:

| Image | Notes |
|---|---|
| gzip `vmlinuz` + appended guacamole DTB, header v0 | pmos `append_dtb` recipe |
| uncompressed ARM64 `Image` + DTB, header v0 | |
| header v2 with separate DTB | |
| magiskboot repack of stock boot with replaced kernel/ramdisk | stock is `KERNEL_FMT raw` |
| `UNCOMPRESSED_IMG` wrapper + Image + DTB (stock OnePlus kernel envelope) | |
| same + empty `dtbo_b` (stock dtbo has 12 overlays) | |

Stock kernel in `boot_a` is **not** `Image.gz-dtb`. Magiskboot 19.4 unpacks:

- magic `UNCOMPRESSED_IMG` + 4-byte LE length
- raw ARM64 Image
- **four** concatenated DTBs (~1.8 MiB total)

pmOS `deviceinfo` for guacamole still says `deviceinfo_append_dtb="true"` and ramdisk offset `0x01000000`; this handset’s stock image uses ramdisk `0x02000000` and the OnePlus uncompressed wrapper.

## Likely cause

The kernel never stays up long enough to bring up USB gadget. Two stacked reasons:

1. **2019 firmware.** Havoc is still on Pie-era ABL/TZ/XBL. The 7T Pro mainline port (`hotdog-linux-bringup`) needed Lineage/OOS 12-class firmware; they even warn that a Lineage flash leaves a persistent change required to boot their images.
2. **DTB/DTBO contract.** Stock ABL selects among 4 kernel DTBs and applies 12 DTBO overlays. A single 95 KiB mainline `sm8150-oneplus-guacamole.dtb` is a different boot path than this ABL was written for.

## Firmware update (2026-09-13 evening)

OOS 12 H.41 firmware images were written to **both slots with Magisk `dd`** (fastboot refused critical partitions). New ABL is running:

- `fastboot boot` now exists (was `unknown command` on 2019 ABL)
- `oem device-info` no longer reports `op_abl_version: 0x31`
- Stock Havoc/Magisk `boot_a` **no longer boots** on this ABL (expected)

Lineage 23.2 `boot.img` (header v2, os 16) + matching `dtbo`/`vbmeta` were flashed at least once; the kernel still returned to fastboot. `fastboot flashing unlock_critical` then **blocked waiting for an on-device Volume confirm**, and later `fastboot flash` commands hung.

**If the phone is sitting in fastboot with a Volume Up / Volume Down prompt, press Volume Up** (unlock critical). Then we can finish Lineage recovery + sideload.

Lineage artifacts (checksums verified):

- `lineage-23.2-20260907-nightly-guacamole-signed.zip` sha256 `ebd0892f…`
- payload images in `.work/firmware/payload-out/`

## Lineage 23.2 is booting (2026-09-14)

After a clean key-combo fastboot (full “START” menu, not the logo-only screen), sparse `system_a` + `vendor_a` + Lineage `boot`/`dtbo`/`vbmeta` were flashed. The phone enumerated as `22d9:2769 GM1911` and adb reports:

- `ro.lineage.version=23.2-20260907-NIGHTLY-guacamole`
- Android 16, kernel `4.14.357-openela-perf`, slot `_a`

Critical partitions remain locked (`unlock_critical` → “cannot be unlocked for technical reason”). Firmware on flash is still the H.41 set written via Magisk `dd`.

## Mainline still returns to fastboot (~5s)

Retried after Lineage was up:

| Test | Result |
|---|---|
| `fastboot boot` header-v2 + stock pmOS 6.17 | fastboot in ~1s |
| `fastboot boot` rebuilt kernel, `RAID6_PQ_BENCHMARK=n` | same |
| slot B + empty DTBO + RAID6-fix kernel | fastboot in ~5s |

Lineage on slot A was restored each time.

Lineage `dtbo` is **10 full Android DTBs** (~320 KiB), selected by `qcom,board-id = <0x08 0x00>`, not small overlays. The mainline guacamole DTB had no board-id, so ABL either applied a 4.14 DTB or found none.

Retest with `qcom,board-id` / `qcom,msm-id` added and a 10-entry DTBO of the mainline DTB: still fastboot in ~6s. Board-id injection alone is not enough; the DTB still lacks the vendor UFS/regulator symbols hotdog had to bridge.

A real postmarketOS edge `boot.img` (header v0, append_dtb, full mkinitfs ramdisk) was built with `pmbootstrap --as-root`. Flashed to slot B as header v2 as well. Both still returned to fastboot in ~5s. Lineage 23.2 on slot A remains the working OS.

`pkexec` as `PMB_SUDO` prompted once per mkdir/mount — do not do that again. Future root work must be a single `--as-root` session.

Lineage DTBO entries are `/plugin/` overlays keyed by `oplus,dtsi_no` + `oplus,pcb_range` (18821/18857/18865/19801/19863). They need ~310 base symbols the mainline guacamole DTB does not have (`FDT_ERR_NOTFOUND`). A no-op overlay with the same IDs still 5s-bounced. Disabling `vbmeta_b` made ABL **fall back to slot A Lineage** instead of sitting in fastboot.

This is the same failure class as OnePlus 7T Pro (`hotdog-linux-bringup`) D1: ABL accepts the image, then comes back to `18d1:d00d` before USB gadget. On hotdog the fix was not “just RAID6”; it was a **transformed DTB plus filtered stock DTBO** so vendor UFS/regulator overlays apply to the mainline tree. Guacamole needs that same overlay bridge next. The rebuilt `Image.gz` is in `out/kernel-raid6fix/`.
