# Mobile roadmap

Updated from the user's 2026-09-17 requirements. Shared shell, input and service
policy belongs in `overlay/mobile/`; board-specific kernel, firmware, audio
routing and charging support belongs in `devices/oneplus7pro/`.

## Current order

1. Deeper suspend: measure SoC/CPU residency, identify blockers, test individual
   fixes with RTC recovery, then repeat battery measurements. Keep verified
   charging, physical wake and input/network recovery intact. Follow with idle
   policy, background wakes, CPU frequency scaling and true shutdown.
2. **Cellular foundations and audio are phone-critical.** Do not postpone modem
   discovery until a SIM is available: validate read-only QMI/QRTR, SIM detection,
   carrier-configuration prerequisites and the IPA data path first. Data, SMS
   and voice/IMS are separate milestones; registration and end-to-end tests need
   service. Do not equate a running remoteproc with a usable cellular modem.
3. **Audio is critical:** main loudspeaker, call earpiece and microphones.
   Bring up capture/playback and routing independently of Bluetooth or a SIM.
   Verify levels, mute, speaker/earpiece switching and later call audio.
   Add haptic motor support and consistent, configurable gesture feedback.
4. Notification/quick-settings shade in Quickshell: network picker and Wi-Fi
   status, a detailed power/battery widget, brightness and useful toggles.
   Report measured net battery mA, voltage, temperature and available charger
   information; distinguish input current from battery current and limits.
   Include actual notification history/actions, not only quick toggles. Separate
   notification presentation from background delivery/wake. Keep this as an early
   usable milestone rather than waiting for complete telephony or perfect sleep.
5. Input and daily usability: copy/paste, touch text selection/highlighting and
   selection handles, context menus, touch window resizing. Investigate a
   keyboard with swipe typing, autocorrect and suggestions, while retaining
   reliable manual show/hide and avoiding duplicate keyboard surfaces.
6. Bluetooth, GPS and later camera bring-up. Active cellular data, SMS and call
   validation proceeds when service is available, with audio as a call prerequisite.
7. USB-C docking: investigate native DisplayPort output, external monitor
   layout/scaling, USB host keyboard/mouse and USB Ethernet, including simultaneous
   charging. Test a Lenovo USB-C dock when its exact model is known. Verify
   the phone's Type-C/DP routing, role switching, PHY and kernel support first;
   USB peripherals and monitor output are separate milestones. Keep generic
   dock/session behavior in the shared shell and hardware enablement per device.

## Status bar and appearance

- Vertical battery icon, with the charging lightning bolt inside and percentage
  immediately alongside. Add a Wi-Fi connection/signal icon now.
- Later settings: show/hide battery percentage, optional thin battery bar
  along the top edge, and configurable status indicators. Avoid hardcoding
  these preferences into a OnePlus-only shell.
- Continue standard Omarchy theme repository compatibility, installation,
  selection, wallpaper and app-wide theme integration.
- Future fast charging needs the appropriate charger/cable and verified
  negotiation, temperature limits, taper and fault handling. Raising the
  existing conservative limits alone does not implement fast charging.

## Standard user session

Move the compositor, mobile shell and ordinary applications out of the root
bring-up session into a standard user account. Provide sudo for administrative
terminal work and narrowly scoped privileged services for hardware management.
Plan home/config/profile ownership migration, device/seat permissions, the user
D-Bus session, notifications and safe recovery access. Verify boot, networking,
charging, sleep/wake and touch before retiring the root desktop. The separate
`mobile-browser` account and display-socket ACL are a temporary Chromium bridge,
explicitly approved by the user on Sep 18, not the intended final session design.

## Phone/desktop integration

Build a paired service usable between Omarchy phones and Omarchy desktops:
theme selection/sync, clipboard copy/paste sync, phone notifications on the
desktop, and eventually SMS/call integration. Use explicit pairing and
per-feature controls; keep clipboard sharing opt-in. Separate the transport
and service from device adapters and Quickshell presentation. Evaluate existing
protocols/services before inventing a new one; preserve standard Omarchy theme
formats on both ends. Background delivery must fit the sleep/wake design.

See [next session](next-session.md) for checkpoints and recovery instructions,
and [background wake design](background-wake-plan.md) for notification delivery
while asleep. This is a backlog, not a claim of completed hardware support.

- Add a themed font picker to mobile settings; initial user choice is JetBrainsMono Nerd Font for the shell and Kitty. Preserve the choice across theme changes.
