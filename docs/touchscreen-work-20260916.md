# Touchscreen bring-up — 2026-09-16

## Update — persistent startup verified 2026-09-17

Flashed **touch1 #175** on slot B. Fresh boot automatically brought up CPUs
0–7, USB, the Adreno desktop and S6SY761 input. Desktop and touch helpers report
success, Hyprland and Quickshell report FD640, and `hyprctl devices` lists
`s6sy761`. Touch IRQs are active. No manual module loading or udev replay was
needed. Logs are `out/touch-test/touch1-auto-state.log` and
`out/network-test/initial-phone.log`, also copied into the frozen checkpoint.
No kernel WARN backtrace or Oops was found; the expected overlay removal
warnings described below remain.

USB internet and SSH were subsequently added live; see
[networking setup](usb-networking-20260917.md).

## Initial live verification on gpu2

The phone runs **gpu2 #174**, with automatic Adreno Hyprland + swaybg + the
existing Quickshell bar. The desktop starts at ~110 seconds after the delayed
GPU probe. Its scanout sample hash is `842e271e`, matching the previous working
wallpaper/bar. Eight CPUs and USB networking remain operational.

On this boot, a temporary module/DT-overlay experiment enabled **Samsung
S6SY761 touch input through Hyprland into Quickshell**. The user confirmed
accurate touch and **five fingers simultaneously**. A saved input trace contains
22 contact starts, 6,536 sync reports, X=66..1384 and Y=57..3093, with multiple
simultaneous tracking IDs. The Quickshell app logged corresponding presses and
releases. The controller reports ID `0x3761`.

The test app has been closed; the normal wallpaper and bar are back. Touch
remains active live. No kernel WARN backtrace, Oops, GPU fault or I2C fault was
found in the final log. Loading these diagnostic modules marks the kernel
out-of-tree (`O`). The overlay prints its standard warnings about property
memory leaks **if removed**; the loader deliberately has no unload function
and holds the overlay until reboot. The stock driver also emits an obsolete
ABS_X/ABS_Y warning; its multitouch axes are present and functioning.

## Why it was absent

- QUPv3 wrapper 2, GPI DMA 2 and I2C17 were disabled in the embedded DTB.
- The image had no matching `evdev` or `s6sy761` module installed. Arch's
  installed module tree targets 7.1.6, while the phone runs our custom 6.17.
- There was no udev daemon. Once the device appeared, Hyprland needed
  `ID_INPUT_TOUCHSCREEN=1` from udev to discover it.

## Board wiring and implementation

OnePlus's 18821 downstream `sm8150-oem.dtsi` specifies address **0x48** on
I2C17 (`c80000`), GPIO **122** low-level interrupt, GPIO **54** active-low reset,
GPIO **119** pull-up for the 1.8 V enable, and **PM8150 L17 at 3.008 V** for the
analogue supply. We retain those pin states. The 1.8 V rail is represented as
a fixed supply with the stock enable pinctrl. The live regulator readback
confirmed 3.008 V after the driver's consumer voltage request.

Reference work for the related 7T Pro helped identify the disabled bus parents
and optional-reset driver support:
[hotdog reference](https://github.com/Sr-0w/hotdog-linux-bringup/tree/47087509c4289c2580c54f5433e55366b2e00445).
**Its L1C/L10C power supplies are not this board's wiring.** Local reference
checkout: `.work/hotdog-reference`, revision above.

Files:

- `devices/oneplus7pro/kernel/touch/guacamole-touch.dts`: isolated overlay, also checked offline
  against the frozen DTB with `fdtoverlay`.
- `devices/oneplus7pro/kernel/touch/touch_overlay.c`: Guacamole-only module that applies the
  embedded overlay. Reboot removes this runtime experiment.
- `devices/oneplus7pro/kernel/touch/s6sy761-reset.patch`: attributed optional-reset backport from
  the reference port. No touchscreen firmware flashing is performed.
- `devices/oneplus7pro/kernel/touch/s6sy761-guacamole-probe.patch`: board-specific live consumer
  voltage request and guards for failed-probe IRQ/regulator cleanup. Changing
  an already-probed regulator's DT limits does not reparse its constraints.
- `scripts/build_touch_test.sh`: builds evdev, patched s6sy761 and overlay
  modules against the prepared kernel. Core exports come from
  `vmlinux.symvers`; no unresolved-symbol bypass is used. Modpost prints a
  missing aggregate `Module.symvers` warning; its needed exports are supplied
  explicitly. Module vermagic matches the intended kernel release.
- `scripts/touch-watch.c`: read-only, non-grabbing evdev capture.
- `scripts/quickshell-touch-test.qml`: temporary visual multitouch test.

The udev daemon runs inside the live Arch chroot. For its administrative
commands, `SYSTEMD_IN_CHROOT=0` prevents an offline-chroot no-op. Only input
uevents are replayed. The live startup helper was tested successfully and
Hyprland lists `s6sy761` under Touch without restarting the compositor.

## Persistence image — now flashed and verified

**touch1 #175**, `6.17.0-sm8150-codex-touch1-g379d8fe35c7c-dirty`, is built.
It keeps the gpu2 kernel driver sources and base DTB. Its initramfs adds modules
with matching vermagic and runs `start-touchscreen.sh` **after the accelerated
desktop starts**, preserving the timing of the verified USB/GPU boot path.
The temporary test UI is not autostarted.

Build: `bash scripts/rebuild_touch_desktop.sh`.
Frozen image/source bundle: `out/checkpoints/20260916-touch1/`.
Flash in fastboot: `bash scripts/flash_touch_desktop.sh`.
Rollback: `bash scripts/flash_gpu_desktop.sh` restores verified gpu2 (automatic
GPU desktop, no automatic touch). Slot A is preserved.

Touch startup is persistent and verified on the touch1 reboot.
Sleep/resume, screen-off gestures, palm rejection and long-term stability
remain untested. Native display control is still a separate task.

Evidence: `out/touch-test/{live-probe,udev-start,input-trigger,ui-start,
hardware-interaction,startup-helper-live,final-state}.log` and
`out/cpu-test/gpu2-{auto-verified,auto-scanout,pre-touch-dmesg}.log`.
The exact hardware-tested gpu2 modules are saved under
`out/touch-test/verified-gpu2-modules/`; top-level modules now target touch1.

## Suggested next milestones

1. Boot-test persistent touchscreen and retain a full known-good recovery image.
2. Share the host's internet over USB, then add authenticated SSH and reliable
   package management. This need not wait for the Wi-Fi driver work.
3. Add an on-screen keyboard, readable scaling, a touch-friendly app launcher
   and workspace switcher, using Omarchy styling and Quickshell components.
4. Enable Wi-Fi as a separate hardware milestone; preserve working USB access.
5. Add battery/charging status, brightness, screen-off/wake and suspend/resume.
   Continue native panel work for correct display timing and power control.
6. Refine navigation gestures and app behavior once keyboard/navigation work.

The current shell is a minimal Quickshell bring-up bar and Omarchy wallpaper,
not the complete Omarchy desktop/application setup.
