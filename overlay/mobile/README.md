# Omarchy mobile userspace

Shared Hyprland/Quickshell interaction layer; see
[`docs/mobile-architecture.md`](../../docs/mobile-architecture.md) for boundaries
and the standard Omarchy integration plan.

Current controls:

- Power sleeps through the device adapter when it is ready, otherwise blanks
  the screen; another tap restores a blanked display. Off plays a CRT close
  before the panel blanks; on plays the open after it lights. The OnePlus adapter
  permits suspend only when unplugged with its wake/battery checks satisfied.
  Press/release pairing and a two-second post-resume grace suppress wake events.
- Swipe up from the **bottom-left third** for the app launcher. Settings opens
  as a normal app (Appearance, clipboard, Do Not Disturb). Theme, wallpaper and
  font live there.
- Swipe up from the **bottom-center third** for the combined overview.
- Swipe up from the **bottom-right third** to show the keyboard; tap that
  corner to hide it. The gesture area is 24 logical pixels tall, with a subtle
  center handle. There is no button bar.
- Workspace tiles preview that space's windows. Swipe horizontally through
  its app cards; tap a preview or Open to switch workspace and focus that app.
  Go enters the selected workspace without choosing an app.
- The card's **···** menu reveals move, maximize and close controls.
- Swipe down on a drawer's heading or tap × to dismiss it.
- The status bar has a compact CPU/RAM chip; tap it for the performance panel.
- The shade has Wi-Fi radio, mute and Do Not Disturb toggles. Notifications group by app. New notifications can show a short toast while the shade is closed.
- Kitty touch scrolling is available through the optional, version-matched
  [Wayland backend patch](kitty-touch/README.md). New terminals launched by
  the mobile session opt in; already running terminals need reopening.

Configuration is installed as `~/.config/quickshell/omarchy-mobile/`; the
session starts with `~/.local/bin/omarchy-mobile-session launch`. The default
Quickshell configuration on this phone is only the OnePlus bootstrap wrapper.

`install.sh [device-adapter-directory]` runs **on the target**, installs into
the current user's XDG paths and backs up affected configuration under
`~/.local/state/omarchy-mobile/backups/`. It does not install packages or flash
hardware. On a standard desktop, arrange startup of this shell and avoid
running a second desktop/navigation shell over it.

Dependencies: Hyprland 0.56 Lua, Quickshell 0.3, Qt Quick/Controls, Kitty,
Python 3.11+, util-linux, procps-ng, Fastfetch, and wvkbd. The keyboard was built
from upstream commit `6b41504a0cb58fd1163fa44692398fbd61f8905f`, using:

```bash
make -j4 wvkbd-mobintl
install -Dm755 wvkbd-mobintl ~/.local/bin/wvkbd-mobintl
```

Build dependencies include a C compiler, make, pkgconf, Wayland client/scanner,
xkbcommon, Pango and Cairo development files. This handset's binary is currently
installed at `/usr/local/bin/wvkbd-mobintl`. It uses `--auto --hidden` and the
upstream USR1/USR2/RTMIN visibility signals. Standard input protocols allow
automatic appearance, but the tested Qt client's field blur did not reliably
emit disable; manual hiding remains necessary in some cases.

The navigation bar uses Wayland's top layer; the unmodified keyboard uses
the overlay layer. Hyprland reserves space for navigation first, keeping the
gesture handle at the physical bottom even after a shell restart with the
keyboard visible. Fullscreen application interactions need further testing.

The theme bridge does not execute theme files. Standard palettes bundled from
the host's Omarchy 4.0.0.alpha install are under `themes/`, with upstream license
and provenance in `themes/README.md`. It reads generated Omarchy theme state
when present and delegates selection to the real `omarchy` command when
installed. Full repository theme installation is a future integration step.
The shell now renders standard theme backgrounds, follows Omarchy's current
background when available, and supports `~/.config/omarchy/backgrounds/<theme>/`
user additions. The minimal-Arch fallback saves per-theme choices in its own
`backgrounds.json`. `omarchy-mobile-theme background next` cycles backgrounds.
Wallpaper-only changes leave Kitty and the keyboard unchanged.
See [wallpaper results](../../docs/wallpaper-switching-20260917.md).

Fastfetch uses the official Omarchy PNG in Kitty. `fastfetch --logo Omarchy`
uses Fastfetch's built-in ASCII branding on a text-only connection;
`fastfetch --logo none --pipe` is useful for logs. OS reporting remains honest:
the current system is Arch Linux ARM with this mobile layer.

The portrait layout places a 10-column, 5-row logo on the left, enables terminal
line wrapping and puts the long kernel field below the logo. Compact labels
keep the other fields readable at the phone's current terminal width. This is
standard Fastfetch configuration, not a custom renderer; extremely narrow
windows can still wrap into the logo area.

Shared interaction and standard Linux status readers live here. Hardware-specific
battery, modem, suspend, charging and camera control belongs in the device adapter.
The optional executable `~/.config/omarchy-mobile/suspend` supports `--check`,
sleep without arguments, and `--wake-after SECONDS` for supervised tests. A
nonzero readiness result retains display-only behavior and logs its reason.
The adapter owns hardware checks, resume/input recovery and sleep permissions.
