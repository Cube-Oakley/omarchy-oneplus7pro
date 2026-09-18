# Evening use and status latency

User reported unplugging around 18:00, returning about 21:45, roughly twenty
minutes of screen use and battery 85%→78%. This is an informal observation,
about 1.87 percentage points per hour, not a calibrated battery-life estimate.
The initial unplug/reconnect gauge samples were not captured. Do not extrapolate
full runtime or claim the gauge is calibrated from this result.

Read-only inspection at 21:51 found the same recovered boot
`be4da80f-2acc-4b4b-bea0-7d4667d62123`, eight successful suspend cycles and all
PM failure counters zero. Eight new suspend records total 12,983.523 seconds
(3h36m23.5s). Modem running, test-network connected, MSS diagnostic 0. Battery already
recharging: 79%, 3,302 mAh remaining, 4.145 V, +281 mA, 25.4 C. The gauge's full
charge estimate changed from 4,148 to 4,098 mAh; percentages/estimates should
therefore remain provisional. Raw captures are under `out/evening-status/`.

## Charging and Wi-Fi indicator lag

User observed ~30s Wi-Fi reconnection and 10–20s before the charging icon.
Battery UI previously sampled every 30s; Wi-Fi every 15s. This establishes
potential display latency, not the actual cause of either entire delay.
The board charger worker checks every 2s and emits power_supply_changed when
its guarded charging state changes; gauge status reads sample current/flags.
No charging limits or hardware policy have been changed here.

Added portable `overlay/mobile/StatusProbe.qml`: event-triggered cached reads,
150ms burst debounce, pending refresh during an in-flight sample, original
polling fallback, and monitor restart after 10s if it exits. Battery listens to
kernel power_supply events, Wi-Fi to NetworkManager's `nmcli monitor` without
requesting scans. Line buffering makes piped events prompt. Battery monitor
uses SYSTEMD_IN_CHROOT=0 because systemd's udevadm otherwise ignores this phone's
chroot. No new Python/package dependencies.

Installed QML/type registration with backup
`/root/status-events-before-20260917/`. The same Quickshell process hot-reloaded.
`tests/check_status_probe.py` runs real offscreen Quickshell and verifies burst
coalescing, an event during a running sample and polling after monitor failure.
It passed. Phone component loading/monitor processes are checked separately.
Rollback: restore the backed-up BatteryStatus.qml, WifiStatus.qml and qmldir;
unused StatusProbe.qml may remain. No Hyprland settings changed.

## Physical timing capture — completed

User reports Wi-Fi appearing practically instant on wake, and charging shown
within a few seconds of plugging in, comparable to Android on this device.
The ninth suspend cycle slept 23.175006s, all PM failure counters remain zero,
modem running, control 0, post-test test-network HTTPS 200. Charger limit remains
500mA; battery sample 79%, 4.148V, +127mA, 27.4C. The temporary recorder and
its three child monitors were stopped after collection; only the two shell
status monitors remain. No new trial is armed.

Trace: `out/evening-status/reconnect-result.jsonl`; recovery:
`out/evening-status/reconnect-health.log`. Observations (CLOCK_BOOTTIME):

- Resume observed at 15435.200s; first Wi-Fi association at 15440.272s
  (~5.07s later). Kernel timestamps independently give ~5.08s. Do not describe
  radio reconnection as measured instantaneous just because the icon looked so.
- Charger enabled at 15443.027s; first sampled positive battery current +215mA
  at 15445.059s (~2.03s later). Gauge change event follows at 15446.161s.
  Input online was sampled after enable; physical plug time is not known
  precisely. Sampling resolution is about one second, not subsecond accuracy.
- NetworkManager later reported no primary connection at 15455.720s, then
  test-network primary returned at 15477.050s while the radio switched back to the
  earlier AP. A successful association is not proof of end-to-end connectivity.
  Initial icon state may remain connected during driver-level reassociation.

The UI improvement is physically confirmed. Follow up on NetworkManager's
resume/link-state reporting and AP roaming with timestamped association,
address/route and connectivity evidence; do not claim continuous internet or
change roaming/suspend policy based solely on this trace.

NetworkManager's existing log file is empty. The chroot suspend helper does not
currently notify NetworkManager through logind. Missed resume notification or
scan retry delays are hypotheses, not a confirmed diagnosis. Do not change
reconnect policy before observing its actual state transitions.

`devices/oneplus7pro/observe-reconnect.py` listens to kernel power_supply events,
NetworkManager state messages and selected new kernel messages. It samples
charger online/status and battery status/current once a second, logging changes
with wall, monotonic and boot clocks. It normally expires ten minutes after starting
(including any sleep), terminates its child monitors, and never changes power,
networking, wake alarms or charging. On-phone log:
`/root/suspend-test/evening-reconnect.jsonl`. Use a normal unplug, power-button
sleep/wake and reconnect, then correlate charging/connection events with the
user's observation. This is not another rail-release experiment.

USB-C docking is added to the roadmap: verify native DisplayPort and external
monitor support separately from host keyboard/mouse/Ethernet and charging.
Exact Lenovo dock model and compatibility remain unverified.
