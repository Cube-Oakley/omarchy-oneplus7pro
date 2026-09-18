# Isolated MSS handoff diagnostic — failed radio resume; do not repeat

## Physical trial result

User confirmed wake/touch and reconnected USB. Linux slept 31.508086 seconds;
passive CPU counter recorded 31.509427 seconds. Both 68-entry snapshots valid,
complete, with MSS active 0 and CX/MX 7, MMCX 6, XO 3 at entry and exit.
Global state_synced remained 0 and CAMCC was absent. Releasing MSS alone
therefore reproduces the radio failure without requiring CX/MX/MMCX release.
It does not establish the precise firmware dependency or a safe lower corner.

MPSS watchdog at kernel monotonic 345.429645 followed suspend entry 344.003554;
Wi-Fi resume failed -110 and failed_resume became 1 (phy0). Suspend helper
recorded the duration/failure and restored display/input; user confirmed touch.
The parent helper's finally attempted MSS restoration, but the upward RPMh
request timed out and its error-recovery request blocked in rpmh_rsc_send_data.
No `mss_restored` or final after-snapshot exists: do not claim restoration.
SSH also stalled, while the outer USB recovery shell remained accessible.

Logs: `out/sleep-stats/mss-{result.jsonl,recovery-outer.log,failure-full.log,
final-stats.log,summary.json}`. The retired `--mss-handoff` CLI now rejects
before accessing hardware. Do not write 1 manually or load CAMCC.

Recovery stopped Arch through the saved outer-RAM script. Normal read-only
remount failed EBUSY because unkillable trial/network processes retained open
files. After sync, SysRq-u emergency remount completed; `/proc/mounts` explicitly
confirmed ext4 read-only before BusyBox reboot. Normal reboot also stalled
(same boot ID and uptime still readable), so SysRq-b emergency reset was
required with the read-only guard rechecked. Evidence:
`mss-{reboot-busy,emergency-remount}.log`. Reboot resets the control to 0;
automatic post-recovery startup is now verified, new boot ID
`be4da80f-2acc-4b4b-bea0-7d4667d62123`. Control 0, state_synced 0, eight CPUs,
desktop, touch/keyboard registration, modem running, test-network HTTPS 200, NTP and
charging all recovered without bootstrap repair. Battery 85%, 29.6 C, 4.20 V,
69 mA into battery at the sample; charger limit still 500 mA. RTC alarm clear,
pm_async=1, PM failure counters zero on the fresh boot. No trial process remains.
Passive modules cleared on reboot. Retired helper is installed and its refusal
verified on-device. Logs: `mss-recovered-{boot,network}.log`. Checkpoint:
`out/checkpoints/20260917-mss-failure-recovered/`.

Next investigation: trace the vendor/mainline modem rail handoff and RPMh
completion difference. Keep the modem's working hold. Do not blindly lower
corners or release other rails on a crashed boot.

Additional vendor source check: `subsys-pil-tz.c:pil_remove_proxy_vote` removes
the modem's proxy regulators; its SM8150 node does not set keep-proxy-regs-on.
`rpmh-regulator.c:rpmh_regulator_handle_arc_enable` masks a disabled ARC request
to level 0 when its table supports OFF. Therefore the DTS retention init value
alone is not evidence Android permanently holds MSS at retention. The current
MSS downward request is asynchronous; the later upward restoration timed out.
Investigate AOP/RPMh completion and actual firmware handoff before assuming a
fixed modem voltage floor would be the correct solution.

## Latest runtime status

User entered fastboot; candidate #185 flashed to boot_b successfully. Automatic
boot verified with no service repair or clock injection, boot ID
`4710a503-8dbc-4380-a3de-0a8e49c57314`. Diagnostic control remains 0 and global
state_synced remains 0; CAMCC is absent. Eight CPUs, desktop, registered touch,
hidden keyboard, running modem, test-network HTTPS 200, charging and NTP all returned.
Battery 85%, 29.6 C; charger input limit remains 500 mA. PM failures are zero.
The passive modules loaded and original CX/MX/MSS/MMCX votes remain unchanged.
Evidence: `out/sleep-stats/mss-default-{boot,votes}.log`.

The optional `sleep-residency.py --seconds 30 --mss-handoff` path now checks
default-off control, unsynchronized controller, absent CAMCC, running modem,
battery temperature below 39 C and the existing RTC/battery/cable guards.
It uses the existing measurement and power-button locks; only releases MSS
after ten seconds continuously unplugged, captures released votes, and restores
0 in a finally block before the after snapshot. Seven focused tests verify
cleanup on successful/failed suspend, failed enable/snapshot, restoration
readback failure, disabled behavior and preflight refusal. Device preflight
passed: `out/sleep-stats/mss-preflight.jsonl`.

This userspace cleanup cannot recover from a kernel hang or forced process kill;
reboot always resets the control to 0. No automatic startup policy changed.
The subsequent physical trial failed as documented above. No repeat is armed.

The passive baseline passed: 30.70665 seconds asleep versus 30.70788 seconds
from the architectural counter (difference 1.23 ms). Both cache samples are
valid, complete (68 entries), and identical. CPU-PM entry has dirty=1 and exit
dirty=0, consistent with the normal RPMh flush during the transition. Modem
remains running, Wi-Fi HTTPS 200 passes, input devices return, and all PM
failure counters remain zero. Charger resumes with the verified 500 mA limit;
the near-ceiling 85% gauge sample shows zero current, not an idle-draw estimate.
SoC deep-state counters remain zero. Files under `out/sleep-stats/`:
`vote-baseline-{result.jsonl,recovery.log,summary.json}`.

| Resource | Cached sleep | Cached wake/active |
| --- | ---: | ---: |
| CX | 7 | 7 |
| MX | 7 | 7 |
| MSS | No cached sleep vote | 9 |
| MMCX | 6 | 6 |
| XO | 3 | 3 |

These are resource corner indices, not measured voltages. MSS has no active-only
peer in the kernel, so its driver sends only an ACTIVE_ONLY request; the generic
cache's `wake` column contains that active request. `ffffffff` means no cached
sleep request, not an off request. Wi-Fi's local supply enable votes were zero
at both sampled boundaries. This still does not identify the failing rail.

## Single-variable test image

`scripts/build_mss_handoff_test.sh` clones the unchanged native5 tree into
`.work/linux-sm8150-mss-handoff` and changes only the built-in RPMh power-domain
driver plus a diagnostic header. It does **not** load CAMCC, globally complete
sync_state, remove any unused-clock/domain/regulator workaround, or choose a
new voltage. Default `mss_test_release=false` preserves the old policy.

Root-only debugfs `/sys/kernel/debug/guacamole_mss_handoff_release`:

- `0` (every boot): normal native5 startup hold for MSS.
- `1`: allow **only MSS** to use its ordinary requested state despite the
  pending global handoff; CX, MX and MMCX remain clamped as before.
- Returning to `0` reapplies the native5 hold through the same locked driver
  path. Invalid values or an already-synchronized MSS are rejected.
- Request errors restore the previous control value and attempt to restore the
  previous vote, logging both results. This cannot resurrect a crashed modem;
  recovery reboot is still required if firmware faults.

The control is exposed only on guacamole with the SM8150 RPMh provider.
No new domain structure layout or exported interface changes. Release remains
`6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty` deliberately so existing
kernel-matched modules and boot helpers work; this diagnostic build is **#185**.
Use the debugfs file/build number and boot image hash to distinguish it from
verified native5 **#184**. This is a diagnostic variant, not a release update.

## Verification and recovery

`scripts/verify_mss_handoff_test.py` passes: boot header, external ramdisk,
packaged/embedded DTB, compressed embedded initramfs, kernel config, module
release and exported symbol table match the saved original. The original
kernel itself matches the frozen rollback image. Diagnostic kernel matches
its build output and contains the control. Compilation has no warnings/errors.
Runtime default-off boot is verified; the targeted trial failed radio recovery.

Frozen candidate: `out/checkpoints/20260917-mss-handoff-test/`.
Boot SHA256: `dbc43acac03a80a223cd69ece9abfc08185d511a536cae5ca2f4cc2ce91ce7e5`.
Recovery image: `out/checkpoints/20260917-native5-test/boot.img` (#184).
`scripts/flash_mss_handoff_test.sh test|rollback` verifies both manifests,
requires serial `$PHONE_SERIAL` in fastboot with active slot B, flashes **boot_b only**,
and reboots. DTBO and slot A stay unchanged.

The original plan was to isolate MSS before CX/MX. MSS-only release reproduced
the failure; investigate firmware power handoff before any further rail release.

The phone now runs #185 with default-off boot verified; #184 is the frozen rollback.
