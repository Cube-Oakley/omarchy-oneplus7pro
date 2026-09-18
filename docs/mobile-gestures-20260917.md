# Gesture shell and Kitty touch — 2026-09-17

Userspace follow-up to [the first mobile checkpoint](mobile-work-20260917.md).
No kernel, boot image or firmware changes.

## Interaction

The 90-pixel button dock is replaced by a transparent 24-pixel gesture surface
with a small center handle. The start position determines the action:

| Bottom third | Swipe up | Tap |
| --- | --- | --- |
| Left | App launcher | No action |
| Center | Windows + workspaces | No action |
| Right | Show keyboard | Hide keyboard |

Gestures require at least 54 logical pixels upward, with upward displacement
more than 1.4 times horizontal displacement. One contact is accepted. This
keeps ordinary app interactions outside the edge under the app's control.
The edge retains the top-layer reservation so the overlay keyboard sits above
it. Fullscreen app interaction and landscape layout still need testing.

The overview has compact workspace tiles showing app counts, a horizontally
swipeable preview deck for each workspace, and a Go action. Tapping a preview
or Open switches to that workspace and focuses the exact window. The card's
ellipsis reveals move-to-workspace, maximize and close. The launcher now uses
app icons when available. Colors remain derived from standard Omarchy palettes.

## Focus bug fixed

Quickshell 0.3 exposes bare hexadecimal window addresses; `hyprctl clients`
includes `0x`. The previous validator rejected Quickshell's addresses and then
dismissed the overview. All card actions now normalize either representation.
Focus uses sequential workspace/window dispatches and dismisses only after
the dispatcher reports success. `out/gestures-test/focus-fixed.log` captures
an actual shell IPC invocation through the same focus function used by cards,
with the resulting exact active window and workspace verified through Hyprland.
Earlier direct-dispatch tests did not exercise this address conversion.

## Kitty

A version-matched, opt-in `wl_touch` listener was added to Kitty 0.48.2's Wayland
backend. The user confirmed scrolling works great. See
[build, limitations and rollback](../overlay/mobile/kitty-touch/README.md).
No global input grabbing, evdev injection, or compositor plugin was needed.
The first shell test had a QML parse error, fixed before physical testing.

## Evidence and recovery

- `out/gestures-test/gesture-live.log`: physical left, center, right and hide
  events; navigation at y=1016 with height 24.
- `out/gestures-test/overview-new.png`: actual scanout of the new overview.
- `out/gestures-test/kitty-build-touch.log`: native backend build.
- `out/gestures-test/focus-fixed.log`: cross-workspace app selection.

Phone configs and original Kitty backend are backed up under
`/root/backups/pre-gestures-20260917/`. Shared source before this change is
`out/gestures-test/mobile-before/`; the previous frozen checkpoint remains
`out/checkpoints/20260917-mobile/`. Reverting the shell does not require flashing.
