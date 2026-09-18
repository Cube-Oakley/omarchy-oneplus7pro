# CX sleep-only diagnostic — 2026-09-17

Status: **one CX sleep-only trial passed recovery; deep residency unchanged**. New boot
`b64adda0-e729-4241-8be2-94b0cf53d04e`, kernel #186, eight CPUs, CX control 0,
MSS diagnostic absent, global state_synced 0, CAMCC absent. Desktop, hidden
keyboard, s6sy761 touch registration, 1440x3120@60 Hz, modem, test-network/HTTPS 200,
USB, systemd-timesyncd and charging started automatically. At 192 seconds uptime,
battery 82%, 28.4 C, +91 mA net current; charger input limit 500 mA. PM failures 0.
The matching passive modules loaded, helper hash matched, and guarded preflight
passed. All five protected resource votes match baseline; AOSD/CXSD/DDR are 0.
Power button is handled on demand by Hyprland bindings, not a resident daemon.

The trial completed: **30.707756550 seconds asleep**, exit 0, full interval,
one successful suspend and zero PM failures. User confirmed touch after return.
CX control is restored to 0; no trial or RTC alarm remains armed. The two
passive modules were unloaded after evidence collection. See the results below.

Preparation baseline was recovered #185, boot
`be4da80f-2acc-4b4b-bea0-7d4667d62123`: nine successful suspends, zero PM
failures, running MPSS, MSS control 0, 81% battery at 28.0 C and charging.

The failed MSS-only experiment showed that releasing the modem startup hold
causes a watchdog even while other domains remain held. This experiment
preserved that hold and changes only CX's SLEEP request. This tests a separate
power dependency; it does not promise deep residency or lower battery draw.

## Image and scope

- Kernel build #186, original native5 UTS release and exported symbols retained.
- Source `.work/linux-sm8150-cx-sleep`, derived from original working #184, not
  the failed MSS diagnostic tree. The MSS diagnostic control is absent.
- Frozen `out/checkpoints/20260917-cx-sleep-test/boot.img`, SHA256:
  `fe33ca01951b080e36476555c7ca1a215018ae95fe1951dc676ad9fe2b6cfcbf`.
- Root-only `/sys/kernel/debug/guacamole_cx_sleep_release`, default **0** on
  every boot. No autoload, startup enable or persistent policy change.
- Value 1 lets CX/CX_AO aggregate their ordinary SLEEP requests despite pending
  global sync_state. Normal CX contributes its requested corner; AO contributes
  zero. ACTIVE and WAKE aggregation is unchanged. MSS, MX, MMCX and XO remain
  under their original policies. CAMCC remains unloaded.
- Both enable and restore update only the RPMh SLEEP cache. They do not issue an
  ACTIVE controller transaction. Setter uses mutex_trylock; getter READ_ONCE.
  The previous MSS restore hung during an ACTIVE request, which this control
  avoids. This does not guarantee recovery from a firmware/kernel failure.
- Existing unused-clock/domain/regulator workarounds remain intact.

Boot header, outer ramdisk/DTB, embedded initramfs/DTB, config, release and module
export table match the original frozen rollback image. The source patch
changes the RPMh diagnostic only, alongside ordinary build metadata;
no claim of runtime equivalence is made before boot verification.

## Local validation

- Full kernel build and boot image packing passed.
- `python3 scripts/verify_cx_sleep_test.py` passed packaging/input comparisons.
- `python3 tests/check_cx_kernel.py` compiles the actual original and patched C
  functions with a fake transport. 2,048 aggregation cases verify unchanged
  default-off behavior, preserved ACTIVE/WAKE requests, normal/AO peer handling,
  synced/unsynced behavior, and unrelated domains. Setter checks cover only-SLEEP
  writes, restore, invalid values, lock contention, sync-state guards and error.
  This is a logic test, not a hardware/firmware simulation.
- `python3 -m unittest discover -s tests -p 'test_*trial.py'`: 17 passed. Covers
  protected cache changes, missing/duplicate/truncated records, failure cleanup,
  duration guard, and continued rejection of the retired MSS CLI.
- Shell syntax checks and both frozen image manifests passed.

## Installation and controlled test

1. Ask user to enter fastboot. `bash scripts/flash_cx_sleep_test.sh test` verifies
   both manifests, exact phone serial `$PHONE_SERIAL` and active slot B, flashes only
   boot_b, and reboots. Slot A and firmware partitions stay untouched.
2. Wait for automatic boot (radio/desktop may take ~165 seconds). Verify a new
   boot ID, #186, control 0, no MSS control, global state_synced 0, CAMCC absent,
   eight CPUs, native desktop/touch, hidden keyboard, charging, modem running,
   test-network and a successful HTTPS request. Do not bootstrap missing services to
   conceal an automatic-start regression.
3. Load the matching passive qcom_stats and rpmh_votes modules and copy the
   current `devices/oneplus7pro/sleep-residency.py` to `/root/suspend-test/`.
   Snapshot the default votes. Confirm resource names/addresses via command DB.
4. Run `sleep-residency.py --check --cx-sleep --seconds 30`. The helper requires
   #186, control 0, absent MSS diagnostic, global startup holds, running modem,
   cool battery, existing power/RTC checks, complete passive cache, and baseline
   CX/MX 7/7, MSS ffffffff/9, MMCX 6/6, XO 3/3.
5. Only after normal boot is verified, arm one logged
   `sleep-residency.py --cx-sleep --seconds 30`. It expires in ten minutes while
   waiting for ten continuous unplugged seconds. User unplugs, leaves it alone
   through RTC wake, checks physical touch, then reconnects.
6. Immediately before suspend, only CX sleep may be below 7; CX wake and all
   four protected resources must retain baseline values. Ordinary unrelated
   regulator votes may vary with device activity. In a finally block the helper
   restores control 0 and checks baseline protected votes again. No polling
   through the actual suspended interval.
7. Capture the passive CPU-PM entry/exit cache, AOSD/CXSD/DDR/modem counters,
   duration, PM failures and kernel log. Check modem, Wi-Fi, USB, touch and
   charging recovery. A successful Linux suspend alone is not a deep-state or
   battery-life result. If residency stays zero, retain the result and choose
   the next dependency from evidence rather than releasing every hold.

The software cache is not a rail-voltage measurement. Entry/exit recording
excludes batch votes and can report a missed sample on lock contention.
Do not read the qcom_stats APSS node: firmware's SMEM item limit is too small.

Rollback: `bash scripts/flash_cx_sleep_test.sh rollback` restores frozen working
native5 #184 (manifest checked). Default-off reboot also restores CX startup
policy. If a trial wedges the system, use the documented outer BusyBox recovery
from `mss-handoff-test-20260917.md`; verify ext4 read-only before forced reset.
Do not repeat MSS release or load CAMCC.

## Completed physical trial

The user unplugged, reconnected and confirmed touch still works. They did not
watch the entire screen transition, so duration is established by recorded
clocks and kernel suspend diagnostics rather than visual timing.

- Boottime-minus-monotonic: **30.707756550 s**. Independent CPU-PM architectural
  counter: **30.708961823 s**, difference **1.205 ms**. All eight CPUs added one
  state1 s2idle usage. Local-clock cpuidle time is not a reliable residency
  duration on this path.
- Entry and exit cache samples valid, untruncated, 68 records each, identical
  values. Dirty changed 1→0, consistent with the RPMh flush processing the cache;
  this is still software evidence, not a hardware voltage trace.

| Resource | Sleep request during trial | Wake/active request |
| --- | ---: | ---: |
| CX | **0** (baseline 7) | 7 |
| MX | 7 | 7 |
| MSS | No sleep request | 9 |
| MMCX | 6 | 6 |
| XO | 3 | 3 |

- AOSD/CXSD/DDR counts and accumulated duration remained **zero**. Modem sleep
  count increased 4 and accumulated ticks increased 610129727.
- Same boot; success 1, every PM failure counter 0. MPSS remains running; no
  modem watchdog or Wi-Fi resume timeout in the trial log. test-network associated
  about 5.02 seconds after kernel suspend exit; subsequent Wi-Fi HTTPS 200.
- Charging recovered at the existing 500 mA input limit; post-test sample
  +161 mA net battery current, 82%, 28.5 C. This plugged-in sample is not an
  idle-consumption measurement.
- Finally restored CX sleep request to 7/control 0. RTC alarm cleared,
  pm_async 1. Trial PID 1578 exited. Passive rpmh_votes/qcom_stats unloaded;
  global state_synced remains 0 and CAMCC absent.

Evidence: `out/sleep-stats/cx-{result.jsonl,summary.json,recovery.log,cleanup.log}`.
Frozen result bundle: `out/checkpoints/20260917-cx-sleep-verified/`.

## Interpretation and next dependency investigation

Unlike MSS release, this isolated CX SLEEP reduction did not break the modem
in the single measured interval. It does not establish repeated-cycle safety,
physical rail collapse or improved battery life; it is not enabled persistently.

MX/MMCX/XO requests remain high at both sleep boundaries. Source confirms CX's
normal domain has MX as parent; MX and MMCX still use the unsynced startup clamp.
XO is different: `drivers/clk/qcom/clk-rpmh.c` derives its sleep request from the
normal `bi_tcxo` clock's prepare state; its active-only peer excludes SLEEP.
It is not the RPMh power-domain sync_state clamp. Do not apply the power-domain
workaround to XO indiscriminately.

The pre-suspend **awake** clock snapshot shows bi_tcxo prepare/enable count 9,
with display, UFS/PHY and modem clock handles in the tree. Handle listings do
not say which consumer currently owns each reference, and awake counts cannot
identify the reference surviving device suspend. Next trace the remaining XO
clock references after device suspend and distinguish live consumers from
bring-up holds, alongside the MX/MMCX domain requests. Keep MSS and awake/wake
settings intact. Any later release needs a separate bounded trial with recorded
entry/exit votes; do not combine all remaining changes or repeat failed CAMCC/MSS
release. No next trial has been armed.
