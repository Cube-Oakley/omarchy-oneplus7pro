# Deeper suspend diagnostics — native5

Latest: [DSI PHY PM fix #187](dsi-phy-pm-test-20260917.md) releases the
remaining display AHB prepare reference and XO request during measured sleep.
31.299355 seconds, zero PM failures, touch/network/charging recovered. Deeper
SoC counters still zero; power-domain holds remain. No experiment armed.

Latest result: [CX sleep-only trial](cx-sleep-test-20260917.md) passed recovery
after 30.707757 seconds, but AOSD/CXSD/DDR remain zero. MSS hold preserved;
control restored and temporary modules unloaded. No test armed.

The previous single five-minute comparison averaged 131 mA with the display
off and userspace awake, versus 83 mA across the suspend interval. Suspend
returned successfully, but this does not prove system-wide rail/DDR collapse.

## Live diagnostic added

`scripts/build_sleep_stats.sh` builds the **unmodified** kernel
`drivers/soc/qcom/qcom_stats.c` against native5's `vmlinux.symvers`.
The resulting `out/sleep-stats/qcom_stats.ko` matches the running release and
loaded successfully from `/root/suspend-test/qcom_stats.ko`. It binds the
existing `c3f0000.sram` device (`qcom,rpmh-stats`). No DT, boot image, power
policy or firmware setting was changed. The module is temporary until reboot.

Initial readings, after four completed suspend cycles this boot:

- `aosd`, `cxsd`, `ddr`: count, last entry/exit and accumulated duration all 0.
- Modem SMEM sleep count and duration are nonzero and advancing.
- Other subsystem files are empty (unavailable data, not proof of no sleep).
- PSCI reports OSI support; CPU/cluster idle counters advance, with substantial
  rejected entries as well. Per-CPU s2idle usage is four. Do not translate
  Linux's local-clock s2idle time into hardware residency: timekeeping freezes
  across this path. Use firmware counters and boottime/monotonic deltas.
- `clk_ignore_unused`, `pd_ignore_unused`, `regulator_ignore_unused` remain;
  awake USB/display and unused UFS-card domains appear on in the snapshot.
  Awake/plugged-in snapshots alone do not identify a suspend blocker.
- The AOSS debugfs `prevent_*` files are **write-only controls**, not readable
  state. Read attempts returned EINVAL; no commands were written to them.

The zero firmware counters suggest deeper SoC modes are not being reached,
but do not yet isolate the cause or establish that this firmware exposes all
records accurately. First collect before/after counters around a bounded
unplugged suspend. Then investigate RPMh/cluster votes and individual unused
clock/domain dependencies. Do not remove all bring-up workarounds together.

## Next physical test

`devices/oneplus7pro/sleep-residency.py`, installed under `/root/suspend-test/`,
passed `--check`. It waits up to ten minutes for ten continuous seconds
unplugged, takes a snapshot, invokes the already verified `guacamole-suspend`
with a 90-second RTC wake, then records counters and actual suspended time.
The shared trial and power-button locks prevent competing test/button actions.
The existing helper guards charging, battery, RTC and wake sources and restores
input/display after wake. Power still provides an early wake, which is labeled
as an incomplete interval. Nothing becomes a persistent idle policy.

Evidence: `out/sleep-stats/{initial.log,capabilities.log,preflight.jsonl}`;
earlier full clock/domain snapshot: `out/wifi-sleep-delay/deep-suspend-baseline.log`.
The initial physical result is now complete (below). No reduced-current claim yet.

The initial one-shot test was armed with confirmation in
`out/sleep-stats/armed.log`. On-phone log/PID:
`/root/suspend-test/sleep-residency.{log,pid}`. It expires after ten minutes if
the user does not unplug. Inspect that log before rearming or doing other
power work; do not assume it remains active across turns.

## Initial residency test completed

User unplugged, let the RTC wake the phone, confirmed touch works and replugged.
`out/sleep-stats/result.jsonl`: **91.610 seconds asleep**, exit 0, full interval.
Suspend success count is five, all failure counters zero; RTC alarm cleared,
pm_async restored to 1. Same boot ID. Wi-Fi HTTPS returned 200, touch and
keyboard registered, USB recovered and charging resumed (+99 mA at 85%,
29.1 C). Recovery evidence: `out/sleep-stats/recovery.log`.

SoC aosd/cxsd/ddr counters remained all zero; modem sleep accumulated normally.
This confirms the earlier observation across a controlled sleep interval.
The APSS diagnostic read triggered a `qcom_smem_get` bounds warning: this
firmware has 620 SMEM items, while that generic file requests item 631.
`sleep-residency.py` now reads only the three supported SoC counters and the
known-good modem record. This was a diagnostic warning, not a PM failure.

## Confirmed handoff blocker and temporary driver trial

Added a read-only native5 diagnostic (`kernel/power/rpmh_votes.c`, built by
`scripts/build_rpmh_votes.sh`). It copies the RPMh software cache under its
existing lock; no registers, firmware requests or power callbacks. Private
cache layouts are extracted from the exact kernel source at build time.
It is loaded temporarily and exposes `/sys/kernel/debug/guacamole_rpmh_votes/cache`.
Snapshots are not a trace of actual hardware rail states during sleep.

Findings before the trial:

- Power-controller `state_synced=0`.
- The only unsatisfied direct consumer is `ad00000.clock-controller`, CAMCC.
  Its node is enabled, but `CONFIG_SM_CAMCC_8150` is not set.
- `rpmhpd_aggregate_corner()` clamps **both sleep and active votes to the
  maximum** until `rpmhpd_sync_state()` runs.
- Cache showed CX/MX sleep+wake 7, MMCX 6, and MSS active 9.
  Resource mappings come from the phone's own `cmd-db`.

Built and temporarily loaded unmodified `camcc-sm8150.ko` with
`scripts/build_camcc_sleep_test.sh`. It bound successfully; power-controller
state_synced changed to 1, CX/MX sleep+wake became 0, MSS active became 0,
and MMCX now follows active consumers (5 with display on, 2 during brief DPMS
blank). All six camera GDSCs report off and CAMCC runtime-suspended.
Display off/on, input registration, Wi-Fi HTTPS and USB checks passed.
Charger guard remains online with the same limits; the near-ceiling gauge
sample returned zero current, not a new estimate of idle draw.

Evidence: `rpmh-cache-awake.log`, `sync-state.log`, `sync-consumers.log`,
`before-camcc.log`, `after-camcc.log`, `camcc-health.log` and
`camcc-screen-off.log` under `out/sleep-stats/`.

**No persistent module or boot change yet.** Reboot returns to the previous
native5 configuration. Unloading CAMCC alone does not restore old handoff votes
because sync_state has already completed. Do not use it as an A/B reset.
The next trial is another 90-second unplugged suspend with CAMCC loaded;
use `/root/suspend-test/camcc-residency.log` and `.pid`. If successful, measure
drain over longer intervals before promoting this driver persistently.
Remaining suspects include XO sleep vote 3, MMCX's retained vote, and GCC
sync_state still waiting for the component-bound GMU. Do not force global
sync_state or drop all unused-clock/domain workarounds together.

## CAMCC suspend trial failed radio resume — do not promote

The user completed the second unplug/wake/reconnect trial. The phone spent
91.173 seconds asleep, but **this was not a passing test**: `failed_resume`
increased to 1 for `phy1`; the Wi-Fi resume callback returned -110 after about
30 seconds. MPSS reported a watchdog (`SFR Init: wdog or kernel error suspected`)
and remoteproc entered `crashed`, with recovery deliberately disabled. The
sleep helper correctly returned exit 1. The screen/touch, USB and guarded
charging recovered (+100 mA on reconnect), but Wi-Fi did not. The three SoC
deep-state counters remained zero. No battery improvement is established.

Evidence: `camcc-result.jsonl`, `camcc-recovery.log`, `camcc-failure.log`,
and `pre-recovery.log` under `out/sleep-stats/`. This exposes an unresolved
radio power dependency when the handoff clamps are released; it does not yet
identify which rail/clock or transition ordering caused the watchdog. The
upstream MPSS driver drops CX/MSS proxy votes after firmware handover. Compare
that contract and AOSS load-state handling with the vendor firmware before
trying to persist CAMCC or replacing the clamp with an arbitrary voltage.

Recovery selected: reboot the unchanged native5 image to reset firmware and
all temporary handoff state. Do not hot-restart the crashed modem/RMTFS into
a loop. No permanent CAMCC load hook was installed and no image was flashed.
The initial clean reboot preparation stopped Arch processes, then refused
to remount ext4 read-only because `/lib/firmware` retained a writable bind
mount. Unmounting that unused bind allowed the remount; the outer BusyBox
reboot was then issued with `/dev/sda19` confirmed read-only. Recipe now
includes the bind unmount: `scripts/phone-recovery-reboot.sh`.
Recovery boot is verified: boot ID `927a5e82-e6ae-4efc-9123-80844ecf186b`.
Native5 #184, all eight CPUs, native 60 Hz desktop, touch and hidden keyboard,
guarded charging (+93 mA sample), running MPSS, test-network autoconnection and Wi-Fi
HTTPS 200 returned without host bootstrap or service repair. NTP synchronized.
CAMCC, RPMh-vote and sleep-stats test modules were cleared by reboot; power
controller state_synced is back to 0. The persistent key-ack module hashes
match the approved pair and startup manifest checks passed. Shell loaded
without errors and its Wi-Fi helper reports connected. Evidence:
`recovered-boot.log`, `recovered-network.log`, `recovery-reboot.log`.
No further suspend test is armed. No new battery-life claim or CAMCC promotion.

Next investigation: capture the modem's required active/sleep/wake votes and
AOSS handoff around suspend, with instrumentation that preserves the original
policy. Identify the missing dependency before another power-changing trial.
Retain the failed-run evidence; do not treat Linux's incremented `success`
counter alone as success when `failed_resume` is nonzero.
