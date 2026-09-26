# Theme wallpapers — 2026-09-17

Installed on the native2 #179 phone without another flash. Appearance now shows
an image preview and **Next wallpaper**. Selecting a theme applies its colors
and background; the minimal-Arch adapter remembers a wallpaper per theme.

## Implementation

- `overlay/mobile/theme.py` reads standard theme `backgrounds/` folders and
  user backgrounds in `~/.config/omarchy/backgrounds/<theme>/`. User files
  override matching filenames while retaining the other stock backgrounds.
- Full Omarchy's current theme/background state is preferred, including the
  current state-directory layout and the older config-directory symlinks.
  With the real CLI installed, selection/cycling delegates to `omarchy theme
  set` / `omarchy theme bg next`; these execute outside the mobile lock so a
  theme hook can synchronize mobile state without deadlocking.
- Minimal Arch selection stays in mobile-owned `selected-theme` and
  `backgrounds.json`. It does not write fake Omarchy state. Missing images
  fall back to the first available background, or the theme color if none
  exist. Standard repository installation remains future work.
- 92 unchanged stock background images across 22 themes were copied from the
  host's Omarchy installation, with paths/hashes in
  `overlay/mobile/themes/backgrounds.sha256.json`. No image generation or
  transformation was needed. Theme provenance/license notes accompany them.
- Shared `Wallpaper.qml` draws one background layer per screen, follows screen
  geometry, ignores input, crops proportionally and loads images asynchronously.
  It retains the prior image while the replacement loads. Image URLs include
  file modification time so replacing a standard current-theme file reloads it.
  Appearance reports decoding errors and disables cycling when fewer than two
  backgrounds exist.
- Wallpaper-only changes update state without restarting the keyboard,
  signaling Kitty, or changing Hyprland settings.
- The OnePlus session adapter retires only the exact legacy
  `/usr/bin/swaybg -i /usr/share/hypr/wall0.png -m fill` process after the mobile
  wallpaper layer exists. Frozen native2 still launches that fallback first;
  the persistent adapter handles it after boot. No generic process killing
  or board-specific paths were added to the shared wallpaper code.

## Validation

- Seven isolated tests cover persistence/wraparound, stock/user overlays, current
  Omarchy precedence, legacy symlinks, missing backgrounds, URL escaping and
  absence of keyboard/terminal side effects for wallpaper-only changes, and
  the optional device hook receiving the image path as a single argument.
  Run `python3 -m unittest discover -s tests -p test_mobile_theme.py -v`.
- QML lint passed for Wallpaper/MobileTheme. All 92 images passed ImageMagick
  format validation; images remain byte-identical to their source manifest.
- Live cycling changed the selected file without changing the keyboard PID.
  Switching Vantablack → Tokyo Night → Vantablack restored its selected image.
  The test restored the user's original theme/background afterward.
- Restart test reproduced native2's order (legacy swaybg first, mobile shell
  second). The chosen Osaka Jade wallpaper returned; exactly one mobile
  wallpaper layer remained, fallback swaybg was removed, and existing window
  addresses were preserved. Hyprland configuration errors were empty.
- This is a **shell restart test**, not another complete phone reboot. The
  persistent startup path is installed; verify again on the next routine reboot.
- Wayland capture confirmed a rendered background. The user confirmed that
  wallpapers are visible and change correctly.


## Follow-up from physical testing

The user confirmed wallpapers work, then noticed a pulsing button and the old
wallpaper briefly showing during the restart test. Both paths were addressed:

- Routine three-second sync no longer toggles the button's busy/dimmed state.
  Busy feedback is reserved for requested changes. A tap during sync is queued
  instead of ignored. A 7.2-second QML check spanning multiple syncs recorded
  zero busy-state transitions and no unintended wallpaper changes.
- The singleton loads its saved palette/background synchronously at creation;
  the same QML check saw the chosen Osaka Jade image at component completion,
  before the asynchronous sync finished.
- The OnePlus-only `wallpaper-apply.sh` keeps native2's legacy boot image path
  as a symlink to the chosen wallpaper. Its original contents were backed up
  before replacement. A shared, optional trusted user-config hook invokes the
  board adapter when the wallpaper changes; imported theme code is never run.
  The session adapter also establishes the link at startup. This fixes the
  old fixed image without another kernel flash.
- The native2-order restart check passed again with the updated fallback and
  cached startup state; all existing windows remained open. Visual confirmation
  of these two follow-up fixes is pending. A full hardware reboot was not run.

## Recovery and evidence

Phone backup: `/root/backups/wallpaper-20260917/` contains the prior shell,
theme helper, device adapter, Hyprland/Kitty config and mobile state. The original
boot wallpaper is at `~/.local/state/omarchy-mobile/backups/boot-wallpaper/wall0.png`.
Evidence/source bundle: `out/checkpoints/20260917-wallpapers/`.
Working logs, captures and test scripts: `out/wallpaper-test/`.

To restore this change only, restore the backed-up Quickshell directory,
`omarchy-mobile-theme`, and `omarchy-mobile/session-prepare`; remove the new
`omarchy-mobile/wallpaper-apply` hook and restore the original boot wallpaper
if desired. Then restart the
mobile shell. If the old fixed wallpaper is needed immediately, launch its
swaybg command above. Preserve the patched keyboard binary and native2 images;
neither changed during wallpaper work.
