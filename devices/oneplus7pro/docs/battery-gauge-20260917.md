# External battery-gauge bring-up — 2026-09-17

## Current result

The phone's external gauge identifies as TI bq27541, device type `0x0541`,
firmware `0x0200`. The standard Linux `bq27xxx-battery` I²C driver binds as
`bq27541` and exposes `/sys/class/power_supply/bq27541-0`.

**Live measurements verified across USB disconnect/reconnect.** Initial
readings were 74%, 4.057 V, about 26.1°C, and zero current. During unplugged
use, 24 samples showed -171 to -508 mA, changing voltage and temperature,
and decreasing available charge (3138 → 3130 mAh across the recording).
Reconnecting USB restored zero battery current; USB SSH worked without repair.
SOC remained 74% over this short interval, so long-term percentage accuracy
and calibration have not been established.

The user was asked to unplug USB for about 30 seconds, use the phone, then
reconnect to the same port. `/tmp/record_battery.py` is recording locally
every five seconds for ten minutes into `/tmp/battery-unplug-test.jsonl`.
The retrieved samples are in
`out/power-investigation-20260917/battery-reconnect.log` and
`battery-installed.log`. A DWC3 unqueued-request message was logged around
disconnect, but the connection recovered; no reboot or host repair was needed.

## Portable shell indicator

`overlay/mobile/battery.py` reads standard power_supply attributes and excludes
device-scoped batteries, absent batteries and invalid percentages.
`BatteryStatus.qml` adds a theme-colored battery icon and percentage beside
the clock. It polls every 30 seconds, hides unavailable data and shows a
charging marker only when the driver reports Charging. The helper and QML
are included by the mobile installer. Quickshell reloaded successfully on
PID 6030; existing windows were preserved. Backup:
`/root/backups/battery-20260917/omarchy-mobile/`.

The hardware description `guacamole-gauge.dts` instantiates the identified
`ti,bq27541` on I²C8 for the next boot integration. Offline compilation and
overlay application passed. It has not been installed into a boot image;
live hardware setup still needs repeating after reboot.

Charging is now the next hardware priority, ahead of suspend. The initial
zero-current state was traced to the PMIC charge-enable bit being clear.
A separate bounded trial produced positive battery current and the helper
reported Charging. See the charger evidence in the power-investigation folder;
do not confuse that timed test with a persistent charger service.

## Bus and driver experiment

- The vendor 18821 tree places the gauge at 0x55 on I²C8, with the fast-charge
  MCU at 0x26. Only 0x55 was queried; there was no whole-bus scan.
- `guacamole-gauge-bus.dts` enables GPI DMA1, QUP1 and I²C8 at 100 kHz.
  Offline DT inspection confirmed only I²C8 became available under QUP1 and
  no peripherals were instantiated by the overlay.
- `scripts/build_gauge_bus_test.sh` builds against the running native2 tree.
  The module loaded successfully, with no new deferred I²C probe or reported
  I²C error. The bus appeared as `/dev/i2c-1` (discover via its hardware path;
  do not assume that Linux bus number will remain stable).
- `scripts/identify_guacamole_gauge.py` discovers the adapter by hardware
  path and refuses to access an already-instantiated gauge. Its only control
  queries are DEVICE_TYPE and FW_VERSION. It decodes measurements only for
  device type 0x0541, without unsealing, reset, profile or calibration writes.
- After identification, `bq27541 0x55` was written to I²C1 `new_device`.
  Standard power_supply attributes became available. The bq27541 descriptor
  has no data-memory configuration table; this experiment supplies no battery
  profile, and DT NVM updates are disabled in the current kernel.

Initial raw readings: temperature 2992 decikelvin, voltage 4057 mV,
flags 0x0180, remaining capacity 3038 mAh, full capacity 4134 mAh,
current 0 mA, cycle count 0, SOC 74%. The standard driver reports
`charge_now=3138000` µAh because it reads nominal available capacity at 0x0c,
whereas the raw probe read RemainingCapacity at 0x10; these are distinct
gauge registers. Its status is derived from current/full flags, so zero
current produces `Not charging` and does not prove the charger is inactive.

Evidence: `out/power-investigation-20260917/gauge-bus-probe.log`,
`gauge-identity.log`, `gauge-driver.log`; artifacts: `out/gauge-bus-test/`.
No boot image was flashed. The overlay and sysfs-created gauge instance
are temporary for this boot. Keep overlay modules loaded until reboot.

## If the unplug test still reports zero current

Check the gauge's control status and operating mode with the standard driver
unbound/removed so raw queries cannot race its polling. Compare against the
[TI bq27541-V200 datasheet](https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/196/bq27541_5F00_V200_5F00_DS.pdf),
especially CONTROL_STATUS and the sleep/calibration flags. The local vendor
driver queries these flags and also issues IT_ENABLE during initialization;
that command has **not** been issued in this investigation. Do not blindly
copy its configuration writes or reset/unseal the battery gauge.

Once measurements are verified, instantiate the matching gauge in the
device-specific DT and consume standard power_supply attributes from the
portable shell. Keep charger/USB-C control and fast-charge firmware separate.
