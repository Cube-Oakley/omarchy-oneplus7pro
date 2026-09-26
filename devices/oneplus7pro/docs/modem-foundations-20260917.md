# Modem foundations and deeper-suspend handoff inspection

User prioritizes deeper suspend, both speakers/microphones, cellular data/voice/
SMS and a notification panel. No active service or SIM is available. The roadmap
now brings modem discovery forward instead of waiting for a subscription.

## Live modem and audio inventory

Same #185 boot `be4da80f-2acc-4b4b-bea0-7d4667d62123`; nine successful suspend
cycles, zero failures, modem running, MSS control 0. No cellular netdev or ALSA
sound card is exposed. IPA is configured as a module but not bound, and ADSP is
disabled in the current DT. These are separate enablement tasks, not evidence
the hardware lacks support.

Read-only QRTR lookup advertises UIM (11), NAS (3), WDS (1), WMS (5), Voice (9),
DMS (2), PDC (36), IPA (49), DPM (47), IMS application (33), IMS settings (18)
and other services. Service presence does not validate carrier operation.

Installed standard `libqmi 1.38.0-1`, `libqrtr-glib 1.4.0-1` and dependency
`libmbim 1.34.0-1` through pacman. No ModemManager daemon installed or started.
Bounded read-only `qmicli -d qrtr://0` queries:

- DMS operating mode: `shutting-down`, HW restricted=no (repeated).
- UIM: both slots absent, no provisioning applications.
- NAS: not-registered-searching, CS/PS detached, no radio interface.
- DMS model: `0`; do not use this as a hardware model identifier.
- PDC software inventory: `InvalidQosId`; platform inventory made qmicli
  segfault. Neither result establishes that firmware configurations are absent.
- IMS registration query: `InvalidOperation`; not a proof that IMS is supported
  or permanently unsupported, and not a successful registration result.

After these queries, modem remains running, DMS still answers and Wi-Fi HTTPS
returns 200. Two new `invalid ipcrouter packet` messages followed the queries;
do not repeat PDC probes unchanged. Crash evidence is limited: see
`out/modem-handoff/qmicli-crash-evidence.log`; no stack is asserted without a
captured core. Here coredumpctl found no journal/core and memory had 5.7GiB
available; no OOM entry was found. Exact userspace failure mechanism remains
unknown. No Set Online, config load/select/activate, SIM PIN, modem reset,
call, text or carrier-account operation was performed.

The related 7T Pro reference already documents a stable `shutting-down` DMS
mode before cellular setup, and a failed transition to online without a valid
carrier configuration. Local reference:
`.work/hotdog-reference/docs/evidence/2026-08-25-radio-dms-shutdown-gate.md`.
This is corroborating evidence from another device, not a validated policy for
guacamole. Inspect supported config-query parsing before carrier setup.

## Power handoff result

Added `modem_handoff_snapshot.c` and `scripts/build_modem_handoff_snapshot.sh`.
Build extracts the private PAS layout from native5 source and copies matching
headers. Layout was compared with the deployed radio-module source; build used
vmlinux.symvers for symbol resolution (the usual absent full Module.symvers
warning remains). No unresolved-symbol load failure. Diagnostic captures software
state under device/rproc locks, requires this machine/kernel/driver and a running
remoteproc, creates a root-read-only snapshot, and makes no firmware calls,
power votes, PM transitions or MMIO accesses. Loaded, read and immediately
unloaded successfully; no automatic load hook.

Result in `out/modem-handoff/live-snapshot.log`:

```
rproc_running=1
q6v5_running=1
handover_issued=1
qmp_attached=1
load_state=modem
interconnect_attached=0
proxy_domain_count=2
proxy[0] runtime_status=2 usage_count=0
proxy[1] runtime_status=2 usage_count=0
```

Runtime status 2 is RPM_SUSPENDED. Linux has completed the handoff and released
both temporary CX/MSS votes. The QMP link exists with the expected load-state
name. There is no missing handover interrupt or absent QMP client to simply
enable. This snapshot does not prove that AOP implements the intended handoff.
No interconnect path matches the current DT; the vendor modem node also lacks
a bus-vote declaration, so that alone is not a demonstrated missing dependency.

The related reference's `0156-hotdog-integrate-validated-runtime-fixes.patch`
retains proxy power domains until modem stop to avoid a first-suspend watchdog.
This supports our isolated MSS-release result. Do not copy that blanket policy
to all remote processors or call it a low-power fix: retained votes cost power.

Kernel source also explains why failed restoration could block: rpmh_write
times out waiting for completion, while a subsequent rpmh_rsc_send_data waits
indefinitely for a command slot/resource conflict to clear. A userspace finally
block cannot guarantee recovery when the kernel request cannot complete.

Next power milestone: preserve the known-required modem hold while preparing
independent non-modem-domain tests with controller completion observability.
Do not repeat MSS release or globally enable CAMCC; no new rail-changing image
or sleep test is armed. Continue startup/suspend-resume health checks at every
step; the notification panel need not wait for complete power optimization.

## Xfinity and a future SIM

Xfinity's current BYOD instructions offer physical SIMs for eligible devices
and require an unlocked device plus an IMEI compatibility check. The OnePlus
7 Pro manual describes a physical nano-SIM tray. Exact phone eligibility,
carrier activation procedure for this Linux setup and Linux IMS/VoLTE behavior
remain unverified. Do not buy/activate/transfer service based only on advertised
modem services. No IMEI was sent to a third party during this investigation.

- [Xfinity BYOD and physical SIMs](https://www.xfinity.com/support/articles/bring-your-own-phone-details)
- [Xfinity activation instructions](https://www.xfinity.com/support/articles/how-to-activate-phone)
- [OnePlus 7 Pro manual](https://service.oneplus.com/content/dam/support/user-manuals/common/OnePlus_7_Pro_User_Manual_EN.pdf)
- [ModemManager QRTR/IPA device architecture](https://modemmanager.org/docs/modemmanager/wwan-device-types/)

Suggested milestones: read-only modem/config discovery; SIM detection; IPA data
interface; registered data session with a test SIM; SMS; IMS registration and
incoming/outgoing voice with both speaker routes and microphone; incoming-event
wake during suspend. Each needs its own result; data does not prove voice.
