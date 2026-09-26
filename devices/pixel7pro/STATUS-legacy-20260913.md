# Pixel 7 Pro (cheetah) — resume notes

**Superseded 2026-09-24:** The user has restarted the Linux project. Current
observations and the explanation of the boot-image read-back discrepancy are in
[docs/restart-20260924.md](docs/restart-20260924.md). Everything below is
historical; do not assume its restore commands or fallback-slot claims are current.

**Date:** 2026-09-13  
**Serial:** `<serial>`  

Linux-on-this-phone is **cancelled**. Next Linux target is a **OnePlus 7 Pro**. This file is only how to get the Pixel usable again.

The phone was **unplugged / shut down** after a stock factory `fastboot update` still bootlooped. Comfortable stopping point: **display works**, **Power+Vol Down reaches the fastboot robot**, ABL on UFS is **good**.

---

## Current device state (last known)

| Item | Value |
|---|---|
| Screen | Works. Bootloop: Google logo a while → bootloader robot. Not black-screen bootrom. |
| Fastboot | `Power + Volume Down` until robot. ABL: `cloudripper-15.1-12292122` |
| `nos-production` | **yes** (when on the *good* robot) |
| `unlocked` | **yes** |
| Slot | `a`, retries often 1 after a failed boot — `fastboot set_active a` resets to 3 |
| Super / system | **Official stock AP4A.250205.002** written 2026-09-13 (`fastboot update` 23/23 sparse OK). Still **did not stay in Android**. |
| Userdata / metadata | **Erased** 2026-09-13 (Magisk `/data` wipe). First-boot wizard expected if it ever boots. |
| `bootloader` partition | **15.1-12292122 flashed to UFS** from factory `bootloader.img` while on a good RAM ABL. |
| Linux images | Do **not** flash stub DT / mainline again unless you mean to. |

If the robot shows **`NOS production: error`** and **`device state: error`**, that is **RAM ABL `cloudripper-1.0-8910487`** from a *Power-only* EUB load. **Do not flash, do not Start, do not Restart bootloader.** That ABL returns `error getting device locked state -1`. Use the **3-button EUB** path below to get `NOS production: yes`.

---

## Do not

- `fastboot reboot-bootloader` on error ABL → drops to black-screen **Pixel ROM Recovery** (`18d1:4f00`).
- `fastboot reboot recovery` / `reboot fastboot` while Magisk/userspace is broken → same Google-logo loop (needs ramdisk).
- Flash **8MB padded** `init_boot` on a wedged cable (historically killed USB send). Compact ~2.5MB is OK; factory `update` did write 8MB `init_boot` successfully on 15.1 ABL.
- `fastboot oem list-oem-cmds` — hung this cable.
- Hold Power+Vol Down for **90s** — that is how we first entered **EUB / bootrom**.
- Flash slot **B**.
- `CMDLINE_FORCE`.
- Factory reset again unless you intend to; userdata is already wiped.

---

## How we got a flashable robot (the thing that actually worked)

Power-only (or Power+Vol Down) EUB always logged **`Requested DPM` first** → robot with **NOS error** → cannot flash.

**3-button plug-in** logged **`Requested BL1` first** → robot with **NOS production: yes** / **unlocked: yes** → flashes OK.

1. Unplug.  
2. Hold **Power + Vol Up + Vol Down**.  
3. Plug in **while holding all three** (~15s). Laptop USB port, not dock.  
4. Let go.  
5. Host should see `18d1:4f00` + `/dev/ttyACM0`.  
6. `sudo chmod a+rw /dev/ttyACM0` (or a chmod loop *before* plugging).  
7. Send bootloaders with tensor-usbdl (see tools).  
8. Wait for robot. Confirm `nos-production: yes` and `unlocked: yes`.  
9. **`fastboot flash bootloader`** factory `bootloader-cheetah-cloudripper-15.1-12292122.img`.  
10. **Then** `fastboot reboot-bootloader` (only after 15.1 is on UFS and this robot is the *good* one).  
11. Confirm ABL still `15.1` + NOS yes. Then flash OS. Never reboot-bootloader on the *error* robot.

EUB USB (`4f00`) often **only stays while Power is held** until a full payload has been sent; after BL3B it can sit for minutes–hours then jump to ABL. Unplugged, the phone goes dark; bootrom is still in the SoC — restorable later. Plugged `4f00` can sip VBUS; not Android fast-charge.

---

## Tools and images (on this machine)

| What | Path |
|---|---|
| tensor-usbdl (EINTR retry build) | `out/unbrick/tensor-usbdl-bin/tensor-usbdl` |
| gs201 split images (ABL in tree is **1.0-8910487**) | `out/unbrick/tensor-usbdl-bin/sources/gs201/` |
| Official factory zip | `out/unbrick/factory/cheetah-ap4a.250205.002-factory-6a87c591.zip` |
| Factory bootloader 15.1 | `out/unbrick/factory/bootloader-cheetah-cloudripper-15.1-12292122.img` |
| Inner `image-cheetah-*.zip` (extracted) | `/tmp/cheetah-fac/cheetah-ap4a.250205.002/image-cheetah-ap4a.250205.002.zip` (tmp — may be gone after reboot) |
| Stock compact init_boot (no Magisk, 2.5MB) | `out/RESTORE-init_boot-stock-compact.img` |
| Evolution dump (Sep 8 slot A) | `out/device-slot-a/` (`boot.img`, `vendor_boot.img`, `vendor_kernel_boot.img`, `dtbo.img`, `vbmeta.img`, …) |
| Magisk compact init_boot from that dump | `out/RESTORE-init_boot-dump-compact.img` |
| Restore script (Evolution dumps + vkb + vbmeta) | `scripts/restore-mainline-slot-a.sh` |

**`--factory` in tensor-usbdl is a stub** (`TODO: Actually use the FBPKv2`). It still sends `sources/gs201/abl.img` (**1.0**). That is why we kept getting NOS-error robots until 3-button + then flashing 15.1 `bootloader.img` from fastboot.

Send command that completed BL3B:

```bash
cd out/unbrick/tensor-usbdl-bin
./tensor-usbdl --src sources/gs201
# after good robot (NOS yes):
fastboot flash bootloader ../factory/bootloader-cheetah-cloudripper-15.1-12292122.img
fastboot reboot-bootloader
```

---

## What we already wrote (2026-09-13)

All **OKAY** on 15.1 ABL:

- `bootloader` → 15.1-12292122  
- Evolution dump: `boot_a`, Magisk `init_boot_a`, `vendor_kernel_boot_a`, `vendor_boot_a`, `dtbo_a`, `vbmeta_a` (disable-verity)  
- Stock compact `init_boot_a` (no Magisk) — still looped  
- `erase userdata`, `erase metadata`  
- **`fastboot --skip-reboot update image-cheetah-ap4a.250205.002.zip`** — full super (system/product/vendor/… 23/23 sparse) **OKAY**, then `fastboot reboot`. USB gone ~5+ min; user reported **still bootlooping**, then shut down.

So: **UFS bootloader + full stock super are on disk.** Remaining failure is “stock AP4A still doesn’t stay in Android” (first boot after wipe can be slow; also possible `radio` not flashed, AVB/vbmeta_system, or need `fastboot -w` + `flash-all` including radio).

Factory `flash-all.sh` also flashes **radio** (`radio-cheetah-g5300q-240919-241106-b-12612898.img` in the factory zip). **`fastboot update` did not flash radio.** Worth doing next:

```bash
fastboot flash radio out/unbrick/factory/cheetah-ap4a.250205.002/radio-cheetah-*.img
# extract radio from the factory zip if not already:
# unzip cheetah-ap4a.250205.002-factory-*.zip '*/radio-cheetah-*.img'
fastboot reboot
```

Or run the official `flash-all.sh` from the extracted factory dir (**wipes again** unless you edit `-w` out).

---

## Next session — suggested order

1. Power + Vol Down → robot. Confirm `15.1`, `nos-production: yes`, `unlocked: yes`. If **error** robot → 3-button EUB, do **not** Start.  
2. `fastboot flash radio` from factory zip (missing from `update`).  
3. `fastboot set_active a` and `fastboot reboot`. Wait several minutes (first boot). Enable USB debugging on setup.  
4. If still G→robot: `fastboot reboot recovery` from **good** 15.1 ABL only; Advanced → Enter **fastbootd**; `fastboot reboot`.  
5. Last resort: factory `flash-all.sh` (stock Pixel, not Evolution). Reinstall Evolution from a working OS later.

---

## Linux bring-up (do not resume on this phone)

GKI ramdisk USB died on HSI2C/TCPC hang. Mainline 7.3 + **vendor DT** never reached PID 1 (210s WDT). Stub cheetah DT in `vendor_kernel_boot` + 15s/25s PID1: **56s retry 3→1 twice** — sleep length did **not** change, so not proven `/init`. 3-button EUB is unrelated to Linux. See `docs/mainline.md`, `out/mainline/NOTES.txt`, `mainline/dts/gs201-cheetah-stub.dts`.
