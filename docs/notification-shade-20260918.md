# Notification shade and JetBrainsMono — September 18

User pivoted from suspend diagnostics to a themed pull-down control/notification
area. Kernel #188 and all power controls remain unchanged. Work is portable in
`overlay/mobile/`; no board-specific sysfs names are added to the UI.

## Implemented and installed

- Drag down from the status bar to reveal the shade. Uses the existing
  finger-following DrawerMotion, then settles on release. Swipe up anywhere on the
  shade, tap the chevron, or tap outside to close. An overflowing notification
  list scrolls until its bottom, then a new upward gesture closes the shade.
- Battery, Wi-Fi, clock/calendar and optional weather tiles use MobileTheme
  colors. Floating detail panels sit above a dimmed shade. Tapping the existing
  status icons/time also opens the matching details.
- Battery: gauge percentage, stored/full/design mAh, signed net mA, voltage,
  temperature, separate charger status and USB input limit. Missing readings
  show an em dash; input limit is not presented as measured charging current.
  Near 4.20 V, charger Full and gauge 84% can disagree; show both truthfully.
- Wi-Fi: SSID/signal, IPv4/IPv6 addresses, gateway, DNS, nearby networks, explicit
  rescan, disconnect and connect form. NetworkManager handles profiles and
  authentication. Personal/open networks supported; enterprise/WEP require an
  advanced profile. Hidden-network entry and enterprise setup are future work.
- Calendar: month grid with today's highlight, previous/next and Today. This is
  a calendar view, not yet calendar-account/events integration.
- Weather: opt-in manual city/postcode search and location selection, current
  conditions, feels-like/wind and three-day highs/lows in Fahrenheit. Cache for
  15 minutes and retain stale data offline. No automatic location lookup. No
  location selected yet; user can choose in the panel. No background weather
  polling while the shade is closed. Requests happen when opened/selected.
- Freedesktop notifications received by Quickshell; plain-text cards, actions,
  individual dismissal and Clear all. Session-only list capped at 100. No
  reboot-persistent history, lock-screen notifications or toast banners yet.
- Shared MobileStatus probes prevent duplicate status-bar/shade monitors.
  Existing event debounce with 30-second fallback; five-second refresh while
  shade is open. Nearby scans occur on opening Wi-Fi or explicit Refresh.
- `ttf-jetbrains-mono-nerd` installed from the phone's configured Arch repo.
  JetBrainsMono Nerd Font applied to all shell text and Kitty. Font picker
  recorded in roadmap. Keyboard font is also installed and verified in its
  process arguments; installer includes a reusable Kitty mobile-font.conf.

Network credentials travel through JSON on child stdin, then nmcli --ask stdin;
never shell interpolation, command-line arguments or logs. Network names render
as plain text. Weather provider: [Open-Meteo forecast API](https://open-meteo.com/en/docs)
and [geocoding API](https://open-meteo.com/en/docs/geocoding-api), attributed in
panel. Notifications use the installed Quickshell 0.3.1 API, consistent with
[NotificationServer documentation](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Notifications/NotificationServer/).

## Session infrastructure

The chroot desktop had only a system D-Bus, no user session bus. Created a
standard user bus at `/run/user/0/bus`. `start-mobile.sh launch` now creates it
only if there is no inherited session address and no standard socket, and
exports DBUS_SESSION_BUS_ADDRESS for Quickshell and launched apps. Existing
normal desktop session buses are reused. Startup persistence is installed but
not yet reboot-tested; no reboot is needed for touch testing now.

Adding qmldir singleton files during hot reload left the old shell partly
reloaded and unresponsive to normal exit. Recovered only that Quickshell process
with a bounded SIGTERM then SIGKILL fallback, preserving its environment; the
compositor and applications were not restarted. New shell loaded cleanly with
D-Bus notifications working. Subsequent single-file hot reload worked.

## Validation and remaining work

- Five Python backend tests pass: signed units/missing fields/charger mismatch,
  escaped SSIDs and IPv6, AP deduplication, password stdin/no shell, invalid
  requests rejected, opt-in weather/cache/offline behavior.
- 41 Qt touch/motion tests pass, including three added upward-pull cases for
  close-at-bottom, scroll-with-more-notifications and ignoring downward pulls.
  Cross-surface physical gesture feel remains for the user to confirm.
- QML syntax checked with `/usr/lib/qt6/bin/qmllint`; known Quickshell metadata
  and unqualified-access warnings remain. Final running shell loaded cleanly.
- Actual test-network status/IP/DNS and nearby scan displayed correctly. Local D-Bus
  Notify delivered a visible notification card. Calendar month grid captured.
  Theme Osaka Jade and requested font confirmed visually and by fc-match.
- The connection backend successfully activated saved test-network and passed HTTPS
  200 afterward. Disconnect and new-password entry have not yet been exercised
  end-to-end through the UI. Weather has not yet been configured/live-fetched for the user.
- USB temporarily became unreachable during capture; the user reported internet
  working on the phone and replugged. USB recovered on the same boot. Cause not
  established; no claim that the shade or Wi-Fi caused it.
- Applied user feedback: navigation now uses exclusiveZone 0 / Ignore and an
  Overlay layer, rather than reserving 24 pixels. It remaps above wvkbd on the
  compositor's openlayer event so bottom-right hide remains accessible. With
  keyboard hidden, app/workspace drawer and shade extend from y=36 to y=1040;
  with keyboard visible, wvkbd extends y=760..1040. No wallpaper band reserved.
- Shade independently ignores keyboard exclusive-zone changes, with explicit
  top inset from statusBar.height. During rapid battery/calendar/Wi-Fi menu
  changes and keyboard show/hide, its layer stayed **0,36 480x1004** throughout.
  Only the floating input popup accounts for keyboard height. Focus ownership
  is cleared on close; unrelated late network replies no longer hide keyboards.
  This addresses the user's report of the lower edge jumping during menu use.
- Added directionSign to the existing DrawerPull component, keeping downward
  drawer behavior unchanged by default. The shade uses -1 and notification-list
  bottom eligibility. Detail menus block shade close gestures until dismissed.
- Final runtime log clean; screenshot confirms battery metrics and theme/font.
  UI and keyboard left closed for physical follow-up. No power changes.


Evidence: `out/notification-shade/`. Some initial batch screenshots reflect later panel
state; use the subsequently completed `battery-final.png` for battery evidence.
`wifi.png` and calendar images demonstrate those layouts. Stable layer geometry
is recorded in `stable-geometry.log`; backend reconnection in `wifi-connect-check.log`.
Phone source staging: `/root/shade-stage/`.

## Backup and recovery

Phone backup: `/root/.local/state/omarchy-mobile/backups/notification-shade-20260918/`.
Contains old `shell/`, battery/Wi-Fi helper, Kitty config and session launcher.
To revert, restore those specific files and restart only the mobile Quickshell
using its existing Wayland environment. New helper/font package may remain
unused. Do not reset Hyprland, flash kernels or change charging policy to undo UI.
No suspend trial or observer modules remain armed/loaded.
