# Isolated MMCX SLEEP candidate #188

Status: **#188 passed one 31.543660-second MMCX trial with physical touch**.
Boot `65942a28-ceec-430b-a072-05e594903681`. MMCX sleep/wake was 0/6 at
recorded CPU entry and 2/6 at exit; other protected votes unchanged. Both
controls restored to 0, RTC cleared, observers unloaded, no trial armed.
Prepared after the successful combined CX/XO test. This is a controlled step
toward removing startup sleep clamps, not a completed battery optimization.

## Why MMCX before MX

Local #187 `drivers/pmdomain/qcom/rpmhpd.c` maps SM8150 CX to
`cx_w_mx_parent` and CX_AO to `cx_ao_w_mx_parent`: MX/MX_AO are their parents.
MMCX/MMCX_AO are the independent `mmcx`/`mmcx_ao` pair, with no parent in this
table. Releasing MX with CX still held needs a separate dependency analysis.

The device tree attaches display controller, DSI host, display/video/camera
clock controllers to MMCX. Live domain data shows display users active while
video users are suspended; MMCX awake performance 256. The missing CAMCC driver
still prevents global sync_state. The RPMh aggregation function clamps the
sleep request to the highest corner while unsynced, independently of Linux
domain on/off status. Previous sleep samples show MMCX 6/6, MX 7/7 even when XO
and CX sleep requests drop. Evidence: `out/cx-dsi-sleep/domain-investigation.log`
and the completed combined-test snapshots. Missing camera-driver ownership
means hardware sleep/resume must be validated; do not simply remove all holds.

## Candidate and limits

Isolated tree `.work/linux-sm8150-mmcx-sleep`, build script
`scripts/build_mmcx_sleep_test.sh`, output `out/mmcx-sleep-test/`.
Build #188 retains the #187 DSI PHY fix and unchanged default-off CX control.
New `rpmhpd-mmcx-sleep-test.h` exposes root-only debugfs
`/sys/kernel/debug/guacamole_mmcx_sleep_release`, default 0 each boot, only on
guacamole/SM8150. When enabled, only the normal MMCX sleep contribution follows
its ordinary requested corner; active-only peer sleep is 0. Runtime aggregation
continues following consumer requests. This does not force a voltage or zero
while a driver still requests power.

Setter changes only RPMH_SLEEP_STATE cache, never an ACTIVE/WAKE command.
Restore caches the original maximum sleep corner 6. It rejects invalid input,
contended lock, already-synced domains and missing initialization. Readback uses
READ_ONCE so it does not wait on RPMh. Kernel stalls still require recovery.
CX/MX/MSS and awake/wake aggregation remain unchanged. XO retains normal
clock-framework behavior. No CAMCC, global handoff, regulator override, firmware
partition or unused-clock-policy change is included.

The first MMCX trial deliberately leaves CX control 0. No simultaneous release
of CX and MMCX. `sleep-residency.py --mmcx-sleep --seconds 30` requires #188,
both controls initially 0, complete clock inventory, original protected votes,
running modem, global hold intact and thermal/battery guards. Other trial flags
are rejected. Finally restores MMCX after ordinary errors; no watchdog promise.
The awake released vote must actually fall below 6 or the helper aborts/restores.
Existing CX mode still only permits #186/#187; passive observation also supports
#188 with both controls disabled. Frozen helper and exact #188 clock observer are now installed on phone.

## Host validation and frozen artifacts

- Full arm64 kernel build and boot packing passed. Build timestamp is Sep 17
  23:59; preparation crossed midnight to Sep 18.
- Actual C function harness passed **4,704 aggregation cases**, covering both
  MMCX peers, CX override on/off, synced/unsynced behavior, requested corners,
  other domains and no-peer MSS behavior. ACTIVE/WAKE match #187; default-off
  MMCX matches it entirely. Cache-only setter, failures, restoration and guards
  tested. This is a fake transport, not electrical validation.
- **42 Python helper tests** pass, covering mode/build guards, vote integrity,
  missing observer and restoration on errors. Shell syntax checks passed.
- Boot verifier compares the actual packed kernel with build output and frozen
  #187 rollback; boot header, DTB, ramdisk, embedded initramfs/config/release and
  exported symbol table unchanged. DSI sources and CX header unchanged.
- Exact-version #188 `observer/clock_refs.ko` built; all 40 imports resolve in
  vmlinux exports, private clock/RPMh layouts unchanged. The usual missing full
  Module.symvers warning is covered by KBUILD_EXTRA_SYMBOLS=vmlinux.symvers.

Frozen candidate: `out/checkpoints/20260918-mmcx-sleep-test/`.
Boot SHA256: `1d985fc743a7f66cd58fe678853f3fdad536fea5531deea423b01c7f83b005ad`.
Rollback: `out/checkpoints/20260917-dsi-phy-pm-test/`, verified #187 boot SHA256
`b06df0473a08be94e8877e1bf33d5225fefec0943e23c1f0a684d8d8ff844991`.
`scripts/flash_mmcx_sleep_test.sh test|rollback` validates both manifests, serial
$PHONE_SERIAL and active slot B, writes only boot_b and reboots. No slot A changes.

## Next hardware steps

1. User places phone in fastboot. Flash the frozen candidate and wait for
   automatic boot; do not mask startup issues with USB bootstrap repair.
2. Verify #188/new boot ID, both controls 0, CPUs/display/touch/hidden keyboard,
   running modem, Wi-Fi HTTPS and guarded charging, no new kernel failures.
3. Back up phone helper and #187 clock observer; stage frozen helper and matching
   #188 observer plus existing hash-verified rpmh_votes/qcom_stats. Baseline
   preflight must pass with no RTC alarm or other trial.
4. Arm one 30-second unplugged MMCX trial, then ask user to unplug, leave it
   untouched about 50 seconds, check touch/display and reconnect. It expires
   after ten minutes without unplugging. Capture actual sleep duration, clock
   and RPMh entry/exit, deep counters and complete hardware recovery.
5. Require MMCX sleep reduced (0 if all ordinary consumers sleep), wake 6;
   CX/MX 7/7, MSS ffffffff/9 unchanged; XO expected 0/0 from verified DSI fix.
   Check MMCX restored 0, no PM errors, modem/Wi-Fi/display/touch/charging healthy.
   Save evidence and unload passive modules. Do not infer battery gains from
   a short successful test or software votes alone.

If successful, next analyze MX alongside already-tested CX sleep behavior;
keep MSS held. Never retry the failed MSS release/global CAMCC handoff.

## Installation and preflight

After user fastboot confirmation, both frozen manifests, serial and active B
verified; only boot_b written. Flash and automatic boot logs saved under
`out/mmcx-sleep-test/`. At ~173 seconds uptime: #188/new boot ID, CPUs 0-7,
native 1440x3120@60 scale 3, registered s6sy761 and virtual wvkbd keyboard,
no visible keyboard layer, running modem, test-network Wi-Fi HTTPS 200. Both controls
0, PM successes/failures all 0. No USB bootstrap repair was used.

Charger reports Full at 4.192 V, input limit 500 mA; battery gauge reports 84%,
Not charging, 0 mA, 28.3 C. This is near the conservative 4.20 V ceiling; it is
not a positive-current charging measurement. Preserve the discrepancy for UI/
charge-state follow-up and check charging behavior after the unplugged trial.
No limit or charger policy was changed.

Phone backups: `/root/suspend-test/sleep-residency.before-188.py` and
`clock_refs-187.ko`. Staged helper and #188 observer hashes match frozen files;
existing qcom_stats and rpmh_votes hashes match previously verified binaries.
All three passive modules loaded. Preflight passed with both controls 0,
CX/MX 7/7, MMCX 6/6, MSS ffffffff/9, XO 3/3; all 283 observed reference pairs
match clk_summary. No RTC alarm. The preflight does not enable MMCX.

One-shot command: `sleep-residency.py --mmcx-sleep --seconds 30`.
Phone result `/root/suspend-test/mmcx-result.jsonl`, PID file `mmcx.pid` in
that directory; host arming evidence `out/mmcx-sleep-test/armed.log`.
The next required action is unplug for ~50 seconds, confirm wake/touch and
reconnect. Completed result and its limits are recorded below.

## Completed MMCX result

The user confirmed physical touch after unplug/wake/reconnect. PID 1602 exited
successfully; actual boottime-minus-monotonic sleep **31.543659571 seconds**.
Independent clock and RPMh intervals: 31.544927656 and 31.544929688 seconds.
All 283 clock records valid and identical at entry/exit; display AHB/source,
bi_tcxo and xo_board all prepare/enable 0/0. Both RPMh snapshots contain 68
valid complete records. **One RPMh entry changed between samples:**

| Resource | Entry SLEEP/WAKE | Exit SLEEP/WAKE |
| --- | --- | --- |
| MMCX | 0/6 | 2/6 |
| CX | 7/7 | 7/7 |
| MX | 7/7 | 7/7 |
| MSS | ffffffff/9 | ffffffff/9 |
| XO | 0/0 | 0/0 |

This demonstrates release of the MMCX startup sleep clamp at entry and a
successful wake with the override still enabled, not a constant zero request
throughout the interval. The observer selects the longest individual CPU-PM
interval; its cache snapshots are not system-wide transition barriers or a
hardware voltage trace. An ordinary consumer can update the sleep cache during
resume before that CPU's exit sample. The driver follows normal consumer
requests under the override, so the 0→2 change is compatible with that design,
but these captures do not identify the caller or exact time of the update.
Record this uncertainty; do not claim all RPMh records matched. No extra test
or instrumentation was installed merely to explain this snapshot difference.

AOSD/CXSD/DDR counts and durations still zero. Modem sleep count +6, accumulated
counter +625754220. Same boot; Linux suspend success 1, all failure counters 0.
Modem running, test-network HTTPS 200. First AP association timed out; a second AP
succeeded **10.65534 seconds after resume**. No ath10k resume -110 or MPSS
watchdog occurred, but this is not an instant-connect result. Retain the known
AP selection/reconnect latency follow-up.

After reconnect, charger online, healthy, Full at unchanged 500 mA input limit;
battery 4.192 V, 84%, 28.3 C, 0 mA/Not charging, same as preflight. The charger
logged enable after reconnection. Positive charging current has not been
revalidated at this near-ceiling state; do not label this a fresh charging-current
pass or override the conservative ceiling to obtain one.

Cleanup verified MMCX/CX controls 0, RTC empty, pm_async 1, global state_synced 0,
CAMCC absent, all three observers unloaded. Original awake cache restored.
#188 remains installed with the default-off diagnostic; no persistent sleep
policy change or battery-life improvement claimed.

Evidence: `out/mmcx-sleep-test/{result.jsonl,summary.json,recovery.log,cleanup.log}`.
Frozen result: `out/checkpoints/20260918-mmcx-sleep-verified/`.
Next prepare MX dependency analysis with CX, preserving MSS and awake/wake
requirements; account for per-CPU capture timing when comparing resume votes.
