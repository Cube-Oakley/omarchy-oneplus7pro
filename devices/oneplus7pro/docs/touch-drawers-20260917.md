# Touch drawers and overview — 2026-09-17

Installed on the running native2 #179 desktop without a firmware flash. The
existing user Kitty window was preserved. Physical feel still needs the user's
confirmation; automated input tests and live compositor checks passed.

## Interactions

- Pull up from the bottom left for Applications, or the bottom center for
  Overview. The sheet follows the drag. Release past 40% to open, or use an
  upward fling (at least 40 logical pixels and 700 px/s). A short slow pull
  returns closed. A velocity sample older than 100 ms is not a fling.
- Pull down on a drawer's heading to close it. A new drag can interrupt a
  settling animation. The close button remains available.
- Bottom-right swipe still shows the keyboard; bottom-right tap hides it.
- In Overview, tap an unselected workspace to inspect it. Tap the selected
  workspace to enter it, including when empty. The Go button is removed.
  Tapping a window still enters its workspace and focuses that exact app.
- Browse previews sideways. Swipe a preview up to close that app: at least
  24% of the card height (capped at 180 logical pixels), or an upward fling
  of at least 54 pixels and 900 px/s. Short pulls return the preview.
- Hold a preview for 450 ms to arrange it. Drop on a numbered workspace to
  move it, another app in that workspace to swap tile positions, or the bottom
  close target to request a normal close. Dragging outside the targets cancels.
  The target highlights before release. The app target list scrolls when a
  held finger reaches its upper/lower edge.
- Close sends Hyprland's normal client close request. It does not force-kill.
  A surviving preview returns after 400 ms so an app that prompts about
  unsaved work remains accessible. Existing menu buttons remain available.

The drawer surface owns input while visible, including the shaded area above
a partly open sheet; new taps cannot pass through to underlying apps. Drawer
content becomes interactive only once the opening motion settles. A drag that
begins on the narrow navigation surface relies on Wayland retaining its touch
grab as the separate drawer surface appears; this cross-surface behavior is
part of the outstanding physical check.

## Implementation and validation

Shared sources are in `overlay/mobile/`: `DrawerMotion.qml`,
`PreviewGestures.qml`, `EdgeGestures.qml`, `WindowCard.qml`,
`WorkspaceOverview.qml`, and `shell.qml`. No OnePlus-specific input path,
coordinates, kernel changes, or global application gesture interception were
added. Application long-press and scrolling outside the overview are untouched.

`bash tests/run_touch_qml.sh` runs isolated Qt Quick tests with synthetic touch
and mouse input, without accessing the host compositor or theme helpers.
19 checks passed (including test setup/cleanup). Cases cover direct tracking,
fling/expired velocity, interruption/reversal, cancellation, all three edge
zones, tap-to-hide, preview taps, short/upward swipes, hold/release, and horizontal
browsing after a hold. The latter caught and fixed retained MouseArea grab
state: the mode now resets after release/click delivery and before a new touch.

Live tests on Hyprland 0.56.2 created two disposable terminals in otherwise
empty workspaces, verified their tile positions swapped, moved one to another
workspace, and normally closed both. Existing user window addresses remained.
The swap API was checked against the exact installed commit
`efb50993780079460b0cbed1363e2166a2de1d9f` before testing it.
A native screenshot verified the themed overview, preview and workspace row.
The shell loaded without QML runtime errors; Hyprland config errors were empty.
Qt reports its vsync animation driver at 16.67 ms. This is not a measurement
of physical gesture latency or a claim that every animation frame is delivered.
The panel remains 60 Hz.

Static QML analysis has the existing Quickshell metadata limitations:
PanelWindow creatability, Process exit enum/collector type information, and
unqualified delegate references. Live loading was used to check those paths.
No full phone reboot was performed for this userspace-only update.

## Recovery and next checks

Phone backup before installation:
`/root/backups/drawers-20260917/quickshell/`.
Host evidence: `out/drawer-test/`.
Checkpoint: `out/checkpoints/20260917-touch-drawers/`.
To roll back, stop only the Quickshell process whose argument is
`/root/.config/quickshell/omarchy-mobile/shell.qml`, restore that directory from
`/root/backups/drawers-20260917/quickshell/omarchy-mobile/`, and run
`omarchy-mobile-session launch` with `XDG_RUNTIME_DIR=/run/user/0` and
`WAYLAND_DISPLAY=wayland-1`. Keep Hyprland and user applications running.

Physical checks pending: slow pulls and flings in both directions, opening
while the keyboard is visible, horizontal browsing followed by hold/drop,
workspace tap-to-enter, accidental-close resistance, and apps with unsaved
work. Touch resizing, direct-on-window manipulation, richer tiling placement,
and application context-menu/right-click gestures remain future work.

## Follow-up: opening flash, held previews, and keyboard re-entry

The user confirmed workspace tap-to-enter and moving windows work. They reported
an old-looking sheet flashing before the finger-tracked opening and wanted the
held window to stay large and become translucent instead of turning into a
small label.

The drawer now keeps its transparent Wayland surface mapped. Its input region
is empty when closed and covers the drawer when open; the sheet itself is
hidden at rest. This removes the remapping/previous-buffer path suspected in
the opening flash. Eight open/dismiss operations across Applications and
Overview kept exactly the same compositor surface. Physical confirmation that
the flash is gone is still pending. The mask behavior follows
[Quickshell's input-region API](https://quickshell.org/docs/v0.2.1/types/Quickshell/QsWindow/#prop.mask).

`HeldPreview.qml` mirrors the existing rendered card at 94% scale around the
original touch point. Opacity goes from 86% at pickup to 42% after 180 logical
pixels of movement. The workspace row stays in its original position and
highlights the target through the preview. The source retains its touch grab;
no app is moved until release. A hold without at least 18 pixels of movement
cannot accidentally drop onto a newly revealed target. Native GPU captures
verified pickup and workspace-hover states, including the full window image.
22 Qt test results pass (including setup/cleanup), with a new touch test
covering the source grab and the finger anchor while moving beyond the card.

During this session the user also found a keyboard stuck beneath a second
keyboard. Inspection found one wvkbd process, and its remaining surface ignored
manual hide. Restarting that process cleared the orphaned state. Code review
found a nested-show hazard: `show()` calls sizing roundtrips before assigning
its global layer pointer. Those roundtrips can dispatch input-method callbacks
and enter `show()` again, creating two layers and overwriting the first pointer.
[Wayland documents this event dispatch during roundtrip](https://wayland.freedesktop.org/docs/html/apb.html).

The exact timing of the user's incident was not recorded, so this is a
reproduced matching failure path, not a captured stack trace of their incident.
`show-reentry.patch`, applied after `focus-grace.patch`, guards construction.
The fault-injection test compiles the actual `show()` function with protocol
stubs and calls it again during sizing: the old code fails the one-surface
assertion; guarded code passes and can subsequently reopen. On the phone,
20 show/focus/hide cycles passed with exactly one visible keyboard or none,
and the corresponding bottom reservation was 304 or 24. Eight further focus
transitions preserved the same surface without destruction. Logging was
returned to normal and the keyboard left hidden. User windows remain open.

The installed wvkbd binary SHA256 is now:
`96326263279e1bf2451ea8d4ce840a946df140d3348ec04f5cfe8b00c9dce5c8`.
Build source: `/root/src/wvkbd-show-guard/`.
Keyboard rollback: `/root/backups/keyboard-reentry-20260917/wvkbd-mobintl`.
Shell rollback: `/root/backups/drawer-refinement-20260917/omarchy-mobile/`.
Evidence: `out/drawer-refinement-test/`.
Checkpoint: `out/checkpoints/20260917-drawer-refinement/`.
No firmware flash or phone reboot was required. Temporary rendering diagnostics
were removed; only the normal shell and one keyboard process remain.

## Follow-up: swipe down from drawer content

The user accepted the prior flash/held-preview/keyboard refinements, then
requested Android-like downward dismissal from anywhere in the open drawer.

`DrawerPull.qml` now observes the initial touch direction before claiming it.
A downward pull beginning while the app/theme list is at its top drags the
whole sheet closed. A pull beginning below the top remains a scroll for that
entire touch, even if it reaches the top; a subsequent pull can dismiss it.
The heading remains available for dismissal regardless of scroll position.
Overview accepts downward dismissal from previews, workspace tiles, buttons
and empty space. Upward preview closing, horizontal browsing and long-press
arrangement retain ownership. Taps continue to launch/select normally.

Downward dismissal settles closed after 160 logical pixels (or 20% of the
panel height on shorter screens), or a downward fling with at least 40 pixels
and 700 px/s. Smaller slow pulls return open. A quick upward reversal returns
open. The opening-edge threshold is unchanged. Tracking uses scene coordinates
so the moving sheet does not feed its own translation back into the gesture.
A disabled/hidden handler cancels, and cancellation suppresses a queued release.
The drawer keeps the persistent transparent/input-masked surface introduced by
the previous refinement.

38 Qt test results pass, including setup/cleanup. New cases exercise pulls over
real Flickable, ListView, TapHandler and preview MouseArea components; they cover
scrolling below/at the top, reaching the top mid-scroll, header use while
scrolled, downward preview dismissal, upward close, horizontal browsing, holding
then moving down, content disabled during a sheet drag, and cancellation.
Motion tests cover short pulls, lower-screen slow pulls, flings and reversals.
The two new/changed motion components pass qmllint without diagnostics. Full
shell analysis retains the known Quickshell metadata limitations documented
above. The installed shell loads cleanly and preserves the existing windows.
The user confirmed the broader dismissal gesture works great after deployment.

Phone backup: `/root/backups/drawer-pull-20260917/omarchy-mobile/`.
Evidence: `out/drawer-pull-test/`.
Checkpoint: `out/checkpoints/20260917-drawer-pull/`.
Only shared QML changed; no keyboard binary, compositor config, device adapter,
firmware or package changes were needed for this follow-up.
