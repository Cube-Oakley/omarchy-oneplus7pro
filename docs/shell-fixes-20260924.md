# Shell fixes — September 24, 2026

## The shell died after an Avahi app

Opening "Avahi VNC Server Browser" (`bvnc`) from the app drawer left the
phone apparently dead: the display off and no shell. The phone itself was
fine (up 5.9 h on #194, reachable over USB): Hyprland ran, the shell
(Quickshell) did not. Its log ended at `MOBILE_LAUNCH bvnc` and, 3 s later,
`MOBILE_HOME slot=2`, with no crash report and nothing in the kernel log.

`bvnc` found no Avahi daemon, opened its window and a small dialog, and both
closed within 3 s. Hyprland's log then shows `ToplevelExport: Couldn't
capture (window doesn't exist)`, followed by every shell surface being torn
down. In Hyprland 0.56.2 (and upstream `main` as of today),
`CToplevelExportClient::captureToplevel` logs that and returns without
creating the frame object the client named, and without sending `failed`;
the client's next request on that frame is a fatal protocol error, and
Hyprland disconnects it. So a window that closes while the shell is capturing
its preview for the switcher can take the shell down. The shell already
stopped capturing a card the user dismisses; a window that closes by itself
cannot be ruled out from the client side. The real fix is in Hyprland (create
the frame and send `failed`); a report upstream is held for now.

**Watchdog.** `overlay/mobile/shell-watchdog.sh`, installed as
`omarchy-mobile-shell-watchdog`, starts the shell again if it exits. The
session's prepare step (which the shell runs every time it starts) launches
it; a lock keeps one per session. It checks every 3 s and relaunches after
two misses in a row (a deliberate restart takes under a second; `quickshell
-n` refuses a second copy anyway), and leaves the screen as it was. A shell
that dies leaves its helpers running (`nmcli monitor`, `dbus-monitor`,
`udevadm monitor`, `pactl subscribe`, `wl-paste --watch`, the controls,
rotation and brightness helpers and their `monitor-sensor`), and the new one
starts its own, so it stops those first: by name, in the dead shell's session
(the shell leads one), leaving the board start scripts the session also
started alone. Nothing it starts inherits its lock: the first version's shell,
launched from the watchdog, held the lock for life, and a replacement
watchdog found it taken and quietly exited.

Killing the shell outright (SIGKILL) three times: with the final version it
was back in 5 s, its ten helpers stopped, one set running afterwards, and
only the watchdog holding the lock.

## Closing the last app

Swiping the last app away in the switcher left an empty switcher; a tap or a
swipe was needed to reach the desktop. `WorkspaceOverview.qml` now dismisses
itself (to the desktop, as Android does) when a close leaves no cards.
User-checked.

## Brightness drag

With kernel #194 keeping panel commands out of frame transfers
([kernel #194](kernel194-20260924.md)), the shade's slider sends about one
level per frame (16 ms) instead of one per 80 ms, and follows the finger.
User-checked: no flicker.
