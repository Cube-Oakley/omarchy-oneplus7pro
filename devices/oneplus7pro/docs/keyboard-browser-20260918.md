# Keyboard focus, dismissal, Chromium and Grok — September 18

## Installed keyboard fixes

Wi-Fi/weather menus previously enabled layer keyboard focus merely by opening.
Their TextFields could then gain active focus and request wvkbd. They now use
TouchTextField: read-only and non-focusing until explicitly tapped. Only an
editing field requests layer keyboard focus; closing/canceling clears editing
before releasing it. No global change to keyboard auto-show behavior.

A 144 × 24 logical-pixel grab handle appears immediately above wvkbd. Pull down
at least 44 pixels and release to hide it. The handle does not reserve space.
Gesture starts in the keyboard or outside the handle are ignored. The old
bottom-right tap-to-hide action is removed and navigation's input mask excludes
that corner while wvkbd is present, preserving Enter taps. Bottom left/center
drawer swipes remain available. Layer geometry is queried at startup and on
wvkbd open/close events, without continuous polling.

Validation: 52 QML checks passed, including text entry after tapping, no editing
from visibility/focus changes, swipe dismissal and rejection of key-area/app
scrolls, short and sideways swipes. Six live Wi-Fi/weather/battery/calendar
open/dismiss cycles showed no keyboard layer. Live handle rectangle is
(168,736,144,24), immediately above keyboard (0,760,480,280).
Physical gesture feel and popup typing still need the user's confirmation.
Evidence: `out/notification-shade/keyboard-focus-{tests,live}.log`.
Backup: `/root/.local/state/omarchy-mobile/backups/keyboard-browser-20260918/shell`.

## Chromium diagnosis and installed browser setup

Chromium 153.0.8010.36-1 refuses the root desktop session. Created an unprivileged
`mobile-browser` account (UID 1001, nologin shell). First headless test aborted
because /dev/shm was mode 0755; changed it to standard 1777. Retest with packaged
sandbox and no disabling flags rendered about:blank and exited successfully.
Unprivileged user namespaces fail inside this chroot, but the packaged setuid
sandbox works for the headless run. No systemd coredumps/journal available.

Automatic approval review initially rejected the display ACL. The user then
explicitly approved this temporary arrangement and requested a future standard
user session with sudo. The staged installer and browser adapter are now
installed and verified; this action is no longer blocked. The account receives
traverse-only access to /run/user/0 and read/write to its Wayland display socket.
The adapter reapplies the ACL on launch because session setup chmod can mask it.

Prepared source:
- `devices/oneplus7pro/adapter/browser-launch.sh`: root-session adapter grants the above
  narrowly scoped ACLs, sets up a private runtime directory, repairs shm mode,
  drops to mobile-browser and launches Chromium with its sandbox enabled.
  It does not grant the root session bus or Hyprland IPC socket access.
- `overlay/mobile/browser.sh`: portable normal-user Chromium launch; delegates
  root bring-up to the adapter.
- `overlay/mobile/launch-webapp.sh`: compatible `omarchy-launch-webapp URL` entry
  point using Chromium --app mode.
- `overlay/mobile/webapps/Grok.desktop`: https://grok.com, with Grok's own icon
  downloaded from https://grok.com/images/android-chrome-192x192.png.
- `scripts/install-phone-browser.sh`: backed-up user-local installation, stock
  Chromium desktop override, terminal wrapper, Grok launcher and icon.

Installed from /root/shade-stage with scripts/install-phone-browser.sh.
Both standard Chromium and Grok launcher entries validate. Chromium opened as
UID 1001 on native Wayland; Grok loaded in its own app-mode window, class
chrome-grok.com__-Default, title Grok. Screenshot confirms the rendered Grok
sign-in page. A subsequent fresh launch after all browser windows closed also
succeeded. The renderer processes have Seccomp=2, NoNewPrivs=1 and separate PID
and network namespaces. GPU process opens /dev/dri/renderD128. GPU and some
utility processes report Seccomp=0; do not claim every process has identical
sandboxing. No sandbox-disabling option was added.

Evidence: out/notification-shade/browser-sandbox-live.log and browser-grok.png.
Audio logs report the expected missing default ALSA device; audio hardware is
still a separate roadmap task. User was actively trying browser input during
verification; no new automated typing or login was performed.

Browser profile belongs to mobile-browser in /home/mobile-browser; file picker
and downloads use that account's home. It has a separate session bus, so root
shell notification integration remains future work. Root-session browser
launchers are in /root/.local/bin and user-local desktop entries override the
packaged Chromium launcher without changing package files. No flash or reboot
was needed; reboot persistence has not been tested. Adapter creates its runtime
directory and restores display access and shared-memory permissions on launch.

The roadmap now records migration of the entire compositor/shell/app session to
a standard user with sudo, ownership/profile migration, user D-Bus and narrowly
scoped hardware services; retire this temporary account/ACL setup after that.

## App launcher PATH correction

User reported both drawer entries did nothing despite direct launch success.
Confirmed Quickshell inherited PATH=/bin:/sbin:/usr/bin:/usr/sbin, so bare Exec
commands omarchy-mobile-browser and omarchy-launch-webapp could not resolve.
The earlier SSH tests explicitly added ~/.local/bin and missed this difference.

start-mobile.sh now exports ~/.local/bin and /usr/local/bin before starting the
shell. Restarted only Quickshell through the corrected normal session entrypoint;
its inherited PATH now includes both. A local minimal-boot-environment check also
confirmed user-installed executable resolution. The default bootstrap already
calls this same entrypoint, so the fix applies to subsequent boots.

Added mobile.launchApp(desktopId) IPC to invoke exactly root.launch(app), the same
function the drawer uses. Invoked chromium and Grok through this handler; both
returned true and compositor output confirmed native Wayland Chromium and Grok
windows. Chromium's first window needed more than the initial two-second check;
both were present in the subsequent check. Evidence is in
out/notification-shade/launcher-{chromium,grok}-check.log. Backup:
/root/.local/state/omarchy-mobile/backups/launcher-path-20260918/.
