# Passive modem power baseline

Following the failed CAMCC trial, the recovered native5 boot remains
`927a5e82-e6ae-4efc-9123-80844ecf186b`. CAMCC is absent and the power-controller
handoff clamp remains in place (`state_synced=0`). Modem, Wi-Fi HTTPS, charging
and desktop are healthy. Do not reload CAMCC as part of this baseline.

## Source comparison

The current kernel's `qcom_q6v5_prepare()` sends the AOSS message
`{class: image, res: load_state, name: modem, val: on}`. Vendor
`drivers/soc/qcom/peripheral-loader.c:pil_notify_aop()` uses the same message
format before loading modem firmware. The live MPSS node has `qcom,qmp`.
The current driver's handover callback drops its temporary CX/MSS domain and
XO-clock votes after firmware handover, matching the vendor proxy-unvote design.

Vendor `sm8150-regulator.dtsi` maps `pm8150_s1_level` to `mss.lvl`; the current
RPMh power-domain driver uses the same resource. Vendor initialization mentions
retention and all request sets, but that alone does not establish the final
firmware/driver votes during suspend. There is no demonstrated message-name
or rail-name mismatch. Do not convert the vendor init setting into an arbitrary
permanent voltage floor without measuring the actual transition.

## Recorder

Extended `devices/oneplus7pro/kernel/power/rpmh_votes.c`:

- Existing `cache` file still shows the current cached single and batch votes.
- New read-only `last_suspend` shows the single-vote cache on CPU-PM entry and
  exit for the longest observed CPU interval during one system suspend attempt.
- PM notifiers delimit the attempt. Per-CPU buffers are preallocated. CPU
  callbacks perform no allocation, logging, MMIO writes or RPMh requests and
  always return `NOTIFY_OK`. A busy cache marks the sample unavailable rather
  than waiting for its lock. RCU synchronization protects callback removal.
- Times use the ARM architectural counter, whose reported frequency here is
  19.2 MHz. Compare ticks/frequency with the userspace suspended-time result.
- This is a **software cache snapshot**, not a rail-voltage measurement or
  firmware execution trace. CPU entry precedes the PSCI domain transition;
  exit follows it. Concurrent changes may require more precise instrumentation.
  Batch votes are excluded from the interval capture and explicitly labeled.

Built with `scripts/build_rpmh_votes.sh` against the unchanged running kernel.
The recorder and stock `qcom_stats` diagnostic are loaded temporarily; neither
is enabled at boot. Initial load, clean unload/reload and `--check` passed.
No new kernel warning appeared; modem running and Wi-Fi HTTPS 200 remain good.
Files: `out/sleep-stats/{handoff-start.log,modem-handoff-baseline.log,
recorder-loaded.log,recorder-preflight.log}`.

## Next physical trial

Use the existing guarded `sleep-residency.py` with **30 seconds**, enough to
isolate a long CPU interval without attempting a new battery measurement.
It waits for ten continuous seconds unplugged, uses RTC recovery, then restores
input/display and captures `last_suspend` alongside the cache and SoC counters.
It expires after ten minutes waiting; no permanent idle policy is installed.
Log/PID: `/root/suspend-test/vote-baseline.{log,pid}`.

After collection, require successful PM callbacks, modem and Wi-Fi recovery,
valid/non-truncated entry and exit samples, and architectural-counter duration
consistent with actual sleep. Interpret missing/no-long-interval samples as
an instrumentation limitation, never as zero hardware power consumption.
Only then choose a targeted dependency test. If cache observations cannot
resolve the order, instrument RPMh flush and modem handoff in an isolated
kernel build while retaining the known-working power policy.

## Result and next step

The physical baseline passed: 30.70665 seconds asleep, valid 68-entry captures
and 30.70788 seconds measured by the ARM counter, modem/Wi-Fi/USB/input/charger
recovery with zero PM failures. No entry/exit vote values changed; the cache
dirty flag cleared during the interval. See [MSS-only diagnostic](mss-handoff-test-20260917.md)
for the prepared next image and recovery path. No test remains armed.
