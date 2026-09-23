# Settings app, shared kit and clipboard store — September 19

Userspace only. Kernel, charging and suspend are unchanged.

## Shared kit

Reusable QML lives in `overlay/mobile/kit/` and is installed to
`$XDG_DATA_HOME/omarchy-mobile/qml/OmarchyMobile`. Settings imports that
module. The shell still loads its own copies of the same widgets so existing
gesture tests and hot reload keep working. Theme data remains Omarchy
`colors.toml` via `omarchy-mobile-theme`.

## Settings

`omarchy-mobile-settings` is a normal Quickshell `FloatingWindow` launched from
a desktop entry. Panels: home, Appearance (theme, wallpaper, font), Clipboard.
Do Not Disturb writes the shared prefs helper. Network, battery and volume stay
in the shade and call the same helpers; they are not duplicated here.

The launcher Appearance button now opens Settings. Font choice is stored in
`prefs.json` and applied to the shell, Settings, Kitty and wvkbd through
`palette.json`. It survives theme changes.

## Clipboard store

`omarchy-mobile-clipboard` owns `$XDG_STATE_HOME/omarchy-mobile/clipboard.json`.
Records are `{id, created, origin, mime, text, pinned}`. Origin is `local` until
a pairing daemon writes a peer id. The shade picker and Settings are clients of
this helper. Copy uses `wl-copy`; paste sets the live clip then sends Ctrl+V.
`wl-paste --watch` ingests new copies while the shell runs. Sync is not
implemented; the store is the surface a later opt-in daemon should use.

## Validation

Host: clipboard/prefs/theme/stats tests and 56 QML tests passed. Phone: installed
2026-09-19, `wl-clipboard` packaged, Settings `FloatingWindow` mapped as
`title: Settings`. Only Quickshell was restarted.

## Recovery

Phone backup: `/root/.local/state/omarchy-mobile/backups/20260919-002622`.
Restore that backup and restart only Quickshell to undo. Do not flash.
