# Shell controls — toasts, grouping, quick settings, weather, performance

Userspace-only work on the portable mobile shell. Kernel #188, charging policy,
suspend observers and audio modules are unchanged.

## Installed

- Heads-up notification toasts while the shade is closed. Tap opens the shade;
  swipe up dismisses the banner only. Do Not Disturb and an open shade suppress
  toasts. At most one visible toast, with two queued.
- Notifications in the shade group by application. A group shows a count and the
  latest summary; expand to see each card. × on the group dismisses every item.
- Compact quick-settings row: Wi-Fi radio on/off (NetworkManager), mute (existing
  volume helper), and DND (saved in `omarchy-mobile/prefs.json`). Brightness,
  Bluetooth and flashlight are not added.
- Status-bar CPU/RAM chip (two small bars, no extra text). Tap opens a
  performance panel: overall CPU, memory, load, per-core bars, thermal zones,
  battery current, and processes ranked by CPU time share. This is not a
  milliwatt measurement.
- Weather panel uses Open-Meteo condition kinds, Nerd Font icons, Today /
  Tomorrow / weekday labels, humidity, and a five-day forecast.

## Validation

- Python backends: `tests/test_stats.py` and extended `tests/test_shade_backends.py`.
- QML: `tests/run_touch_qml.sh` — 56 passing, including grouping.
- Installed on the handset 2026-09-18 via `overlay/mobile/install.sh` with the
  OnePlus adapter. Only Quickshell was restarted; Hyprland, kernel and charging
  were left alone. Status/shade/navigation/wallpaper layers came back on PID 8760.
  One startup TypeError on an unconfigured weather binding was fixed and hot-reloaded
  with no TypeError afterward. Physical gesture confirmation is for the user.

## Recovery

Phone backup: `/root/.local/state/omarchy-mobile/backups/20260918-235300`.
Restore that backup and restart only Quickshell to undo. Do not flash or change
charging policy to revert UI.
