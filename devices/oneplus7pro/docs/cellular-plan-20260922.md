# Cellular implementation handoff — OnePlus 7 Pro / guacamole

Investigated 2026-09-22. Intended for a future coding agent or human continuing
this repository. This is an implementation plan, not a claim of working cellular
service. No SIM was available. This investigation made only read-only phone
queries; it did not install services, change radio mode, flash, call, or text.

## Decision: should we get a SIM?

**A cheap, separate test SIM is a reasonable experiment. Buying service on the
expectation of working voice today is not justified.** There is a concrete path
to data, useful related-device code, and functioning modem control. There is
still substantial driver/integration work before an internet connection, and
voice adds unverified IMS and DSP audio requirements. No defensible numerical
success probability or completion date follows from the evidence.

| Outcome | Assessment on this phone |
| --- | --- |
| Detect a SIM and inspect its state | Next low-cost hardware milestone; no card tested yet |
| LTE data | Most promising initial service; IPA, carrier setup and registration remain |
| SMS in both directions | Plausible after registration; transport may require IMS |
| VoLTE with two-way audio | Credible research path, highest uncertainty; not demonstrated here |
| Reliable incoming calls/texts while asleep | Separate late milestone; cannot infer from awake operation |

Use a **physical nano-SIM with voice/SMS/data**, a new temporary number, and a
small prepaid commitment. A data-only plan cannot validate ordinary calls/SMS.
Prefer a SIM that can first be activated and verified in a supported spare
phone, if the carrier permits moving it. Keep the existing primary line until
incoming/outgoing calls, texts, reboot and sleep tests pass.

Assuming US use, a T-Mobile-network prepaid physical SIM is a reasonable first
candidate **if this handset's exact variant, unlock status, IMEI eligibility,
coverage and carrier policy check out**. This is an engineering preference for
a test path, not evidence that Linux VoLTE works with that carrier. T-Mobile
provides a [prepaid compatibility checker](https://prepaid.t-mobile.com/bring-your-own-phone/imei-check)
and [BYOD instructions](https://www.t-mobile.com/resources/bring-your-own-phone/).
Xfinity was considered in earlier notes; its [BYOD instructions](https://www.xfinity.com/support/articles/bring-your-own-phone-details)
also require eligibility/unlock checks and offer physical SIMs. Neither check
certifies this Linux software stack. Do not assume generic Verizon/AT&T profile
files make the phone eligible. Have the user perform any IMEI submission.

The SIM is useful before full cellular support: it unlocks UIM mapping, carrier
selection and registration testing. If spending nothing until data is closer
is preferable, complete phases 1–3 first. A borrowed suitable SIM can reduce
cost, but protect its PIN attempts and avoid using a primary line for debugging.

## Verified starting point

Fresh pinned-key SSH observations on September 22:

| Item | Observation |
| --- | --- |
| Kernel | `6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty` |
| Boot ID | `b43be7d0-77dd-4ef9-8199-ff63708160f4` |
| Remote processors | `modem` and `adsp` both running, also after queries |
| DMS | `shutting-down`, hardware restricted `no` |
| UIM | Both slots absent; no GW/1X provisioning applications |
| NAS | Not registered/searching, CS and PS detached, radio interface `none` |
| Net devices | Only loopback, USB and Wi-Fi; no cellular data interface |
| Userspace | libqmi `1.38.0-1`, libqrtr-glib `1.4.0-1`, NetworkManager `1.58.1-1`; ModemManager not installed |
| Radio helpers | `tqftpserv`; `rmtfs -r -P -o /root/radio-bringup/partitions -s -v` |
| Audio | ALSA OnePlus 7 Pro card present; speaker/capture/call quality not tested in this investigation |

The older [modem foundations](modem-foundations-20260917.md) enumerate QRTR
UIM/NAS/WDS/WMS/Voice/DMS/PDC/IPA/DPM/IMS services. They also record a qmicli
PDC platform-inventory segfault, software-inventory `InvalidQosId`, and IMS
`InvalidOperation`. These errors do **not** establish an empty profile catalog
or permanent lack of IMS. Do not repeat the crashing probe unchanged.

Local source inspection found `CONFIG_QCOM_IPA=m` and `CONFIG_RMNET=m`, but no
SM8150 IPA match, IPA v4.1 platform data, or IPA node in the inspected native
kernel source. Thus merely loading the existing generic IPA module is not a
complete solution. Reconfirm source/build correspondence before patching.

The existing `.work/guacamole-radio-firmware/image/` contains **242**
`mcfg_sw.mbn` files, including T-Mobile, AT&T and Verizon candidates, under
`modem_pr/mcfg/configs/mcfg_sw/`. No filename containing `ipa` was found in this
extracted tree. This establishes available inputs, not their suitability or
active state. Establish the exact MPSS build/catalog relationship with hashes;
do not identify firmware solely from a directory or profile count.

Current audio notes supersede the older “no ALSA card” observation:
[audio bring-up](audio-bringup-20260918.md), [status](status.md). Playback has
progressed, but microphone and telephony DSP routing are still open.

## References to reuse, with limits

The local related-device checkout is `.work/hotdog-reference`, pinned during
this investigation to `47087509c4289c2580c54f5433e55366b2e00445` from
[hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup).
It targets **7T Pro**, not this 7 Pro. Its status reports `rmnet_ipa0` working,
but SIM registration/data/SMS/calls are still pending. Unit-tested orchestration
is not carrier validation. Its OOS10 firmware assumptions must not become
guacamole constants.

Useful paths relative to that checkout:

- `kernel-checkpoints/clearstaff-403b56c-r181/patches/0144-*` through `0147-*`:
  IPA v4.1 platform data, registers, DT and binding.
- `docs/evidence/2026-08-18-ipa-ssr-notifier-deadlock.md`: IPA can block modem
  recovery; a bounded wait exposed further recovery faults, not full recovery.
- `docs/evidence/2026-08-25-radio-dms-shutdown-gate.md`: going online without
  active software MCFG caused a modem assertion on that device.
- `docs/evidence/2026-08-25-radio-pdc-{readonly,resident-catalog,apply-nosim}.md`:
  typed queries, stale resident profiles and no-SIM execution limits.
- `docs/evidence/2026-08-24-oxygenos-modem-stack-architecture.md`:
  detailed UIM/PDC/data/SMS/IMS ownership and restart handling.
- `helpers/hotdog-radio/`: PDC/UIM/WDS/WMS/Voice/IMS adapters, state machines,
  replay tools; associated `tests/test_hotdog_*` files.
- `aports/temp/libqmi/`: subscription-scoped PDC and IP voice attributes.
- `aports/temp/modemmanager/0002-*` through `0007-*`: SIM/PIN mapping,
  numberless calls, SMS IMS transport, IP voice and revalidation changes.

Evaluate upstream projects before porting all of this private stack.
[ModemManager documents QRTR control and IPA data](https://modemmanager.org/docs/modemmanager/wwan-device-types/).
[OpenIMSd's team reports VoLTE work on Pixel 3a and OnePlus 6T](https://www.openimsd.de/),
which is encouraging but not SM8150/carrier validation. Its
[profile-manager announcement](https://www.openimsd.de/09-qcom-baseband-profile-manager.html)
describes SIM-based PDC selection. The linked GitLab README was blocked by
anti-bot protection during this investigation; current source/API compatibility
was not audited. Fetch and pin source before choosing it.

## Architecture and ownership

```text
MPSS firmware + preserved EFS <-- rmtfs / tqftpserv
          |
         QRTR/QMI <-- UIM + carrier-profile bootstrap
          |                    |
          |              verified radio readiness
          |                    v
          +----------- ModemManager <----> NetworkManager (internet APN)
          |                    |
          |             Voice / Messaging D-Bus APIs
          |                    |
          |                 phone UI
          |
          +---- IMS support daemon (if required by this firmware)
          |       IMS settings/status, modem-requested IMS data sessions
          |
         IPA ---- rmnet/QMAP links ---- internet and IMS bearers

Voice signalling + ADSP voice session + codec/mic/earpiece routes = audible call
```

Use one owner for profile selection/radio startup, one for each bearer and mux,
and one for call-audio routing. ModemManager and an IMS daemon can coexist only
with deliberate ownership. Do not run oFono alongside ModemManager controlling
the same modem. Do not introduce Android RIL/HAL binaries into the Arch chroot
as a presumed shortcut; their dependencies and kernel contract differ.

## Implementation sequence and acceptance gates

### 1. Establish a reproducible baseline and firmware inventory — no SIM

Read `scripts/phone-radio-{start,test,network}.sh`,
`scripts/verify_radio_preflight.py`, the modem foundations and audio notes.
Record kernel/build source, DT, module hashes, firmware provenance, boot ID,
remoteproc state, QRTR services and network routes in ignored `out/cellular/`.
Keep device identifiers, SIM identities and raw traces out of tracked docs.

The current runtime is an Arch chroot with manual service startup. Check PID 1
and existing lifecycle before writing systemd units that may never run.
Retain pinned USB SSH and the existing recovery image/checkpoint. Preserve the
RMTFS guard reservations and working modem power hold. Do not fold CAMCC/MSS
power experiments into cellular enablement.

Inventory and hash the 242 local profiles and the actual deployed MPSS. Parse
profile metadata, IDs and carrier selectors using reviewed code, not names
alone. Locate matching IPA firmware from the correct device vendor/firmware
package; distinguish GSI firmware from modem firmware. Do not flash firmware
partitions merely to obtain a file.

**Pass:** reproducible manifest, restore path and known-good radio/Wi-Fi baseline;
missing IPA firmware and profile pairing explicitly resolved or tracked.

### 2. Make profile discovery reliable — no SIM

Inspect the previous qmicli PDC crash evidence before retrying. Reproduce parser
behavior offline or under an instrumented userspace build; use the typed PDC
reference as a comparison. Handle asynchronous indications, tokens, timeouts,
client release and QRTR generation changes. Distinguish protocol errors,
unsupported requests, malformed responses and “not provisioned.”

Read software catalog, selected/pending IDs per subscription and config info
with a bounded, non-mutating probe. Confirm libqmi field support rather than
blindly applying patches written against another version. PDC inventory failure
must block activation, not trigger a guessed profile. No need to query the
known-crashing platform inventory just to proceed with software discovery.

Compare OpenIMSd's profile manager and the hotdog bootstrap implementation for
the exact required operations. Keep ModemManager absent/disabled, including
D-Bus auto-activation, until startup ordering is understood.

**Pass:** reliable read-only UIM/PDC report and an offline plan for selecting a
matching profile; modem remains healthy. No card means no carrier activation.

### 3. Implement IPA v4.1 and rmnet — largely no SIM

Port the reference patches to the exact native kernel with review of subsequent
fixes. Compare against guacamole downstream DT and IPA tables: endpoint IDs,
memory regions, register windows, interrupts, IOMMU streams, clocks,
interconnects, SMP2P handshake and firmware reservations. Do not substitute
SDM845 or SM8250 tables. Review the reference's SSR timeout/recovery changes.

The hotdog DT uses AP-loaded GSI (`qcom,gsi-loader = "self"`) and
`ipa_fws.mbn`. Confirm guacamole's loader contract and reservation before using
that design. Avoid a loader waiting indefinitely for a handshake the firmware
does not supply. Validate DT and rebuild matching modules/image; never force
vermagic. Prefer a reversible test image with known recovery before persistence.

**Pass without SIM:** IPA binds, correct firmware loads, QMI setup completes,
physical data netdev appears, an rmnet link can be created/deleted, and modem,
Wi-Fi and audio survive startup. Capture errors and counters. An interface
appearing is not proof of traffic. Suspend/restart reliability remains a later
gate; do not enable blind recovery loops to hide crashes.

### 4. SIM mapping, carrier setup and registration — active test SIM

First establish exact device variant, carrier unlock/eligibility, SIM activation,
plan and APN. Map physical slot -> UIM application -> logical subscription;
verify a single populated slot before attempting dual-SIM support. Read PIN
state/retry counts; never guess a PIN or PUK. Use a known PIN only if needed.

Select a profile using actual SIM identity and matching firmware metadata.
Preview the exact ID/file/hash/subscription and current/pending IDs. Preserve
factory EFS/calibration and retain an explicit rollback. Do not delete resident
profiles as a first step, and do not copy hotdog's carrier IDs.

Current `rmtfs -r` uses a RAM shadow for writes. This protects backing radio
storage but means changes may be lost when the storage daemon/process lifecycle
ends. It does not make active PDC operations harmless. Keep the shadow during
initial experiments; later choose either deterministic bootstrap each boot or
carefully backed-up persistent state. Do not casually drop `-r`.

Load/select/activate only the reviewed software configuration, reconnect after
any modem restart, and read back active IDs on the same subscription. Then
allow one bounded online transition and NAS registration attempt. The related
device's pre-profile crash is a reason to enforce this order, not proof that
this phone has the same fault.

**Pass:** SIM ready, expected profile active, stable home/roaming registration
and packet-service attachment. On failure separate carrier rejection, profile
selection, RF/firmware crash and SIM provisioning; stop reset/retry storms.

### 5. Internet data

Build/install a QRTR-capable ModemManager with required, reviewed fixes. Confirm
port grouping associates the QRTR modem with IPA. Start it only after the
bootstrap gate, then let NetworkManager own the internet connection/APN.

First target one SIM and one bearer. Validate endpoint/mux binding, WDS packet
handle, IP family, address, gateway, DNS and MTU. Do not assume DHCP on raw-IP
rmnet or use generic USB `cdc-wdm0` instructions for this SoC. Add IPv6/dual-stack
once one-family behavior is understood and compatible with the carrier.

**Pass:** DNS and HTTPS demonstrably traverse the cellular link (bind traffic
and verify routes/counters, excluding USB/Wi-Fi fallback); sustained transfer;
clean disconnect/reconnect without leaked handles, links or stale routes.
Preserve the USB SSH subnet while testing. Then verify reboot and recovery.

### 6. SMS

Use ModemManager Messaging/WMS, initially with a diagnostic client. Establish
whether the carrier uses SMS over IMS or another LTE-supported transport;
do not assume data registration is sufficient. Audit the reference's WMS IMS
transport patch against the chosen ModemManager/libqmi versions. If IMS is
required, phase 7's registration work precedes successful SMS.

**Pass:** send and receive with another handset, then multipart and Unicode
messages, correct timestamps, storage acknowledgement/deduplication, notification
delivery and receipt after reconnect. Distinguish submitted from delivered.
MMS needs an additional service/APN path (for example a separately evaluated
MMS daemon); RCS is outside basic SMS and is not implied by this milestone.

### 7. IMS/VoLTE and call audio

Treat LTE voice as the target; do not depend on a legacy-network fallback.
Inspect IMSA registration/service status, IMS settings and firmware requirements.
Use current OpenIMSd where appropriate, with hotdog code as a reference; do not
write a new SIP stack merely because a QMI query fails.

OpenIMSd's [protocol investigation](https://www.openimsd.de/08-how-volte-is-working.html)
identifies a crucial reversed role: the baseband can request data sessions from
an AP-side IMS DCM service. An `ims` APN alone may not satisfy this contract.
Discover service/version support and implement the actual request/response
flow. Coordinate WDS subscription binding, unique rmnet muxes, requested IP
families, P-CSCF discovery and route lifetime. IMS routing must not accidentally
replace internet routing. Audit newer source before assuming the older article
describes every firmware requirement.

Only call signalling after IMS registration **and voice service availability**.
Check QMI IP-call attributes and ModemManager support, including anonymous
incoming calls. Registration alone does not prove the carrier will accept calls.

In parallel, finish microphone recording and earpiece/loudspeaker playback.
Then identify the actual ADSP voice-session interfaces (CVS/CVP/MVM or the
firmware's applicable equivalent), kernel support, DAI routes and mixer controls.
PCM media playback does not implement a baseband voice path.
[q6voiced](https://pkgs.postmarketos.org/package/v25.12/postmarketos/x86_64/q6voiced)
is a call-audio integration reference, not evidence it supports this kernel.
Audit its assumptions before installing it. Implement a supported voice route,
UCM/PipeWire policy and call-state integration. Preserve existing conservative
speaker limits until proper protection/calibration is established.

**Pass:** outgoing and incoming ordinary calls with two-way audio, earpiece and
speaker switching, microphone mute, acceptable echo/gain, ringing/ringback,
answer/reject/hangup, DTMF, and teardown restoring media audio. Verify concurrent
data and repeat after reboot. Use consenting test numbers; do not place routine
test calls to emergency numbers. Emergency calling is not established by these
tests and needs separate carrier-appropriate validation before daily reliance.

### 8. Sleep, persistence and phone UI

Subscribe to modem indications and implement bounded retry/backoff and restart
generation handling. Wake for incoming calls/SMS, ring/display notifications
while locked, inhibit suspend during calls, release inhibitors afterward and
recover data/IMS following resume. Use the existing guarded suspend/RTC recovery
workflow; first test short sleep intervals with another handset. Measure standby
drain with the new radio stack. Preserve the working power policy during bring-up.

**Pass:** repeated calls/texts arrive awake and asleep; missed-call state and
notifications persist; modem/Wi-Fi/audio remain healthy; power use is measured.
Provide signal/operator/SIM/PIN/data/airplane controls through narrow D-Bus
interfaces. Define airplane-mode behavior carefully because modem state currently
affects Wi-Fi startup. Build dialer and message UI only after the service APIs
work; integrate existing shell notifications instead of inventing another bus.

## Next-session instructions

Start with phases 1–2 and offline IPA preparation. The first useful deliverables
are a firmware/profile manifest, a safe read-only PDC probe and an IPA port diff.
Do not start by installing/enabling ModemManager or issuing Set Online.

Read-only baseline commands (run from this repo; script is invoked via bash):

```sh
bash scripts/phone-ssh.sh 'uname -r; cat /proc/sys/kernel/random/boot_id'
bash scripts/phone-ssh.sh 'for p in /sys/class/remoteproc/*; do cat "$p/name" "$p/state"; done; ip -br link; cat /proc/asound/cards'
bash scripts/phone-ssh.sh 'timeout 12 qmicli -d qrtr://0 --dms-get-operating-mode'
bash scripts/phone-ssh.sh 'timeout 12 qmicli -d qrtr://0 --uim-get-card-status'
bash scripts/phone-ssh.sh 'timeout 12 qmicli -d qrtr://0 --nas-get-serving-system'
```

`qrtr://0` was valid on the observed boot; rediscover if topology changes. With
a SIM inserted, treat query output as private. Keep each experiment bounded,
check remoteproc health afterward, and document exact pass/fail evidence.
No percentage progress based on daemon presence or test counts.

There are pre-existing uncommitted UI changes in this worktree. Preserve them.
This handoff added no implementation and does not require a flash/reboot.
