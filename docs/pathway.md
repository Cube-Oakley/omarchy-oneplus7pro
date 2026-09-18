# Pathway: Omarchy on OnePlus 7 Pro

Omarchy is Arch + Hyprland + Quickshell. This phone is a Snapdragon 855 with a working mainline DTB already in the shared SM8150 kernel. The job is not “port Android.” It is: boot a real Linux kernel, put an Arch userspace on it, overlay Omarchy, then teach that desktop to be a phone.

## What already exists

| Layer | Status | Source |
|---|---|---|
| Mainline DTB `sm8150-oneplus-guacamole.dtb` | In the SM8150 pmOS kernel package (6.17) | `linux-postmarketos-qcom-sm8150` |
| Device package `device-oneplus-guacamole` | postmarketOS *testing* | pmaports |
| Shared SM8150 SoC | CPU, UFS, USB, GPU, Wi-Fi, BT, display, cameras *as a platform* | [SM8150 wiki](https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_855_(SM8150)), [sm8150-mainline](https://gitlab.com/sm8150-mainline/linux) |
| Sister bring-up OnePlus 7T Pro (`hotdog`) | Direct ABL boot, 1440×3120 DSC, Turnip, touch, Wi-Fi, four cameras including pop-up IMX471, USB-C DP, modem QMI up | [Sr-0w/hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup) (reviewed 2026-08-25) |
| guacamole pmOS page (May 2025) | Flashing and USB net work; touch works; screen *partial*; Wi-Fi listed broken; modem/camera untested | wiki `oneplus-guacamole` |
| Omarchy aarch64 packages | **Do not exist.** `pkgs.omarchy.org/stable/aarch64` 404s | [omarchy-arm-utm notes](https://github.com/ggalancs/omarchy-arm-utm), [moarchy](https://github.com/SimonSchubert/moarchy) |
| Omarchy on a Qualcomm handheld | AYN Thor (SM8550): Hyprland + Quickshell + `wvkbd`, dual-boot via existing ABL | [TensorFleet/omarchy-cm5](https://github.com/TensorFleet/omarchy-cm5) |

guacamole’s wiki row is stale relative to the 7T Pro work. Treat hotdog as the hardware template (same generation, same pop-up camera family, same Adreno 640) and guacamole’s DTB/device package as the starting point, not the ceiling.

Adreno 640 + Freedreno/Turnip gives GLES 3. Hyprland can run. That is the difference versus PinePhone/`moarchy` (Mali-400, Sway only).

## Path we will take

```
fastboot boot (no flash)
    → postmarketOS/mainline kernel + tiny rootfs, USB SSH
        → prove display, touch, UFS, USB
            → Arch Linux ARM rootfs, same kernel/DTB
                → Omarchy 4 overlay (vendored, like omarchy-cm5)
                    → phone layer: OSK, gestures, rotate, modem, camera, audio
```

Do **not** start by installing Omarchy’s x86_64 installer. Do **not** use Halium/Droidian unless mainline fails display/GPU — the 7T Pro already did this without Hybris.

### Phase 0 — backup (this weekend)

User files from `/sdcard` plus firmware/EFS LUNs for unbrick. No app/userdata image. See `docs/backup.md`. Do not flash until `files/` has finished copying.

### Phase 1 — ramdisk boot, Android kept

Build or borrow `linux-postmarketos-qcom-sm8150` with `sm8150-oneplus-guacamole.dtb`. This 2019 ABL has **no** `fastboot boot`; use `fastboot flash boot_b` and keep Android on `_a`. First attempt bounced to fastboot — see [bringup.md](bringup.md). Next is an OOS 11/12 / Lineage firmware update, then the same kernel again.

**Phase 1 USB net is done (2026-09-16):** gadget `1d6b:0104`, `172.16.42.1`, `nc :23` shell, ABL leftover panel showing `guacamole-init: alive`. Not SSH yet, not UFS, not touch. See [status.md](status.md).

Success looks like: USB network `172.16.42.1`, SSH, something on the panel, touch events in `evtest`.

Likely first fights, from guacamole’s own notes plus hotdog:

- DSC/DSI FIFO timeouts (hotdog still marks display *partial*)
- Wi-Fi `ath10k_snoc` / WCN3990 firmware (guacamole wiki: broken; XDA user M1DNYT3 reverse-engineered a working path for a headless guacamole)
- Old Havoc 9 firmware vs blobs the mainline drivers expect

If the panel stays black, USB SSH is still a win. Serial is `ttyMSM0` if we ever get a debug UART.

### Phase 2 — dual-boot slot B

This phone is A/B and does **not** use `super`. Plan:

| Slot | Role |
|---|---|
| `_a` | Current Android (Havoc). Do not overwrite until Linux is boringly bootable. |
| `_b` | Mainline `boot` + `dtbo` + `vbmeta` (disabled verification) |

Rootfs does **not** fit in `system_b` (3.39 GiB). Options, in order of preference:

1. **Dedicated userdata ext4/btrfs** once we are ready to stop using Android day-to-day.
2. **Loop file on Android userdata** for early bring-up ( Magisk/kexec style, as in the guacamole “Linux server” XDA thread ).
3. Shrink userdata — ugly with FBE, skip unless we have to.

`qbootctl` / `fastboot set_active` marks the slot. Always have a way back to `_a`.

### Phase 3 — Arch, not Alpine

postmarketOS is the fastest *kernel* test harness. Omarchy is Arch. After the kernel boots:

- Arch Linux ARM aarch64 rootfs
- systemd (Omarchy assumes it)
- Mesa `freedreno`/`turnip`, `linux-firmware` extracts from `vendor_a`
- NetworkManager, `iio-sensor-proxy`, `hexagonrpcd`/`pd-mapper` as needed

Kernel stays the SM8150 mainline fork (or a guacamole-specific patch series copied from hotdog). Userspace is ours.

### Phase 4 — Omarchy overlay

Same shape as `TensorFleet/omarchy-cm5`:

- Pin a `basecamp/omarchy` Quattro commit in `upstream.lock`
- Install Hyprland + Quickshell from Arch ARM (rebuild Quickshell against Qt private ABI when ALARM breaks it)
- Vendor Omarchy’s `/usr/share/omarchy` instead of `pacman -S omarchy`
- Replace desktop-only assumptions: greeter keyboard, scale, touch

Omarchy 4 dropped the x86_64 `uname` guard; the blocker is the package repo, not the desktop code.

### Phase 5 — make it a phone

| Function | First tool | Notes |
|---|---|---|
| On-screen keyboard | `wvkbd` (Thor) or `squeekboard` | Must work at the greeter, not only inside Hyprland |
| Touch / gestures | Hyprland input + extra binds | 1440×3120, start at `scale 2` |
| Rotation | `iio-sensor-proxy` + Hyprland | hotdog uses libssc → SEE, not raw IIO |
| Wi-Fi | `ath10k_snoc` + WCN3990 firmware | Highest-priority guacamole-specific gap |
| Audio | ALSA UCM, TFA9874 on hotdog | Speakers first, then earpiece/mic |
| Cameras | libcamera | hotdog: IMX586 + IMX481 + S5K3M5 + pop-up IMX471 |
| Pop-up selfie | Hall-bounded motor | Unique 7 Pro/7T Pro; copy hotdog’s lifecycle |
| Modem | ModemManager + QRTR + IPA v4.1 | Even hotdog has no live-SIM call yet |
| USB gadget | NCM + ACM | Recovery SSH if the panel dies |
| Suspend | s2idle | After networking works |

Do not promise calls/SMS in the first bootable image. A usable Linux handheld with USB + Wi-Fi + Hyprland is already a large milestone.

## Paths we are not taking (unless Phase 1 fails)

- **Halium / Droidian / Ubuntu Touch GSI** — Android HALs forever; fights Omarchy.
- **Downstream 4.14 + Anbox/LXC** — fine for a server, wrong GPU/display stack for Hyprland.
- **Windows on ARM (woa-op7)** — unrelated, but proves UEFI/ABL flexibility.
- **Replacing XBL/ABL** — brick path. Boot Linux from OnePlus ABL like hotdog.

## Safety rails

1. No flash until `/sdcard` files have finished copying.
2. Never `fastboot flash` `xbl`, `abl`, `tz`, `aop`, `hyp` while experimenting.
3. `fastboot boot` before `fastboot flash boot_b`.
4. Keep slot `_a` as Android until slot `_b` has booted Linux ten times.
5. MSM/EDL is the unbrick backstop for this family; do not test it for fun.
6. `sdf` (EFS) backup is already more important than photos. It is in the backup set.

## First engineering milestone after backup

Host packages: `android-tools`, `pmbootstrap` (or a direct kernel build), `aarch64-linux-gnu-gcc` or an Arch ARM chroot, `mkbootimg`.

Then a guacamole `boot.img` that we only *boot*, never flash, and a log of: panel mode, `/dev/input`, `usb0` address, dmesg errors for `ath10k`, `qcom-ice`, DSC.
