# Power bring-up — 2026-09-17

## Verified starting state

Native2 #179 remains installed on slot B. No boot image was changed during
this investigation. Initial boot ID: `e38aa15d-a549-42a7-b98a-b4d9df657096`.
Evidence is in `out/power-investigation-20260917/`.

- The embedded boot DT disables `/soc@0/spmi@c440000` and
  `/soc@0/cpufreq@18323000`. The required SPMI, PM8941 power-key,
  QCOM PON and hardware CPU-frequency drivers are built in.
- Initially there were no SPMI devices, battery/charger power supplies,
  CPU frequency policies, or physical power-button input device.
- All eight CPUs are online. PSCI idle is registered with the `menu`
  governor. This does not establish useful deep-idle residency.
- `/sys/power/state` offers `freeze mem`, but `mem_sleep` offers only
  `[s2idle]`. No suspend attempt has been made.
- 24 TSENS thermal zones report plausible readings around 34–37°C.
- Initial wakeup sources were only the generic `autosleep` and `deleted`
  entries. The PMIC thermal/ADC devices were not active.
- `clk_ignore_unused`, `pd_ignore_unused` and `regulator_ignore_unused`
  remain active; the prepared kernel also defaults these to true in source.
  Audit and retire them separately, not as a single experiment.

The historical minimal-bring-up notes list SPMI and CPU frequency as
deliberately disabled along with many unrelated subsystems. No specific
SPMI failure was found in the project notes reviewed for this test.

## Temporary power-key test installed

Sources: `devices/oneplus7pro/kernel/power/guacamole-powerkey.dts` and
`powerkey_overlay.c`. Build: `bash scripts/build_powerkey_test.sh`.
Artifacts: `out/powerkey-test/`, including hashes and an offline merged DT.

The overlay enables the SPMI bus and PM8150 PON/power-key path only. Other
PM8150 peripheral children and PM8150b/PM8150l slave nodes are explicitly
disabled before the bus becomes available. The empty PM8150 secondary USID
is retained. Charger, Type-C, gauge, GPIO and ADC drivers are not brought up.
The loader rejects a different machine or an already-enabled SPMI bus.

The module was built against the exact running kernel release and loaded
from `/tmp/powerkey_overlay.ko`. Offline checks confirmed only PON was
available among PM8150 peripheral children. The build uses the prepared
kernel's `vmlinux.symvers` via `KBUILD_EXTRA_SYMBOLS`; the generic missing
`Module.symvers` warning was emitted, but modpost and live module loading
succeeded.

Observed result:

- SPMI arbiter v5 (`0x50000000`) probes.
- `pm8941_pwrkey` registers as `/dev/input/event1`, advertising KEY_POWER.
- The kernel marks its wakeup capability `enabled`.
- Hyprland detects the new physical keyboard, with the existing virtual
  keyboard and s6sy761 touchscreen still present.
- USB SSH remains connected, all eight CPUs remain online, and DSI-1 remains
  enabled at 1440×3120, 60 Hz, scale 3.

**Physical press/release verification passed.** The user pressed twice and
the passive recorder captured two KEY_POWER down/up pairs. First press:
`1789671121.313744`–`1789671121.541075`; second:
`1789671122.622041`–`1789671122.782086`. No extra key events occurred.
The passive recorder is running for
30 minutes, writing `/tmp/powerkey-events.log`:

```sh
python3 -u /tmp/read_input_events.py /dev/input/event1 --seconds 1800
```

The source is `scripts/read_input_events.py`. It does not grab the device or
inject input. Expected events are type 1, code 116, values 1 then 0 for each
press/release. Copy the log into the evidence directory when observed.
The original unbound-input capture is saved in
`out/power-investigation-20260917/button-confirmed-config.log`.

### Display off/on test

`scripts/test_display_power.py` passed one live display off/on cycle:
DPMS true → false for three seconds → true; DSI-1 retained its native 60 Hz
mode, Hyprland PID 625 survived and USB stayed connected. The kernel logged
a fresh panel DSC initialization, without a new panel error. A separate
process retried display-on after 20 seconds. Evidence:
`out/power-investigation-20260917/display-power-first.log`.

The installed Hyprland 0.56.2 uses Lua dispatchers:
`hyprctl eval 'hl.dispatch(hl.dsp.dpms({ action = "enable" }))'`.
The legacy `hyprctl dispatch dpms on` syntax fails on this build.
Reference: [Hyprland dispatchers](https://wiki.hypr.land/configuring/core/dispatchers/)
and [binding flags](https://wiki.hypr.land/configuring/core/binds/flags/).

The first physical test used a temporary live binding loaded from
`/tmp/powerkey_display_test.lua` (source: `scripts/powerkey_display_test.lua`).
XF86PowerOff release executes a delayed display toggle outside the compositor
event loop. Each invocation also arms a 20-second display-on retry. Existing
key-press/mouse-move automatic DPMS wake options are false. There was no
previous power-button binding. The new binding is present and configerrors
is empty. No persistent Hyprland config was changed; normal config reload
or restart removes this binding. If reapplying live, first unbind the previous
test binding to avoid duplicates.

**The user confirmed the physical display test:** first press turns the screen
black, second press three seconds later restores it, and touch works.
Recorder events occurred at `1789671357.783659`/`.948114` and
`1789671360.792376`/`.956220`. Both dispatched toggles returned `ok`.

The temporary binding has since been replaced with the saved shared mobile
binding in `overlay/mobile/hypr-mobile.lua`. The new
`overlay/mobile/display-power.sh` helper is installed as
`~/.local/bin/omarchy-mobile-display`, with `on`, `off` and `toggle` actions.
The installer includes it. Release binding and 150 ms delay are retained;
the test's automatic 20-second wake is removed. The normal config explicitly
unbinds the previous XF86PowerOff action before setting its replacement.
Hyprland reload/configerrors passed; exactly one power binding is present,
and the installed helper's `on` request passed. Phone rollback files are in
`/root/backups/powerkey-20260917/`.

The userspace binding is persistent, but the kernel overlay still requires
manual loading after reboot. Do not claim full boot persistence yet. Keep
native2 unchanged until the next planned boot integration and validation.

Screen blanking does not establish system suspend, a
secure lock screen or measured idle-power savings. No automatic suspend or
shutdown action has been installed.

The overlay is intentionally permanent for this boot: do not rmmod it or
remove a live overlay. A normal reboot restores the unchanged native2 DT;
the power-key experiment is not configured to autoload. No fastboot is needed
for this temporary test.

## Shutdown hypothesis, not a verified fix

The local `drivers/input/misc/pm8941-pwrkey.c` does more than report a key.
For the selected `qcom,pm8941-pwrkey` data, it registers a reboot notifier.
On `SYS_POWER_OFF`/`SYS_HALT`, the notifier selects the PMIC shutdown type
in PON PS_HOLD reset control; on reboot it selects a reset type.

Previously that driver was absent because its parent bus was disabled.
Its missing notifier is a plausible explanation for the observed reboot on
power-off. Now it probes successfully, but **shutdown has not been retried**.
The `qcom-pon` driver handles reboot-mode metadata, not this shutdown-type
selection. The boot DT has no `qcom,pshold` node; inspect the active PSCI
power-off path as well rather than assuming `CONFIG_POWER_RESET_MSM`
establishes a bound PS_HOLD device.

Before a shutdown test, prepare a coordinated outer-initramfs shutdown
that preserves user work, syncs storage and verifies a read-only remount.
Observe that the phone stays off; USB loss alone is insufficient. Compare
USB-connected versus disconnected behavior if needed. Keep the earlier
[failed attempt](shutdown-20260917.md) as the baseline.

## Battery wiring found in the vendor source

Update: [the gauge bus and standard driver now work](battery-gauge-20260917.md).
Identity is bq27541 / firmware 0x0200. Live discharge readings and USB reconnect
are verified, and the shell battery indicator is installed. A bounded charger
trial also verified positive current; [persistent charging](charging-20260917.md)
is now the next priority ahead of suspend. The trial restored disabled charging.

Local vendor source: `.work/lineage-kernel/src/arch/arm64/boot/dts/18821/`.

- `sm8150-oem.dtsi` sets `oem,use_external_fg` on PM8150b FG.
- `sm8150-mtp.dtsi` places an `oplus,bq27541-battery` device at address
  `0x55` on `qupv3_se8_i2c` (`0xa80000`). A separate fast-charge MCU is at
  `0x26` on that bus.
- Downstream pinctrl uses GPIO88/89, function `qup8`, 2 mA, bias disabled.
  These match mainline `i2c8`/`qup_i2c8_default` in the prepared tree.
- `guacamole.dtsi` selects the OP 4000 mAh battery profile.

The downstream bq27541 driver supports several gauge variants and queries
DEVICE_TYPE at runtime. Thus the DT name alone does **not** prove the exact
chip fitted to this handset. Do not bind an arbitrary variant based only on
that name. It also performs configuration writes unsuitable for a first
readout-only experiment.

Next battery experiment: enable only the QUP1/I²C8 dependencies, check the
GENI firmware mode and DMA availability, then identify address 0x55 with
the documented device-type query and read its matching measurement registers.
Do not scan the whole bus or touch the fast-charge MCU. The existing kernel
has I2C_CHARDEV and BQ27XXX_I2C built in, with BQ27XXX DT NVM updates disabled.
After identifying the chip, prefer the matching standard power_supply driver
and validate percentage, voltage, current sign and temperature before showing
them in the shell. Charging control remains a separate test.

## Next sequence

1. Physical KEY_POWER presses/releases are verified.
2. Automated and user-observed button/display off/on passed, including touch
   recovery. Prepare suspend/resume testing with a known wake source and a
   suitable recovery path. Native2 lacks CONFIG_PM_DEBUG, so staged pm_test
   testing needs a kernel update; no PMIC RTC is active for timed wake yet.
3. Bring up the external gauge and obtain trustworthy battery telemetry.
4. Test real shutdown with coordinated storage handling and user observation.
5. Test CPU frequency scaling separately, then idle/runtime power management;
   measure behavior rather than inferring battery life from enabled drivers.
6. Persist only verified changes in a new recoverable boot checkpoint, then
   continue Wi-Fi and the remaining hardware queue.
