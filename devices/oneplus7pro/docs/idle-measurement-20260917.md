# Supervised idle-drain comparison — 2026-09-17

`devices/oneplus7pro/adapter/measure-idle.py` is staged on the phone at
`/root/suspend-test/measure-idle.py`. The first complete comparison passed; results below.
The first run also validates suspend/resume with the live experimental Wi-Fi
[key-acknowledgement fix](wifi-key-ack-20260917.md).

Default sequence after explicit arming while USB is connected:

1. Wait up to ten minutes for ten continuous seconds unplugged.
2. Blank the screen, wait sixty seconds for battery readings to settle.
3. Measure five minutes awake with the screen blank and Wi-Fi connected.
4. Measure five minutes of s2idle using the RTC fallback, then restore display.

The comparison needs about eleven minutes without interaction. During the
awake phase a Power tap restores the screen and cancels the comparison. During
suspend Power wakes early; that run is marked incomplete. Cable reconnection,
unexpected suspend during baseline, low battery or unsuitable temperature abort
the trial. Cleanup restores display. The suspend phase holds the shared power
event lock and sets the same post-resume grace, preventing wake-release re-sleep.
The underlying board command owns wake-source checks and input recovery.

Battery charge_now is microamp-hours; average drain in mA is
`(start_uAh - end_uAh) * 3.6 / elapsed_seconds`. BOOTTIME minus MONOTONIC measures
actual time suspended. The interval includes entry/resume cost and is not an
instantaneous measurement of current while asleep. A nominal 1 mAh gauge step
is 12 mA over five minutes, so small differences require longer trials. Gauge
charge increases invalidate an estimate; zero charge change means below useful
resolution, not zero consumption. Do not extrapolate phone battery life from
this short pair of trials.

Awake monitoring checks display/USB every two seconds and reads/logs gauge data
every thirty seconds, adding some baseline overhead. Nothing polls during
actual system suspend. Existing background apps and Wi-Fi remain; the result
compares this phone's current session under these two modes.

Six local checks cover conversion, suspend-time accounting, reconnected cable,
charge increases, invalid duration and battery limits. Hardware execution completed. Run log: `/root/suspend-test/idle-comparison.log`. After reconnection,
collect it together with kernel logs, PM counters, power-button/suspend logs,
Wi-Fi HTTPS and charging status. Check `full_interval` before accepting the
suspend result. If the ten-minute arming wait expires, rearm once; no daemon or
automatic idle policy is installed.

## First completed comparison

The user unplugged and later reconnected; continuous observation was unnecessary.
The log records completion of every phase, exit 0, and `full_interval: true`.

| Mode | Measurement interval | Charge used | Average current |
| --- | ---: | ---: | ---: |
| Screen-off awake | 301.53 s | 11 mAh | 131.33 mA |
| Suspend including transitions | 303.08 s | 7 mAh | 83.15 mA |

Actual suspended time was 301.12 seconds. This is a **36.7% lower interval
average**, with roughly 12 mA per gauge step and only one short sample of each
mode. The awake sampler adds overhead; these are preliminary measurements,
not a runtime prediction. Temperature fell from 28.3 to 27.9 C during sleep.

PM success count rose to four; all failure counters remain zero. Touch/power
key reappeared, configerrors stayed empty, the RTC alarm cleared, pm_async
returned to 1, Wi-Fi HTTPS passed and charging resumed at +158 to +183 mA with
stored charge rising after reconnection. There is no measurement process left.
No key-removal timeout appears in the new suspend or subsequent roam. The USB
HS-PHY L2 warning and invalid-frequency scan warnings remain. A first AP denied
authentication, followed by successful association to another and a later roam.

Evidence: `out/wifi-sleep-delay/idle-result.log`, `after-idle-kernel.log` and
`after-idle-charging.log`. After explicit user approval, the tested Wi-Fi modules were also promoted to
the persistent module directory, with originals backed up. The next reboot
still needs verification; see the Wi-Fi document.
