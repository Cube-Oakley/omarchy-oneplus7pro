# Pixel 7 Pro (cheetah) native Linux bring-up log

Unit: serial kept locally in `out/device.serial`, Evolution X 15.0 10.3, kernel
`5.10.214-android13-4` GKI. Dual-boot safety net is Evolution X on
slot `_a` with Magisk. Restore image:
`out/RESTORE-init_boot-compact.img` (~2.2M). Do **not** flash the
8MB padded Magisk `init_boot` — it wedges fastboot USB on this cable.

This file is the running experiment log for a later public writeup.
Per-flash dumps live under `out/root-dump/after-flashN/`.

## 2026-09-11 afternoon (flashes 58–73)

Unattended auto-fastboot still works when PID 1 `rebootbl`s.

**I2C:** `i2c-exynos5` insmod does **not** finish in 50s in this ramdisk
(child hangs; PID 1 still rebootbl). 70s wait hung the kernel (62).
All-6 HSI2C `driver_override=none` did not make insmod return (71–72
extra=0). Flash 59 extra=120 at 251s was likely `autoprobe=0` + slow
reboot, not a real HSI2C driver. Flash 63 (59 replay) **bootlooped**.

**PHY/DWC3 without I2C:** Flash 64 extra=60 (`usb_data_enabled` sysfs
exists after PHY+glue bind + write `enabled`). Replay 67 extra=0.
Write after 5s wait hung (65). Glue-only (66) and bind-without-write
(73) extra=0. Live gadget uses `usb_data_enabled=enabled` (not `1`)
and `dwc3_exynos_otg_b_sess=1`; `new_data_role` is read-only.

**Next:** need `11210000.dwc3` in `/sys/class/udc` without hanging
PHY probe. Mainline oriole used `role-switch-default-mode=peripheral`
and skipped TCPC; vendor DT still waits on `i2c:13-0025`.

## STOPPED 2026-09-11 00:14 PDT — morning

Flash **57** hung: PID 1 `insmod i2c-exynos5` (isolate, no bind).
Flashed 00:08:49, USB still `none` at 00:14 (5.5 min). Expected
auto-fastboot by ~4 min. Overnight cycling **stopped**.

**Morning:** hold Power+Vol Down **through** the Google logo to
fastboot. Compact restore:
`out/RESTORE-init_boot-compact.img` both slots, `set_active a`.
Notes: `out/root-dump/after-flash57/NOTES.txt`.

Last unattended auto-fastboot: flash 56 at 107s, extra=0
(`exynos5-hsi2c` driver sysfs absent). Flash 52 looked like extra=120
(module + `13-0025` node) at 219s — not reproduced.

## Session 2026-09-09 night (flashes 37–40)

Phone is **back on Evolution X** slot `_a`, Magisk root, ADB
`<serial>`. Compact restore on both slots.

Phone is **back on Evolution X** slot `_a`, Magisk root, ADB
`<serial>`. Compact restore on `init_boot_a` and `_b`.

**Overall:** ~50–60% of a ramdisk USB root shell; ~5–10% of a usable
Omarchy device. Next work is still that shell.

**Flash 37 (valid pstore, first since 14):** cap 100 + skip UFS/PHY/DWC3/
xhci/watchdogs/touch, dump, **idle**, hold-through. `local m` **works**.
PHY and DWC3 insert as deps of `exynos-pd.ko` (`sys=y`, `exynos-dwc3`
and `phy_exynos_usbdrd` in `pdrv`). `pd-hsi0: on`. UDC still
`dummy_udc.0`. Both PHY and USB `waiting_for_supplier=1`. `i2c_mod=n`.
Live Android PHY also waits on `i2c:13-0025` (TCPC); that device is
missing until `i2c-exynos5.ko` probes. Cap stopped at `bc_max77759.ko`
(`tcpci_max77759` already inserted via deps). Idle at t=36s still dummy
UDC. Log: `out/root-dump/after-flash37/`.

**Log that survives:** dump to kmsg then **idle** (no `rebootbl`) and
hold Power+Vol Down **through** the logo. `reboot()` still tears
ramoops (`start = size+114`).

**Hangs PID 1 (frozen Google logo):** UFS probe; PHY probe once
suppliers are ready (flash 28); full `modules.load` after ~100
(drm/panel/aoc/trusty). Flash 38 therefore loads I2C in a **child**.

**Restore (compact only):** `scripts/restore-init-boot.sh` or
`out/RESTORE-init_boot-compact.img` sha256
`8c68dccb74fe17e07e4b31e62c975f5adddc5b5da70e5f5dc5a220127874e07a`.
Never the 8MB padded `out/RESTORE-init_boot.img` on this cable.

**Code on disk:** `ramdisk/init.sh` is the flash-36 script (no cap,
same skip list, dump, rebootbl). `ramdisk/init-min.sh` is the proven
43s min ramdisk. `ramdisk/rebootbl.c` is RESTART2 `"bootloader"`.
`scripts/build-ramdisk.sh` takes `INIT_SH=`. Packed image
`out/ramdisk-usb/init_boot-usb.img` is flash 36 (the one that froze).

## What we already know (live Android)

- UDC `11210000.dwc3` (never `dummy_udc.0`). Compatible
  `samsung,exynos9-dwusb`. PHY `11200000.phy`.
- ACM-only gadget works if the USB HAL is stopped: host `ttyACM0` root
  shell. Recipe in `docs/usb.md`.
- `CONFIG_DEVTMPFS=n` — `/dev` is tmpfs + mknod.
- Magisk busybox `sleep` hangs as PID 1; use `/proc/uptime` spin.
- `fastboot boot` ignores ramdisk; must flash `init_boot_a` **and** `_b`.
- Power+Vol Down for ~8s is a **warm kernel reboot** (Google logo
  again), not fastboot. Fastboot requires holding **through** BL1
  (logo, black, next logo) until the menu. Softdog (`soft_margin=60`)
  also dumps to bootloader and tears ramoops.
- Ramoops: 4MiB at `0xfd3ff000`, console 2MiB, pmsg 2MiB, no dmesg
  record-size. Hard/kernel reboot often leaves
  `invalid buffer, size N, start N+114` and Android discards the log.
  Flash 14 survived because buttons were pressed during **idle** after
  dumps (~58s), not mid-insmod.
- Persist `/dev/block/sda1` mounts from Android. In the ramdisk, ext4
  mount on the mknod'd `8,1` node **hangs PID 1** (flash 5, 18) and a
  hung mount **blocks `reboot()`** (flash 24). Do not mount persist
  from `/init`.
- `/dev/pmsg0` on this GKI is `252,0`, not `10,1`. Unused so far;
  console ramoops is the log we actually read when it is valid.

## Flash timeline (2026-09-09)

| N | What changed | Result |
|---|---|---|
| 1–4 | C init, tmpfs+mknod, module order (pd, pmic, I2C) | PHY/DWC3 insert; UDC still dummy; persist too early |
| 5 | persist remount after modules | PID 1 hung on ext4 sda1 |
| 7–9 | skip persist; Magisk `sleep` vs `wait_s` | `wait_s` works; dummy UDC; fake ttyGS0 |
| 10 | `modules.load` order | dwc3-exynos unknown symbol |
| 11–12 | dep walker; File exists = ok | ok=192 but PHY not in `/sys/module` |
| 13 | sysfs dump | `waiting_for_supplier`; suppliers PHY, pd-hsi0, clock; no `exynos-dwc3` driver |
| 14 | force PHY via `/sys/module` | **`$m` clobber** — never insmod'd PHY. **Valid pstore** (buttons at idle t=58s). Last good log. |
| 15–17 | `local m` in `insmod_one` | USB hung; ramoops invalid +114; no log. `local m` **unconfirmed**. |
| 18 | persist remount after dumps | softdog/hang → auto fastboot; persist never wrote |
| 19 | skip softdog.ko | ~60s hold (softdog still? or keys). pstore invalid |
| 20 | skip softdog | logo gone <10s (panel); immediate hold mid-insmod; invalid pstore |
| 21 | quiet printk after dump | missed logo; ramdisk **did** run (~157KB discarded) |
| 22 | pmsg 252,0 | 8s holds = warm reboot loop; pstore empty |
| 23 | `rebootbl` (RESTART2 `"bootloader"`) | **auto-fastboot at 75s, no buttons.** pstore still invalid +114; pmsg empty |
| 24 | persist mount in child | child mount blocked `reboot()`; frozen; persist log never appeared |
| 25 | no post-modules persist; still C-init persist | frozen Google logo; empty ramoops (no invalid-buffer line) |
| 26 | skip persist in C init too | frozen Google logo again; empty pstore; user hold-through |

## Current hypothesis

1. `rebootbl` **can** work (flash 23). Later hangs are PID 1 blocking
   *before* `exec /rebootbl` (persist, trybind/gadget, or early
   `/init`).
2. `local m` still unproven. Flash 14 showed the clobber; 15+ never
   produced a readable log.
3. Flash 27 **minimal** ramdisk (no modules): auto-fastboot in **43s**.
   `rebootbl` is proven. Pstore still empty after that reboot.
4. Flash 28: full `modules.load` + `local m` force PHY, dump, rebootbl
   (no trybind). Frozen logo. pstore invalid 165974/+114.
5. Flash 29: skip PHY/DWC3/xhci, still full `modules.load`. Frozen.
6. Flash 27 min: auto-fastboot **43s**. Flash 30 cap=30: **51s**. Flash 31
   cap=50: **51s**. Flash 32 cap=100: **frozen**. Hanger is in
   `modules.load` ~51–100 (watchdogs, s2mpg, iommu, UFS, tcpci, i2c).
   `reboot()` still yields empty pstore; cycle works without Android
   restore — flash next image from fastboot.
7. Flash 33 cap=70 + skip hardlockup: auto-fastboot **53s**.
   Flash 34 cap=100 skip hardlockup: frozen.
8. Flash 35 cap=100 skip UFS+watchdogs+PHY: auto-fastboot **55s**.
   **UFS probe was the cap-100 hang.**
9. Flash 36 no cap, still skip UFS/PHY/watchdogs: frozen (later
   modules: drm/panel/aoc/trusty/tcpci). Unattended-safe set is
   cap 100 minus UFS/PHY/DWC3/xhci/ehld/softdog/hardlockup/touch.
10. Flash 37: same set + idle + hold-through. **Valid pstore.**
    `local m` confirmed. PHY/DWC3 load as `exynos-pd` deps. UDC dummy.
    PHY/USB `waiting_for_supplier=1`. Live extra supplier is
    `i2c:13-0025` (`10d60000.hsi2c`). `i2c_mod=n`.
11. Flash 38: child `i2c-exynos5`. Hung. ramoops invalid 140106/+114.
12. Flash 39: PHY/USB `driver_override=none`, only `10d60000.hsi2c`,
    child i2c. Still hung. invalid 136975/+114. Hang is HSI2C probe
    itself (needs `set usi mode` + `ipclk_hsi2c`), not PHY.
13. Flash 40: no i2c insmod; dump HSI2C sysfs + `driver_override`.
    Hold-through ~2m. **Empty pstore** (no invalid-buffer line). New
    sysfs may hang before ramoops has a record. Next dump must stay
    read-only (no `driver_override`).

**Autonomous logging:** none. Persist/UFS hangs PID 1. Console ramoops
and pmsg (2MiB zone, `/dev/pmsg0` 252,0) both die on `reboot()`.
`rebootbl` **does** auto-fastboot in ~60s (flash 35/43/44) — use that
for “did it hang?”; host `ttyACM0` is the only success signal that
does not need a hold.

14. Flash 43: dump to pmsg + `rebootbl`. Auto-fastboot 60s, no hold.
    Pstore empty, no invalid-buffer line. Pmsg did not survive.
15. Flash 44: child bind PHY/DWC3, ACM if real UDC else `rebootbl`.
    Auto-fastboot ~78s (bind did **not** hang). No `ttyACM0`. Bind
    without I2C does not produce `11210000.dwc3`. Blocker remains
    `i2c-exynos5` / HSI2C probe (USI MMIO), which hangs (38/39).

## Host USB

Restore must use the **compact** Magisk init_boot (~2.2M). 8MB padded
image `SendBuffer` hangs; unplug/replug is not enough — **Restart
bootloader** from the phone menu resets the gadget.

## Restore

```
fastboot flash init_boot_a out/RESTORE-init_boot-compact.img
fastboot flash init_boot_b out/RESTORE-init_boot-compact.img
fastboot set_active a
fastboot reboot
```

## Mainline 2026-09-11 evening

First mainline 7.3 Image on **slot A only** (vendor DTB from vendor_boot,
timed rebootbl initramfs). Auto-fastboot ~80s (17:49:41→17:51:01). No
ACM. Strong signal the kernel reached `/init`. Evolution X restored on
`boot_a`+`init_boot_a`. Slot B untouched.
