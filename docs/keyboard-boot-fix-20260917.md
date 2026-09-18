# Keyboard startup after a full reboot

Fixed and installed on 2026-09-17 without flashing a new kernel. The phone
still runs touch1 #175 on slot B.

## Cause

The keyboard helper used Bash process substitution (`mapfile ... < <(...)`).
The minimal initramfs does not create `/dev/fd`, so the first keyboard launch
failed with `/dev/fd/63: No such file or directory`. The host USB setup helper
later created the standard device links, masking this problem during earlier
live development. Launcher and overview startup did not need this path.

`overlay/mobile/keyboard.sh` now captures Python output with command
substitution, then reads it through a here-string. This works without
`/dev/fd` and propagates Python's failure status. The shell runs keyboard
requests through a queued Process and displays/logs a helper failure instead
of silently ignoring it.

## Verification

- Reproduced the original error on a fresh boot, before starting USB SSH.
- Opened the keyboard with the corrected helper while `/dev/fd` was still
  absent. The helper returned success and Hyprland exposed the keyboard layer.
- Installed the helper and shell, then performed a controlled full reboot.
- On boot `59b02db6-5cd9-4058-b2b3-778eb97d68d0`, before running the USB setup
  helper, wvkbd was already running automatically as PID 598. `/dev/fd` was
  still absent. Quickshell's keyboard IPC displayed its layer at
  `0,736 480x280`, alpha 1.
- After restoring SSH: all eight CPUs online, no Hyprland configuration
  errors, Quickshell configuration loaded and rendered on FD640.
- The user confirmed the keyboard and hide/reopen gestures work after this
  reboot: “yeah the keyboard/gestures look good to me”.

Early checks at 33 and 79 seconds preceded desktop startup; they are not
keyboard failures. The successful baseline was captured at 302 seconds.

Evidence: `out/keyboard-boot-test/`, especially `reproduced-failure.log`,
`fixed-without-dev-fd.log`, `after-full-reboot-ready.log`, and `final-health.log`.
Original phone files: `/root/backups/keyboard-boot-20260917/`.

## Separate boot issues

The original missing Linux USB device remains intermittent and unexplained.
Fastboot detected serial $PHONE_SERIAL; rebooting the existing image restored USB,
and the subsequent controlled Linux reboot also restored it. Saved diagnostics
from seven boots include one whose gadget remained `not attached`; those logs
do not establish the cause or prove that the USB problem is fixed.

Normal device links should also be created early in a future initramfs for
other Arch tools. That change is not required for this keyboard fix and has
not been flashed. Actual power-off still reboots the handset; see
[shutdown investigation](shutdown-20260917.md).
