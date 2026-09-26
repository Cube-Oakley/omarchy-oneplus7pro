# Compact status indicators

The portable mobile shell now has a vertical battery with fill level, an inset
charging bolt and percentage alongside. The bolt has a contrasting outline
so it remains visible with both low and high fill levels. Wi-Fi has cached
signal arcs and a slash when disconnected; it hides when NetworkManager or a
Wi-Fi device is unavailable. Wi-Fi connection does not imply Internet access.

`overlay/mobile/wifi.py` reads NetworkManager without requesting scans or
credentials. The shell samples every 15 seconds (battery remains 30 seconds).
These userspace timers freeze in system suspend. The evening follow-up added
shared StatusProbe event refreshes while retaining these fallback intervals;
see [event-driven update and timing investigation](evening-observations-20260917.md).

The new helper, QML and type registration are installed on the phone. The
shell hot-reloaded successfully; live helper returned connected with signal
64. Python/shell syntax checks passed, and an isolated rendered preview covered
charging at 84% and 10%, ordinary discharge and Wi-Fi. Final shell runtime
verification is recorded under `out/status-indicators/`.

Backups: `/root/status-indicators-before/{BatteryStatus.qml,shell.qml,qmldir}`.
Restore those three files to `/root/.config/quickshell/omarchy-mobile/` to
revert the visible change; the unused Wi-Fi helper/component can remain.
No Hyprland config or kernel changes are involved. Percentage visibility and
the optional top-edge battery bar remain planned settings; see the roadmap.
