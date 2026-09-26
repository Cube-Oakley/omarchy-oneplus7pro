# Passive clock reference observer — 2026-09-17

The CX SLEEP-only trial passed recovery but left AOSD/CXSD/DDR counters zero.
XO sleep stayed 3. Source inspection distinguishes XO from the RPMh power-domain
startup clamps: the normal `bi_tcxo` clock requests XO during SLEEP whenever it
is prepared, whereas its active-only peer excludes SLEEP. The next measurement
records which CCF references survive device suspend under unchanged power policy.

## Implementation and limits

- Source `devices/oneplus7pro/kernel/power/clock_refs.c`, build
  `scripts/build_clock_refs.sh`, output `out/clock-refs/clock_refs.ko`.
- Exact native5 #186 version/release and guacamole machine checks. Private
  `clk_core` layout extracted from the running build's `drivers/clk/clk.c`.
- Clock IDs extracted from this build's GCC/display/GPU/RPMh provider tables;
  DSI exports 0 and 1. Pins consumer handles and recursively pins their current
  parents, with no prepare/enable, rate/parent change or RPMh request. Module
  unload releases those handles. No startup hook or boot image change.
- Preallocated CPU-PM snapshots of cached prepare count, enable count and parent
  pointer identity. READ_ONCE scalar reads; parent pointer is compared against
  pinned inventory, never dereferenced in the callback. Metadata names/flags
  copied at module load. No provider callbacks, allocation, MMIO, logging or
  sleeping locks during CPU events. A nonblocking history lock may lose a
  sample; the longest successfully captured interval is retained. CPU cluster
  events are ignored. System PM notifications delimit one suspend attempt.
- Root-readable debugfs `guacamole_clock_refs/current` and `last_suspend`.
  History has validity markers, generation, CPU, architectural counter timing,
  count, indexed parent relationships, names, flags and entry/exit references.
- This records **software reference counts**, not physical clock status or
  per-consumer ownership. Scalar reads are not a coherent whole-tree snapshot.
  A prepared clock can still be hardware-gated. Never infer hardware power or
  battery improvement from these records alone.

## Build and live validation

Build passed against the frozen #186 config/release. External module build warns
that full Module.symvers is absent; KBUILD_EXTRA_SYMBOLS supplies vmlinux.symvers.
All 40 undefined symbols were independently confirmed in that export table; no
clock/power mutation APIs imported. Loaded successfully on the matching phone.

Initial observer load refused a NULL display-clock entry. The shared SM8250
provider table removes three dividers specifically for SM8150 during probe:
DP_LINK1_DIV, DP_LINK_DIV and EDP_LINK_DIV. The build now extracts that explicit
removal list and excludes exactly those three. Failed loads cleaned up all
acquired handles; no PM notifier remained active and CX stayed 0. This was an
observer inventory defect, not a phone driver regression.

Final inventory: **283 clocks**, zero missing requested provider clocks, all
parent IDs resolved. All 283 prepare/enable pairs match kernel clk_summary in
both initial and later awake samples. The kernel report contains 296 clocks;
13 are outside this targeted inventory: UFS PHY symbol sources, qdss, sleep_clk,
two unused DSI divider branches and video-controller clocks. Of those, only
qdss was prepared in the awake validation and it is a separate root. Do not call
this a full-tree trace; check omitted clocks and unknown parents before assigning
responsibility for any residual reference.

The load interval changed 17 UFS/ancestor counts during file activity; a later
sample shows counts falling again (XO 11→8, UFS AXI/unipro 2→1). These asynchronous
awake samples do not establish a suspend blocker or prove a causal relationship
to the observer. They do validate scalar layout/count interpretation; actual
sleep samples are required.

Updated `sleep-residency.py --clock-refs --seconds 30` requires complete observer
inventory, XO sample/history, default CX control 0, absent MSS control, global
startup holds, healthy modem, complete unchanged five-resource vote cache, and
existing battery/USB/RTC checks. It refuses --cx-sleep and any duration other
than 30 seconds. Readiness is checked again after unplugging while holding the
power-button lock. Both clock files are included in before/after JSON snapshots.
The retired MSS mode remains rejected. All 22 helper tests pass.

## Physical capture and interpretation

After preflight, arm one logged invocation while plugged in. Wait up to ten
minutes for ten continuous unplugged seconds; suspend once with the 30-second
RTC wake. Do not press power unless it fails to wake after about a minute.
Confirm touch, reconnect, retrieve the log, then verify normal modem/network,
charging, alarm cleanup and restored power state.

Compare clock history's longest interval with Linux boottime-minus-monotonic and
RPMh recorder duration. Require valid entry/exit and a full interval. Group
prepared clocks by their **captured** parent IDs; identify surviving XO branches
and residual parent references, accounting for omitted clocks. Compare with the
awake inventory to find what actually shut down. Verify original CX/MX/MSS/MMCX/
XO requests remained unchanged. Inspect AOSD/CXSD/DDR and modem counters.
Only then select another bounded dependency test. Do not blindly disable XO,
release all rails, load CAMCC or repeat the failed MSS test.

Module removal after collection: clock_refs, rpmh_votes and qcom_stats. Check
control 0, RTC alarm empty, pm_async 1 and no live trial. The phone's persistent
power policy is unchanged. Current results and arming state are recorded below.

## Completed result

Same boot `b64adda0-e729-4241-8be2-94b0cf53d04e`, native5 #186. The user reports
the test worked. **30.735529154 seconds asleep**, exit 0; clock observer interval
30.736763958 s and RPMh observer 30.736868542 s. Valid, complete entry and exit
clock samples, all 283 records unchanged. Suspend successes 2, all failures 0.
Modem running, test-network/HTTPS 200 and charging recovered (+136 mA sample, 83%,
28.6 C, input limit 500 mA). AOSD/CXSD/DDR still zero.

The only prepared captured XO branch during the long sleep interval was:

`xo_board → bi_tcxo → disp_cc_mdss_ahb_clk_src → disp_cc_mdss_ahb_clk`

Every clock in that chain had prepare=1, enable=0. The parent counts are fully
accounted for by the captured prepared child; the residual leaf reference is
at display AHB. Other observed consumers, including DSI PLL and UFS clocks,
dropped their references. Ten parentless GCC clocks marked CLK_IS_CRITICAL
remained prepare=enable=1; do not indiscriminately disable these.

RPMh entry/exit votes remained CX/MX 7/7, MSS ffffffff/9, MMCX 6/6, XO 3/3.
This associates XO's retained request with a prepared display reference, not
an enabled display pixel clock. It is still software-state evidence.

Source identifies a matching persistent owner: DSI PHY probe adds its `iface`
clock via pm_clk_add. pm_clk_acquire prepares a clock with enable/disable ops
at registration; pm_clk_suspend subsequently only disables it, keeping the
prepare reference until removal. The iface clock is DISP_CC_MDSS_AHB_CLK in
the DT. That prepared child in turn retains the RPMh parent's prepare vote.
The ordinary DSI-host, MDSS and DPU suspend paths already unprepare their clocks.

The proposed fix retains the PHY's runtime-PM lifecycle and balances prepare
as well as enable in its callbacks. See [candidate #187](dsi-phy-pm-test-20260917.md).
Follow-up: #187 is now flashed and passed one measured suspend; display AHB
and XO prepare counts reached zero, XO requests dropped to 0/0, and recovery
passed. See the candidate document for evidence and remaining limitations.

Trial PID 3485 exited. All three observer modules unloaded; RTC alarm empty,
pm_async 1, CX control 0, global state_synced 0, modem running, CAMCC absent.
No capture remains armed. Evidence: `out/clock-refs/{result.jsonl,summary.json,
entry-clocks.json,recovery.log,cleanup.log}`. Frozen result bundle:
`out/checkpoints/20260917-clock-observer-verified/`.
