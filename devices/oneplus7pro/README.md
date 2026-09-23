# OnePlus 7 Pro / guacamole adapter

This directory owns device-specific configuration. Portable shell code lives
in `overlay/mobile/`.

- `mobile.json`: scale 3 (1440×3120 becomes 480×1040 logical), keyboard sizes,
  four workspace shortcuts, and SUPER+Q for Kitty (formerly missing foot).
- `desktop-prepare.sh`: touch1 overwrites its Hyprland baseline in `/etc` at
  boot. Append the persistent mobile override and validate a reload. This
  adapter is intentionally specific to the current root/chroot session.
- `quickshell-bootstrap.qml`: bridge touch1's default Quickshell launch to
  the portable named configuration with the correct runtime/display.
- `suspend.py`: native5 explicit s2idle with charger/battery/wake guards and
  input rediscovery on resume, installed as `/usr/local/sbin/guacamole-suspend`.
- `power-suspend.sh`: optional shared-shell suspend adapter delegating to that
  board command. No privileged hardware policy is embedded in shared bindings.
- `boot-slot.py`: reads the A/B slot flags ABL keeps in the `boot_a`/`boot_b`
  GPT entries on `sde`, and marks the running slot successful so ABL stops
  spending a boot retry on it. It changes one bit in both GPT copies and their
  CRCs, and refuses mismatched copies, an unbootable slot or two active slots.
  Installed as `/usr/local/sbin/guacamole-boot-slot`; `desktop-prepare.sh`
  runs it a minute after the desktop is up when `/root/boot-slot/autostart-enabled`
  exists. `fastboot set_active` clears the bit, so a newly flashed kernel must
  reach the desktop before it is marked.
- `kernel/touch/`: S6SY761 reset support, OnePlus rail setup, DT overlay and
  overlay loader. These files were moved without changing their contents.

Kernel/firmware and recovery details remain in
[`docs/touchscreen-work-20260916.md`](../../docs/touchscreen-work-20260916.md),
[`docs/cpu-gpu-work-20260916.md`](../../docs/cpu-gpu-work-20260916.md) and
[`docs/status.md`](../../docs/status.md). Slot A remains untouched.
