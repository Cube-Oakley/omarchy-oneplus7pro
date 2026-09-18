# DSI PHY interface-clock PM candidate — 2026-09-17

Status: **#187 passed automatic boot, display off/on and one measured suspend**.
Boot `3c184f64-6dda-4509-99ec-ef0e77b1ff00`. During 31.299355 seconds asleep,
the display AHB/XO chain's prepare references reached 0 and XO sleep/wake requests
became 0/0. Display/touch, modem, Wi-Fi HTTPS and charging recovered with zero PM
failures. Other power-domain holds remained unchanged. AOSD/CXSD/DDR are still 0;
no battery-life improvement is measured. Temporary observers unloaded, no trial
or alarm active; #187 remains installed with CX control 0.

## Evidence and implementation

The passive 30.735529-second suspend captured the display AHB clock's remaining
prepare=1/enable=0 reference and its XO parent chain. Clock samples were valid
at entry and exit. The local `dsi_phy.c` registers `iface` with pm_clk_add;
`clock_ops.c` keeps this gate clock prepared across pm_clk_suspend. The generic
clk_is_enabled_when_prepared check only examines the leaf's enable/disable ops,
so the prepare-driven RPMh ancestor is not considered. The resulting retained
prepare reference explains the XO request remaining 3 despite enable count 0.
See [full observation](clock-sleep-observer-20260917.md).

The matching generic PM-clock use is also present in the
[upstream-derived DSI PHY source](https://android.googlesource.com/kernel/common/+/223ba8ee0a3986718c874b66ed24e7f87f6b8124/drivers/gpu/drm/msm/dsi/phy/dsi_phy.c).
Local runtime observations establish this phone's behavior; no upstream bug
report or claim of testing on other phones has been made.

Candidate patch `devices/oneplus7pro/kernel/power/dsi-phy-pm.patch`:

- Obtain a managed `iface` clock handle before enabling runtime PM.
- Runtime resume uses clk_prepare_enable and propagates any error.
- Runtime suspend uses clk_disable_unprepare, releasing the corresponding
  reference through the normal clock framework.
- Retain existing PHY runtime-PM get/put and PLL sequencing. Replace only the
  generic pm_clk mechanism; no forced clock disable, direct counter adjustment,
  MMIO write, new system-suspend callback or firmware request is introduced.
- Append the private handle to msm_dsi_phy; all affected built-in MSM objects
  are rebuilt (CONFIG_DRM_MSM=y). This is source development in the kernel,
  independent of the shared Omarchy shell.

Normal framework operation may now drop XO sleep/wake/active requests when
no consumer needs it. This is **not** an XO sleep-only override. Display restart
and resume must reacquire the clock successfully; that is a required hardware
validation. Other power-domain startup holds, including MSS, remain intact.

## Build and checks

Build script `scripts/build_dsi_phy_pm_test.sh`, isolated source tree
`.work/linux-sm8150-dsi-phy-pm`, output `out/dsi-phy-pm-test`, version #187.
Derived from #186, retains the existing default-off CX diagnostic unchanged.
No CAMCC enable, global sync_state completion or unused-clock workaround removal.

Full kernel build and boot packing pass. `verify_dsi_phy_pm_test.py` compares
header/DTB/ramdisk, embedded initramfs/DTB, config, release, exported module
symbols and RPMh control sources against #186. Callback contract test runs 500
resume/suspend cycles with a fake CCF transport, checks error propagation and
preservation of other references. These are logic checks, not hardware tests.
All 23 suspend-helper tests pass, including the new #187 observer preflight.

A matching passive clock_refs.ko is prepared under
`out/dsi-phy-pm-test/observer/`. It checks exact kernel release/version at load;
all imports resolve against #187. Existing #186 observer must not be loaded
on #187. qcom_stats/rpmh_votes use unchanged ABI/private RPMh layouts.
For this first clock-fix test the helper accepted #187 only for observation.
After its successful completion, a separately guarded combined CX trial was
prepared; see [combined trial](cx-dsi-sleep-test-20260917.md).

## Install and verify

Frozen candidate `out/checkpoints/20260917-dsi-phy-pm-test/`. Flash helper
`scripts/flash_dsi_phy_pm_test.sh test` checks candidate and #186 rollback
manifests, exact phone serial $PHONE_SERIAL and active slot B, writes boot_b and reboots.
No slot A or firmware partition changes.

1. Wait for automatic boot; confirm #187/new boot ID, eight CPUs, native display,
   touchscreen/hidden keyboard, modem, test-network/HTTPS and guarded charging. Leave
   CX control 0, global startup holds active and CAMCC absent.
2. Inspect kernel logs for clock, DSI/PLL and PM errors. Verify a brief display
   off/on cycle while plugged in, including restored touchscreen/input. A
   successful boot alone is not sufficient for this clock-lifecycle change.
3. Stage the matching observer and updated helper, load the three read-only
   diagnostics, validate awake clock inventory and baseline votes. Record changes
   from #186 rather than assuming identical awake counts.
4. Arm a single `--clock-refs --seconds 30` unplugged RTC-backed capture under
   original power-domain holds. It waits up to ten minutes and takes before/after
   clock, RPMh and residency snapshots. User checks physical wake/touch.
5. Require balanced display AHB references (expected prepare=enable=0 during
   sleep), inspect XO request and all other holds, compare full interval timings,
   zero PM failures, modem/network/display/touch/charging recovery. AOSD/CXSD/DDR
   may still remain zero while other rails are held. No battery claim without
   actual measurements. Save results and remove temporary observers afterward.

Rollback: `bash scripts/flash_dsi_phy_pm_test.sh rollback` restores verified
#186, which has passed both the CX diagnostic and passive baseline sleep.
Original #184 is still available through `flash_cx_sleep_test.sh rollback`.
Both preserve the persistent Arch filesystem; do not change cellular firmware
or retry retired MSS/global CAMCC experiments.

## #187 installation and preflight results

Only boot_b flashed after serial/active-slot and both manifests verified.
Automatic boot evidence: `out/dsi-phy-pm-test/automatic-boot.log`. At 207 seconds
uptime: 1440x3120@60 scale 3, MPSS running, test-network HTTPS 200, PM failures 0;
battery 84%, 28.7 C, +71 mA net current, charger input limit 500 mA. No new
DSI/PLL/clock failure found. Existing bring-up messages and overlay warnings
remain; no bootstrap repair was used.

`test_display_power.py` passed a three-second display-off period and restore;
compositor DPMS false→true and panel DSC reinitialization recorded. Its separate
20-second recovery child completed and exited; no display recovery timer remains.
Input devices remained registered; the user subsequently confirmed physical touch
after the unplugged test below.

All staged module/helper hashes match build outputs. Matching #187 clock_refs,
rpmh_votes and qcom_stats loaded temporarily; preflight passed. All 283 observer
reference pairs match clk_summary. Awake AHB prepare/enable 4/4 and XO 9/9;
protected baseline votes CX/MX 7/7, MSS ffffffff/9, MMCX 6/6, XO 3/3. The sleep
samples below establish reference release; awake counts alone cannot do so.

The one `--clock-refs --seconds 30` process completed. Phone log:
`/root/suspend-test/dsi-pm-result.jsonl`; PID 1583 exited. CX stayed 0 and no
power-domain override was enabled. Evidence under `out/dsi-phy-pm-test/`:
`early-boot.log`, `automatic-boot.log`, `display-cycle.log`, `preflight.jsonl`,
`armed.log`, `result.jsonl`, `summary.json`, `recovery.log` and `cleanup.log`.

## Measured suspend result

The user completed unplug/wake/reconnect and confirmed touch still works.
Linux boottime-minus-monotonic measured **31.299355300 s**. Independent clock
observer interval was **31.300570781 s**, RPMh observer **31.300606563 s**.
All 283 clock and 68 RPMh records were valid, complete and identical between
entry and exit; the approximately 1.2 ms timing difference is consistent with
the observers bracketing slightly different points.

| Captured sleep state | #186 before fix | #187 with fix |
| --- | ---: | ---: |
| Display AHB prepare / enable | 1 / 0 | **0 / 0** |
| Display AHB source prepare / enable | 1 / 0 | **0 / 0** |
| bi_tcxo prepare / enable | 1 / 0 | **0 / 0** |
| XO sleep / wake request | 3 / 3 | **0 / 0** |
| CX sleep / wake request | 7 / 7 | 7 / 7 |
| MX sleep / wake request | 7 / 7 | 7 / 7 |
| MMCX sleep / wake request | 6 / 6 | 6 / 6 |
| MSS cached active request | 9 | 9 |

XO requests returned to 3/3 after display recovery. This supports the diagnosed
prepare-reference mechanism and successful restoration through ordinary runtime
PM. It is software clock/reference evidence, not a measured oscillator waveform
or physical rail voltage. The comparison uses the previous passive #186 test,
not the separate CX-release experiment.

AOSD/CXSD/DDR counts and durations stayed zero. Modem sleep count increased 5,
accumulated counter by 619258158. Kernel suspend success 1, every PM failure
counter 0. Same boot, running MPSS, Wi-Fi HTTPS 200. Association returned about
5.05 seconds after suspend exit; a later AP roam occurred, so do not imply an
uninterrupted connection throughout resume. Charging sample +129 mA at 84%,
28.5 C, unchanged 500 mA input limit; plugged-in current is not idle draw.

No new clock/DSI/PLL/RPMh error in the captured resume log. RTC alarm cleared,
pm_async restored to 1, CX control 0, global state_synced 0 and CAMCC absent.
clock_refs/rpmh_votes/qcom_stats unloaded after saving results. No test remains
armed. Frozen evidence: `out/checkpoints/20260917-dsi-phy-pm-verified/`.

## Next power work

Keep #187 as the current tested baseline and retain #186 rollback. This is one
successful full sleep cycle plus display off/on, not a repeated-cycle reliability
or battery benchmark. The next deeper-state work concerns remaining CX/MX/MMCX
startup sleep holds, preserving MSS. The older CX-only test passed on #186;
the guarded #187 combined trial subsequently passed 30.715147 seconds asleep
with physical touch and full recovery, recorded in the linked follow-up. Keep comparison captures for each change;
do not enable global CAMCC handoff, repeat MSS release, or disable critical GCC
clocks indiscriminately. Repeat longer idle/current measurements only after the
relevant state transition and wake behavior have been verified.
