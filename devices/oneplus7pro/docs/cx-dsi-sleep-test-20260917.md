# Combined CX sleep release and DSI PHY fix

Prepared on the verified #187 boot `3c184f64-6dda-4509-99ec-ef0e77b1ff00`.
This reuses the existing default-off CX control; no new kernel or flash.
The DSI fix alone passed 31.299355 seconds asleep. CX release alone passed
30.707757 seconds on #186. Their combination **passed one measured sleep cycle with user-confirmed touch**.
CX restored to 0, observers unloaded, no trial or RTC alarm remains active.

## Scope and guards

Only CX SLEEP is overridden during one 30-second test. CX ACTIVE/WAKE, MX,
MMCX and MSS retain their startup policy. XO follows normal clock references
with the already-installed DSI PHY fix. CAMCC stays absent; global sync_state
stays incomplete. Never retry the retired MSS release or global CAMCC handoff.

`sleep-residency.py --cx-sleep --seconds 30` explicitly allows #186 and #187;
#187 additionally requires a complete valid clock observer inventory and history
interface. All other build numbers are refused. Existing power/vote/thermal/
modem checks remain. The CX context rechecks prerequisites immediately before
changing the control, and restores it in finally even after ordinary errors.
A kernel hang still requires recovery; this is not a watchdog guarantee.
`--clock-refs` remains a separate observation-only mode, not a second flag to add.
Clock snapshots are automatically recorded when the observer is loaded.

27 helper guard/cleanup tests pass. Added cases cover both allowed builds,
unknown/misplaced versions, explicit single-build restrictions and rejection
of #187 without the observer. Kernel CX control is byte-identical to #186.

## Preflight and evidence

`out/cx-dsi-sleep/preflight.log`: success 1, all PM failures 0; modem running,
test-network connected, Wi-Fi HTTPS 200; battery 84%, 28.4 C, +78 mA while charging.
CX control 0. Protected awake votes CX/MX 7/7, MMCX 6/6, MSS ffffffff/9,
XO 3/3; all 283 observed clocks present. No outstanding RTC alarm.
The three temporary passive modules match the verified hashes:

- clock_refs (#187): `3a009133c81933ae8836654296f01a89f55b62177b9146668e14a46f75816f38`
- rpmh_votes: `044fa6c8c9cdaf0dda154ccebffa802f962a1be5ef5c049c6a2213f4808f719d`
- qcom_stats: `4a92d428e9a00c20b73823ec94aec44d5ec6e29b5a5bdaa4637583d8737f3b97`

Phone helper backup: `/root/suspend-test/sleep-residency.before-cx-dsi.py`.
Planned result `/root/suspend-test/cx-dsi-result.jsonl`, PID file
`/root/suspend-test/cx-dsi.pid`; host evidence `out/cx-dsi-sleep/`.
The one-shot helper waits at most ten minutes for ten continuous unplugged
seconds, then requests a 30-second RTC-backed suspend. No persistent policy
change is installed. Confirm actual process/log state before any follow-up.

## Acceptance and cleanup

Collect completed log, same boot ID, actual sleep duration, complete clock/RPMh
entry and exit samples. Expected CX sleep 0/wake 7 alongside XO 0/0 and balanced
display AHB/XO references; MX/MMCX/MSS unchanged. Require CX restored to 0,
all PM failures still 0, physical touch/display recovery, modem running,
Wi-Fi HTTPS and charging recovery. Inspect new kernel errors and deep-state
counters without assuming improvement. MX/MMCX still hold startup sleep votes;
this short test cannot establish battery life.

Save results, clear/verify RTC, verify pm_async 1, and unload clock_refs,
rpmh_votes and qcom_stats after capture. If the trial expires, nothing was
changed but observers remain loaded until explicitly removed. Retain #187
baseline and #186 rollback; no new flash is needed for this experiment.

## Completed result

The user completed unplug/wake/reconnect and confirmed touchscreen operation.
PID 3090 exited successfully. Linux boottime-minus-monotonic measured
**30.715147176 seconds asleep**; passive clock and RPMh observers independently
measured 30.716395417 and 30.716397656 seconds. All 283 clock records and 68 RPMh
records were complete, valid and identical at recorded entry/exit.

- CX SLEEP/WAKE **0/7**, XO **0/0** together, confirming the intended combination.
- Display AHB/source, bi_tcxo and xo_board prepare/enable all **0/0**.
- MX 7/7, MMCX 6/6, MSS ffffffff/9 unchanged.
- AOSD/CXSD/DDR counts and durations still 0; no deep-state or battery-life gain
  established. Modem count +4, accumulated counter +610367941.
- Same boot ID; suspend success increased 1→2, all failure counters remain 0.
- Modem running; test-network connected and Wi-Fi HTTPS 200. Kernel association was
  about 5.09 seconds after resume; this does not measure application readiness.
- Charging +97 mA net battery current, 84%, 28.4 C; USB input limit 500 mA.
- No new DSI/PLL/RPMh/modem fault in captured test interval. Existing USB resume
  messages and ath10k invalid-frequency scan messages remain.

Cleanup verified CX 0, RTC empty, pm_async 1, global state_synced 0, CAMCC absent;
all three diagnostic modules removed, no trial remains armed. The current #187
kernel retains its verified DSI fix; CX release remains diagnostic and default
off. Do not describe this as a persistent battery optimization.

Host evidence: `out/cx-dsi-sleep/{result.jsonl,summary.json,recovery.log,cleanup.log}`.
Frozen result: `out/checkpoints/20260917-cx-dsi-sleep-verified/`.
Next investigate MX/MMCX dependencies separately while preserving MSS and all
awake/wake requirements. No next experiment or new kernel has been installed.
