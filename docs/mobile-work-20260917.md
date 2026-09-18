# Mobile userspace checkpoint — 2026-09-17

The phone remains on **touch1 #175**. No additional flash or kernel change was
needed. All eight cores, Adreno rendering and touch remain available.

## Installed and verified

- Scale 3: 480×1040 logical desktop on the 1440×3120 panel.
- Kitty 0.48.2; the user confirmed keyboard input, window opening and tiling.
- wvkbd 0.20 built from upstream commit
  `6b41504a0cb58fd1163fa44692398fbd61f8905f`, without source modifications.
- Persistent Apps/Terminal/Spaces/Keyboard controls; parsed desktop-entry
  launching supports terminal applications such as Vim.
- Swipe up from the bottom navigation surface opens the switcher. Real touch
  generated multiple `MOBILE_GESTURE overview` log entries. Horizontal swipes
  on that surface select adjacent workspaces.
- Window cards with captured previews, focus/maximize/close and move-to-space
  controls. A dedicated test window moved to workspace 3 and back to 2; both
  results were verified through Hyprland, as was maximize.
- Standard Omarchy palettes can be selected under Apps → Appearance. Gruvbox
  and Tokyo Night were tested live; Tokyo Night was restored. Shell, keyboard,
  Kitty and Hyprland border colors share the palette.
- Fastfetch 2.68.1 with the official Omarchy PNG logo, verified on physical
  scanout in Kitty. It honestly reports Arch Linux ARM, OnePlus 7 Pro, eight
  CPUs and Adreno. A Fastfetch launcher is included.
  The final portrait layout uses a small left-hand logo, compact labels and
  wrapping below the logo for the full kernel version (`fastfetch-layout.png`).
- Phone timezone is America/Los_Angeles. USB reconnect still corrects its
  reset-on-boot clock from the host.

## Keyboard behavior and limits

The keyboard uses Wayland virtual-keyboard and input-method-v2 protocols,
not raw input injection. A controlled Qt text field triggered automatic
appearance. Field blur in that client did not reliably send text-input disable,
so universal automatic hiding is **not** claimed. The Keyboard button provides
manual show/hide, and opening the launcher/switcher hides it deliberately.

The keyboard does not take app keyboard focus and reserves 280 logical pixels
in portrait mode. Navigation reserves 90 pixels below it, in the top layer;
the keyboard retains its upstream overlay layer. Restarting the shell while
the keyboard was visible preserved navigation at y=950 and keyboard at y=670.
Normal and maximized application behavior is verified, while fullscreen
application interaction remains to be tested.

## Persistence and layout

The shared code is in `overlay/mobile/`, the OnePlus adapter/profile in
`devices/oneplus7pro/`. Touch wiring/overlay sources moved under the device
directory; recompiling its DT overlay produced byte-identical output.
See [architecture and future ports](mobile-architecture.md).

On the phone, `~/.config/quickshell/shell.qml` is the OnePlus bootstrap. It
launches `~/.config/quickshell/omarchy-mobile/shell.qml` with the current
Hyprland instance identity. This named shell starts the shared helpers under
`~/.local/bin/omarchy-mobile-*`. The adapter adds the mobile Lua override after
touch1's initramfs restores its hardware baseline. This startup chain was
exercised live and after a shell restart; a fresh **phone reboot** with the
final mobile layer remains untested.

The shared layer respects XDG config/state/data paths and contains no phone
serial, USB network address, framebuffer address or root/chroot requirement.
Only this handset has been tested. Full Omarchy installation and repository
theme installation are still future work; see the architecture document for
the intended standard workflow and the Archwave compatibility check.

## Evidence and recovery

- `out/mobile-test/clean-session.log`: fresh shell load without QML errors;
  empty `hyprctl configerrors`. Existing boot-time OF overlay warnings remain.
- `window-actions-verified.log`: workspace move and maximize assertions.
- `keyboard-auto-test2.log`: exact text-input behavior and limitations.
- `navigation-restart-final.log`: corrected keyboard/navigation layers after
  restarting the shell with the keyboard visible.
- `fastfetch-branding.log`: real bottom-swipe events and system view.
- `window-cards.png`, `gruvbox.png`, `fastfetch-branding.png`: snapshots read
  from the actual retained scanout framebuffer.

Original pre-mobile configs: the directory recorded in `/root/mobile-backup-path`
on the phone. Later installer backups:
`~/.local/state/omarchy-mobile/backups/`. The hardware rollback image stays
`out/checkpoints/20260916-touch1/`; restoring the userspace is separate because
the Arch partition persists across flashes. A frozen mobile source/binary/log
bundle is under `out/checkpoints/20260917-mobile/`.

For userspace recovery, stop the named mobile Quickshell instance, restore the
original saved `/etc/hypr/hyprland.lua` and user config directories, reload
Hyprland and check `configerrors`, then start the restored default shell. Stop
only the keyboard PID recorded in `$XDG_RUNTIME_DIR/omarchy-mobile-keyboard.pid`.
SSH/USB recovery is independent of the mobile shell.
