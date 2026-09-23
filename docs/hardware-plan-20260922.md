# Remaining hardware implementation handoff — guacamole

Prepared 2026-09-22 for the next coding session, including sessions with another
agent. Companion: [cellular plan](cellular-plan-20260922.md). This investigation
changed documentation only and made read-only hardware queries. It did not
record audio, move motors, enable radios, change brightness, or reboot.

## Start here

The next high-value work is **microphone and application audio**, followed by
**brightness, haptics and Bluetooth**. Sensor infrastructure unlocks rotation,
ambient light and potentially motion/proximity features. Camera work is larger
and must first address the known CAMCC/power interaction. Keep modem work on
the separate cellular plan. No SIM is needed for most work in this document.

| Queue | Deliverable | Dependencies / uncertainty |
| --- | --- | --- |
| 1 | Audible app playback and an intelligible microphone recording | Existing ADSP/codec/amps; routing and capture front end |
| 2 | Adjustable brightness; physically verified keys | Existing backlight/input interfaces; reversible verification |
| 3 | Haptic pulse and alert-slider policy | Identify guacamole wiring/profile; related driver exists |
| 4 | Bluetooth controller, HID and A2DP | UART/firmware/rails; known reference lifecycle regression |
| 5 | SLPI sensor inventory, acceleration and light | Firmware/config/calibration compatibility; FastRPC/SEE |
| 6 | One rear camera with a processed preview | CAMCC power issue, CAMSS/CCI/sensor drivers, software ISP |
| 7 | Remaining cameras, autofocus, safe pop-up lifecycle | Per-module wiring, actuators, position sensing |
| 8 | USB host/USB audio, then SuperSpeed and DP | Role/power management and QMP PHY recovery |
| Ongoing | Suspend, battery, thermal and reliable shutdown | Regression gates for every newly enabled block |
| Later | GNSS, NFC, video acceleration | Different independent driver/userspace chains |
| Research | Fingerprint, hardware keystore, cDSP, Warp charging | Vendor/TEE/protocol limitations; no completion promise |

Do one hardware change at a time. “Driver bound,” “interface exists” and “unit
tests pass” are intermediate milestones; each feature needs a physical result
and teardown/reboot/resume evidence. The priorities above are engineering
judgment, not time estimates.

## Current evidence and corrections to older plans

Read [status](status.md), the dated notes and actual runtime before old
[pathway](pathway.md) or the visual checklist. The old pathway contains
contradictory historical boot instructions: **this phone's ABL does not support
`fastboot boot`**. Use the repository's current guarded build/flash procedure
and known recovery checkpoint, never a generic phone guide.

Read-only SSH on September 22, same native5 kernel and boot as the cellular
investigation, found:

- MPSS and ADSP running; no SLPI remoteproc exposed in the running inventory.
- ALSA `00-03: MultiMedia1` advertises playback and capture on the same PCM.
  This is not microphone validation.
- `/sys/class/backlight/ae94000.dsi.0` exists: brightness and actual_brightness
  both `320`, max `1023`. The native panel driver calls the DCS brightness
  helper. Physical response to a changed value was not tested.
- No Bluetooth controller; rfkill only lists Wi-Fi. No media/video/IIO/Type-C
  devices were listed by the queries. Absence of IIO does not rule out future
  direct SEE sensor access.
- Twenty-five thermal zones and one cooling device exist. Sample on-die
  readings were about 36.8–40.3 C; gauge temperature 26.3 C. This proves readable
  temperature channels, not verified throttling or safe sustained operation.
- No CPU-frequency policies were listed and no cpu0 scaling-driver value was
  returned. Investigate driver/config/DT before discussing governor tuning.
- PID 1 reports `init`; the project still uses outer initramfs lifecycle with
  Arch in a chroot. Do not assume `systemctl enable` installs a working service.

Existing uncommitted `overlay/mobile/bluetooth.py` and `display.py` provide
settings inventory/UI work. Display code reports brightness without setting it;
Bluetooth UI existence does not establish a controller. Preserve this work.

Several checklist assumptions need verification: exact sensor chips, whether
this SKU has a barometer, SIM tray capacity, secondary microphones and camera
module variants. Do not convert a related phone's list into guacamole facts.
The alert slider should be tracked explicitly. Derived sensor definitions:
gravity estimates gravitational acceleration; linear acceleration subtracts it;
geomagnetic rotation uses acceleration plus magnetic field; game rotation omits
magnetic heading and can accumulate yaw drift.

## Reference map and common working method

Local primary evidence and code:

- `.work/linux-sm8150-codex-native/`: inspect exact running-source correspondence,
  `.config`, guacamole/common DTS, and affected drivers before changing them.
- `.work/lineage-kernel/src/`: downstream source reference; inspect guacamole
  board overlays and drivers here, not at `.work/lineage-kernel/arch/`.
- `.work/guacamole-radio-firmware/image/`: existing extracted firmware; inventory
  hashes and provenance before using another remote processor's payload.
- `devices/oneplus7pro/kernel/`, `scripts/build_*`, `scripts/verify_*`: current
  board changes and guarded test workflow. Keep board policy here and reusable
  UI under `overlay/mobile/`.
- `.work/hotdog-reference/` at `47087509c4289c2580c54f5433e55366b2e00445`:
  related **7T Pro** evidence and source. Its board GPIOs, rails, calibration,
  sensor addresses, firmware and actuator settings require guacamole validation.

In the tables below, `H:` means a path relative to that hotdog checkout;
`P:` means `kernel-checkpoints/clearstaff-403b56c-r181/patches/` inside it.
Read the **latest status and full patch evolution**, since early success notes
can be superseded by failures. The public [reference repository](https://github.com/Sr-0w/hotdog-linux-bringup)
is the retrieval source if ignored `.work/` is unavailable. Keep third-party
licenses/attribution when adapting code. Do not execute its deployment scripts
unchanged: they target another phone and rootfs.

Before each hardware trial: save kernel/DT/module/firmware hashes, boot ID,
remoteproc state and relevant logs; retain USB recovery; document one expected
effect and rollback. Use existing guarded modules/overlays only where lifetime
and ownership are understood. Rebuild a coherent image for changes that cannot
be safely applied live. Do not force unload a driver with known teardown faults.
Keep private calibration, identifiers, recordings and photos in ignored output.

## 1. Audio playback, microphones and call prerequisites

**Starting point:** [audio notes](audio-bringup-20260918.md), existing TFA9874
driver and routing overlays in `devices/oneplus7pro/kernel/audio/`, plus
`scripts/phone-audio-test.sh`. One tone was heard previously; individual outputs,
application playback and capture still need clear physical evidence.

**Playback:** compare a quiet known ALSA stream with the same file through
PipeWire. Record selected sink, PCM ownership, sample format/rate, mute and
volume at each layer, mixer route, amplifier clock/active state, and teardown.
Separate lower speaker and upper receiver tests; have the user identify the
source. If ALSA works but an app does not, inspect PipeWire/WirePlumber default
route and browser stream placement before editing the kernel. Preserve the
existing output cap while protection is unresolved; silence is not permission
to maximize analogue gains. Validate mono/stereo mapping and simultaneous output.

**Capture:** reference `H:docs/evidence/2026-08-07-mainline616-microphone.md` and
`P:0043-*`, `0044-*`, `0045-*`. That phone needed three independent fixes:
mic-bias routes, a separate Q6ASM capture front end, and channel mapping on every
SLIMbus link. Inspect whether our current card lacks each fix. Advertised
capture on MultiMedia1 is insufficient and resembles the reference's initial
shared-interface configuration.

Derive AMIC/bias mapping from **guacamole's active stock overlay**, then test
one plausible route at conservative gain with a known acoustic stimulus and a
quiet control. Do not blindly copy hotdog's AMIC4 choice or mixer gains: its
stock “handset mic” label was misleading. A nonzero RMS/noise recording is not
a pass. Require intelligible speech or correlation with an external test sound,
repeatable mute behavior and no clipping. Determine which physical microphone
responds by spatially isolating stimuli; do not claim every listed ADC is a mic.

Package the successful route in board UCM with a separate source. Verify it
from a fresh service start without manual mixer leftovers, then app capture,
simultaneous playback/capture, and reopen after suspend. Add echo cancellation
and noise reduction only after clean raw capture exists. Telephony DSP sessions
and routing remain separate work in the cellular plan. USB and Bluetooth
microphones each need their own profile tests.

**Done:** physically confirmed outputs, intelligible recording through ordinary
app APIs, gain/mute/route controls, no amp left active, reboot/resume regression
pass. Recordings require an attended test; none were collected here.

## 2. Brightness, refresh rate, touch and physical keys

**Brightness:** the sysfs node already exists. Read the exact panel implementation
and any vendor brightness override before adding a driver. Save `320`, test a
small nonzero bounded change with an automatic restore and USB access, and have
the user confirm luminance changes. Check DCS byte ordering/range and whether
panel init overwrites the value on wake. Expose a narrowly scoped setting path
to the shell, clamp inputs and persist the user preference. Test repeated blank/
wake and reboot; only then connect ambient-light policy with smoothing and a
manual override. Do not start with zero brightness, HBM or fingerprint illumination.

**90 Hz:** keep stable 60 Hz as baseline. Compare exact panel timing, DSC/PPS,
lane rates, regulators and bandwidth with stock. The related reference has
DSI/DSC corruption and FIFO/timeouts, so do not copy its mode and declare success
from compositor refresh alone. Validate scanout under load, switching, suspend
and power cost. Ambient/doze/AOD mode is a separate panel command and wake-policy
project; black pixels in a fully awake compositor are not a low-power AOD.

**Input:** use existing input-event scripts to verify volume presses/releases,
hold/repeat, power and touchscreen after repeated sleep. Identify alert-slider
GPIO/pinctrl or ADC wiring from stock; debounce all three positions, then map
to ring/vibrate/silent via one policy owner. The hotdog `ABS_SND_PROFILE`/
`fbd-alert-slider` path is a reference, not verified wiring. Test lock screen,
accidental edge/palm touches, rotation transforms and gesture conflicts.

**Done:** physical brightness and keys match UI state; touch coordinates remain
correct through transformations; no stuck keys or dark-screen recovery trap.

## 3. Haptics

Reference `H:docs/evidence/2026-08-11-haptics-aw8697.md`, `P:0128-*`–`0130-*`,
`H:helpers/hotdog-haptics-pulse.c`. Verify controller identity, I2C bus, reset/IRQ,
supply and actuator resonance from this board's source/calibration. Do not copy
hotdog's 170 Hz setting solely because the controller is also AW8697, or use a
newer Awinic register map on it. Avoid blind bus scans or forced I2C access
while a driver owns the device.

Port the minimal bounded `FF_RUMBLE` path with stop/remove/suspend handling.
First trial: a short weak pulse, explicit stop and physical confirmation. Test
repeat/interrupt/timeout without a stuck motor, then use feedbackd for a real UI
event. Respect slider/silent policy and cap repetitive feedback.

**Done:** user-confirmed vibration via the normal API, predictable stop and
strength, idle power recovery and a post-suspend pulse.

## 4. Bluetooth — useful reference, known regression

Reference `H:docs/evidence/2026-08-04-mainline616-bluetooth.md`, `P:0025-*`,
`0026-*`, and the **current** hotdog status/suspend evidence. Earlier firmware
loading, scanning and HID worked there; later controller initialization broke,
`qca_suspend()` timed out and unloading `hci_uart` panicked. This is a required
regression investigation, not a ready-to-copy solution.

Verify guacamole UART/serdev, pinctrl active/sleep, RTS/CTS, wake IRQ, supplies,
and clock configuration. Check HCI UART/QCA/serdev build options and exact
controller revision. Hotdog selected `crnv21.bin` and `crbtfw21.tlv` explicitly;
choose guacamole firmware from provenance/revision evidence, not diagnostic
symlinks hiding a mismatch. Read the pinned driver's shutdown and suspend paths
before repeated reset/load/unload trials.

Bring up one controller with bounded HCI capture/logging, then BlueZ on the
existing system D-Bus. Verify passive discovery, attended pairing with a known
device, HID input, disconnect/reconnect and retained pairing after reboot.
Next use PipeWire/WirePlumber for A2DP playback and separately HFP/HSP duplex
audio if required. A2DP does not prove microphone/call support. Test concurrent
Wi-Fi traffic because they share the radio package. Resolve suspend/unload
failures before enabling persistent automatic startup.

**Done:** useful paired-device traffic, working audio profile(s) explicitly
listed, clean power-off/reconnect, no Wi-Fi regression or suspend blocker.

## 5. SLPI / SSC and physical sensors

Reference `H:docs/evidence/2026-08-10-slpi-sensor-dsp.md`, then the August 19–25
sensor investigations, especially `2026-08-23-the-firmware-version-was-the-cause.md`,
`2026-08-23-userspace-has-a-sensor-path-now.md` and
`2026-08-24-my-decoder-was-hiding-four-sensors.md`.

Inventory this phone's stock sensor descriptors, selected board/project ID,
firmware versions, sensor JSON/config trees and per-unit `persist` calibration.
Build a table of physical chip/bus/address, claimed SEE data types and evidence.
Treat accelerometer/gyro/magnetometer/ALS, possible pressure/SAR/range sensors
separately from derived gravity/rotation/step outputs. Verify that a barometer
actually exists rather than inventing its driver from the old checklist.

Enable SLPI only after checking firmware segment bounds/reservations, regulators,
clocks, interrupts, QMP and FastRPC endpoints. Booting it is the first gate,
not sensor completion. Supply matching sensor skeleton libraries and a confined
Hexagon filesystem/registry service. Reproduce required identity and writable
registry semantics; keep calibration backed up and private. Do not regenerate
factory calibration as zeros or serve an arbitrary host filesystem to the DSP.

The reference's incompatible firmware/config pairing hid sensors despite a
running DSP. Port its diagnosis, not its OOS10 image: our guacamole must have a
matching set. If enumeration is sparse, inspect DSP logs and registry requests
before guessing bus addresses. Use `H:helpers/ssc-{client,subscribe,stream,verify}.py`
as protocol references. Decode sensor-specific event IDs, scalar/vector lengths,
timestamps and requested mode; continuous and on-change sensors differ.

Start low rate: static acceleration in multiple orientations, gyro rotation and
rest, magnetic-field response, light covered/uncovered. Check units, signedness,
mount matrices, sample cadence and bias. Validate physical stimuli independently
of the claimed sensor names. Then integrate libssc-capable iio-sensor-proxy if
available for the chosen Arch build; it can consume SEE directly, so absence of
`/dev/iio*` need not require a new kernel sensor driver. Gate consumers on actual
sensor readiness rather than D-Bus-name appearance. Set the correct mount matrix
and synchronize display/touch rotation; debounce rotation and offer a lock.

**Done:** repeatable physical readings, calibrated orientation/light exposed to
the shell, no high-rate polling in idle, correct reopen/reclaim after DSP restart
and suspend. Add derived sensors only when actual clients need them.

## 6. Proximity, range and pop-up Hall sensing are different

Do not treat darkness as proximity or a camera Hall sensor as a face detector.
The related phone uses an ADSP Elliptic ultrasonic path; its ALS-based heuristic
falsely reported a head in a dark room. Inspect guacamole's stock route to learn
whether it uses the same method.

If applicable, review `H:docs/evidence/2026-08-25-elliptic-protocol-from-oxygenos.md`
and the related near/far evidence and helper. Preserve per-unit calibration,
establish mic/ADSP prerequisites, and reproduce setup/suspend parameters before
publishing events. Test against a face, uncovered in darkness, in a pocket, and
while playing/capturing audio. Enable call screen blanking only once reliable;
restore display/touch immediately on far or call end. Measure standby overhead.
SLPI/ADSP naming in the reference is not proof of which block owns our signal.

Any laser/range sensor needs its own identity/driver/calibration evidence.
Camera mechanism Hall sensors are addressed under camera motor safety below.

## 7. Cameras, focus, pop-up and flash

The local phone exposes no media/video interface. The related port has a useful
CAMSS/libcamera path, so a proprietary hardware ISP is **not** a prerequisite
for the first processed preview. Its software-ISP solution still needs separate
quality, performance and thermal validation here.

**Critical dependency:** [deeper-suspend notes](deeper-suspend-20260917.md) record
that globally enabling CAMCC released power-domain holds and broke the modem.
Plan a camera test kernel that retains the known required power policy. Resolve
that interaction before loading the camera stack; never re-enable CAMCC casually
as a package dependency.

Read `H:docs/evidence/2026-08-09-mainline616-camera-{power-sequence,libcamera,imx586}.md`
and later IMX481/IMX471/focus notes. Reference patches span `P:0055-*`–`0124-*`;
review their final combined result, not every temporary diagnostic patch. Verify
CAMSS generation, CCI controllers, CAMNOC/interconnect bandwidth, IOMMU/DMA
limits, clocks/resets and sensor-to-CSIPHY/CSID/VFE endpoints. Use current
[kernel sensor-driver guidance](https://docs.kernel.org/driver-api/media/camera-sensor.html)
for controls, power management and interfaces.

Inventory actual modules and per-slot supplies/reset/MCLK/lane mapping from
guacamole stock configuration. IMX586 main and IMX471 front are expected;
IMX481/S5K3M5 are related-device candidates for the other cameras until verified.
Probe one powered slot at a time, with checked voltage/polarity/sequence and
bounded chip-ID reads. Do not indiscriminately scan or power all camera buses.

Start with the best-understood rear sensor: ID -> complete media graph -> a
bounded RAW capture -> repeated valid frames -> libcamera software-processed
preview/still. Validate Bayer order, stride, bit depth, timestamps, orientation
and optical content. Then sensor gain/exposure metadata, black level, colour,
white balance, lens shading and dynamic range; tuning files are model-specific.
Camera “IPA” in libcamera is its image-processing algorithm module, unrelated
to Qualcomm cellular IPA.

Add each remaining rear module separately. Identify autofocus/OIS actuator and
EEPROM/calibration; do not assume a sensor driver also implements focus. Begin
with bounded lens travel and known focus targets, then normal V4L2/libcamera
controls. OIS stabilization, production 3A and high-resolution/video modes are
later milestones. Preserve calibration and avoid EEPROM writes.

**Pop-up front:** reference `H:docs/evidence/2026-08-10-mainline616-camera-imx471-popup.md`
and the full sequence of motor fixes. First identify Hall sensors, establish
resting position and plausible position change, confirm reset/boost/step/dir and
PWM timing from our hardware. Require travel/time/drive limits, stalled-motion
detection and a stop path before any motion. Perform the first trial attended.
Do not copy position thresholds or step counts across devices. Never force the
mechanism by hand or run an unbounded motor loop.

Attach motor ownership to camera lifecycle: extend before optical capture,
retract after close, failed start, process exit and suspend. A kernel/runtime-PM
cleanup path is needed; a UI finally-block cannot cover process crashes. Test
repeated open/close, killed app and rejected stream start. Drop detection depends
on reliable motion sensors and should be tested with controlled stimuli, not
by dropping the phone. Failure must stop motion and report an error, not retry
against a physical endstop indefinitely.

**Flash/torch:** inspect actual PMIC channels, LEDs, current and timeout limits;
reference `H:docs/evidence/2026-08-12-camera-flash.md`, `P:0139-*`. Start with a
short low-current torch, then framework-controlled strobe with hardware timeout,
thermal/current limits and stop on app failure. Do not infer flash safety from
a working LED class registration.

**Done:** real preview/stills from each claimed sensor, working controls,
resources released, motor retracted on all exits, and reboot/resume/temperature
evidence. Camera access needs application permissions/portal integration later.

## 8. USB-C, SuperSpeed, docks and wired audio

Preserve known USB2 NCM/SSH. Read [USB notes](usb-networking-20260917.md) and
`H:docs/evidence/2026-08-20-smb5-v4-dock-validation.md`. Distinguish **data role**
from **power role**: a powered dock can make the phone a data host and power sink.

First inventory Type-C/role-switch/extcon/PMIC controller, VBUS regulator and
orientation/mux wiring. Implement coherent attach/detach and source/sink policy;
do not manually drive VBUS against an attached charger. Validate a low-power
USB2 HID peripheral, both plug orientations, then recovery to gadget SSH without
reboot. Add USB audio through standard class drivers and PipeWire, verifying
playback/capture and unplug restoration. Active digital adapters and passive
analogue adapters have different requirements; do not promise both.

SuperSpeed is a separate regression task: earlier QMP PHY enablement crashed
this phone. Inspect its recorded failure, PHY/clock/reset/regulator/IOMMU and
orientation handling before enabling it. Test clean enumeration and bounded
read-only transfers first; preserve filesystem integrity on detach.

DP requires Type-C alternate-mode negotiation, lane mux/orientation, PHY and
DRM. Use a conservative link-budget-valid mode and check hotplug, scaling,
touch mapping and return to internal display. The reference reports bad output
when a mode exceeds available lanes/bandwidth, and unresolved DP audio; keep
those acceptance gates separate. Ethernet enumeration is not traffic—test DNS/
HTTPS routes and reconnect. Finish with powered/unpowered docks and docked sleep.

**Done:** declared role combinations function in both orientations without
backfeeding, stuck peripherals, lost recovery networking or charging regression.

## 9. GNSS, NFC and Wi-Fi completion

**GNSS:** reference `H:docs/evidence/2026-08-10-gnss-qmi-loc.md`. QMI LOC session
start is not a position fix. Inventory capabilities; run a bounded standalone
outdoor test with reliable time, indications/NMEA parsing and explicit cleanup.
A SIM is not inherently required for satellite reception; modem operating state
and firmware behavior still matter. Do not bypass the cellular pre-online gate.
The reference's standard ModemManager bridge needed an IPA network port: this
is a userspace dependency, not proof GNSS physics needs cellular internet.
Validate fresh fix age, uncertainty and movement; compare cold/warm starts.
Then GeoClue/gnss-share or the selected supported bridge, location permission,
assistance data and stop-on-no-clients policy. Keep coordinates private.

**NFC:** reference `H:docs/evidence/2026-08-10-nfc-nxp-nci.md`, `P:0127-*`,
`0131-*`–`0137-*`, `0140-*`–`0142-*`. Verify chip/bus and interrupt, enable,
firmware, clock-request/reference-clock and board NCI configuration. Wrong
pinctrl caused resets on the reference; follow guacamole's own configuration.
Target the maintained NCI reader stack and a harmless known tag: reset/init,
poll, detect, read, stop, repeat. Only then app integration and suspend. Reader
mode does not establish card emulation, secure element or payment support.

**Wi-Fi:** keep the existing key-ack fix and suspend behavior. Measure both
bands, weak-signal/reconnect, throughput, routing after USB removal, Bluetooth
coexistence and wake-source cost. Verify per-device MAC provenance privately.
Add hotspot/roaming only after needed roles are established. Do not mistake
periodic scan warnings for proven causes of unrelated failures.

## 10. Power, thermal, CPU frequency and shutdown

Use [charging](charging-20260917.md), [gauge](battery-gauge-20260917.md),
[deeper suspend](deeper-suspend-20260917.md), [MSS trial](mss-handoff-test-20260917.md),
[MMCX trial](mmcx-sleep-test-20260918.md), and [shutdown](shutdown-20260917.md).
Keep current conservative charge limits and required modem hold while adding
devices. Do not remove all `*_ignore_unused` workarounds together.

**Thermal/cpufreq:** inspect thermal-zone sensors/trips, cooling bindings and
frequency-driver probe/config/OPP dependencies. Readable temperatures are already
present; next prove the correct cooling action with a short bounded load and
temperature/frequency traces. If cpufreq policies are absent, fix that cause
before governor tuning. Validate CPU/GPU separately, then realistic mixed load.
Do not disable throttling to improve benchmark results.

**Battery/sleep:** repeat gauge sampling under controlled brightness/radio/load
and unplugged conditions. Compare equal-duration runs and actual suspended time,
RPMh/SoC residency, wake reasons and per-domain state; keep several runs rather
than extrapolating battery life from one reading. Test each newly enabled DSP,
camera/radio driver for idle resource release. Use existing RTC/recovery guards;
MSS-release failure and CAMCC coupling are still constraints. Add incoming-event
wake tests only after the corresponding service works awake.

**Charging:** validate current/voltage/temperature/sign against independent
PMIC readback, USB source capability, unplug, termination/taper and fault limits.
Fast charging requires the right charger/cable/controller negotiation and thermal
policy. Raising a current register or copying hotdog's higher voltage is not
Warp support. Off-mode charging, low-battery boot/shutdown and simultaneous
dock charging need explicit tests. Use a USB meter when available.

**Shutdown:** current poweroff can reboot; USB loss is not success. Inspect live
PON/PS_HOLD nodes and bound drivers, selected poweroff handler and restart reason.
Distinguish failure to shut down from charger-triggered power-on using attended
plugged/unplugged trials. Flush storage and orderly-stop chroot services through
the real outer init; do not repeat force-poweroff as a proposed fix. Verify the
phone stays off physically, then expose a shell action and test the next boot.

## 11. Video codec, GPU, storage and recovery hardening

**Venus:** inspect SM8150 decoder/encoder driver support, firmware/reservation,
IOMMU, clocks and power dependencies. No video nodes were exposed in this run.
Bring up one supported decoder path and measure frames/CPU/temperature with a
known local clip. Then assess browser codec/backend compatibility and copy cost;
a working V4L2 decoder does not mean Chromium uses it. Diagnose network, software
decode, GPU/compositor and audio timing separately before attributing choppy
video to Venus. Encoding and camera recording are separate tests.

**GPU:** retain hardware rendering; measure sustained compositor/video/3D load,
thermal behavior, suspend and memory pressure before enabling aggressive modes.
**Storage:** preserve UFS functionality and validated partition layout. Verify
clean shutdown, writeback, capacity pressure and recovery before rootfs migration
or encryption. Hardware crypto support is not encrypted storage. Avoid raw
write stress against live partitions.

**Recovery/boot:** maintain a tested known-good image, matching modules and
boot/DT hashes, preserved Android slot, pinned SSH, crash logs/pstore and serial/
slot checks. Confirm boot-success marking and retry handling before unattended
reboot tests. Consolidate proven runtime overlays into reproducible board
patches only after their ownership/order is understood. A future true rootfs
init/service manager should inherit tested startup ordering, not race DSP and
radio setup. Never use firmware/bootloader replacement as routine driver repair.

## 12. Fingerprint, security hardware and compute DSP

Fingerprint is a research track. Reference
`H:docs/evidence/2026-08-19-fingerprint-goodix-udfps.md`: its sensor data path
belongs to a signed TrustZone applet, not an ordinary exposed SPI camera. Verify
our SKU/vendor HAL dependencies and current mainline secure transport support.
Do not port four GPIOs and expect fprintd to work. Required chain includes secure
transport/app protocol, enrollment/template storage/matching, display-region
illumination synchronization and authenticated integration with fprintd/PAM.
Do not treat a raw interrupt as successful authentication or weaken lock policy.

Hardware keystore may share secure-world dependencies but is not synonymous with
an NFC secure element or filesystem encryption. Inventory actual trustlets and
supported kernel/userspace APIs; keep software authentication as the usable
baseline. Avoid touching RPMB/provisioning keys during discovery.

cDSP acceleration: inventory exact remoteproc support, firmware, reservations,
FastRPC domains and compatible userspace before claiming it is impossible or
supported. Boot/IPC -> small known computation -> clean shutdown -> useful
runtime integration are separate gates. GPU/CPU inference remains the existing
fallback; sensor/audio DSP operation does not establish cDSP/NPU support.

## First resumed session: concrete work packets

1. Read this and the cellular plan; inspect `git status` and preserve existing
   shell changes. Refresh the short live baseline rather than redoing research.
2. Produce a guacamole audio diff reviewing separate capture front end, per-link
   SLIMbus setup and measured mic-bias wiring. Prepare an attended playback/
   recording trial with conservative levels and control stimulus.
3. Prepare a bounded brightness test using the existing interface and restore
   value; integrate the existing Settings page after physical verification.
4. Prepare independent haptics and Bluetooth source/DT diffs, each with exact
   firmware/wiring evidence. Keep the Bluetooth lifecycle failure a visible gate.
5. Inventory SLPI firmware/config/calibration and actual sensors offline. This
   unblocks a precise sensor trial without guessing addresses or replacing blobs.
6. Design the camera/CAMCC test with modem power preserved, then one rear sensor.

For every packet deliver: source diff, build result, artifact hashes, exact test
command, expected physical observation, bounded stop/rollback, and a short
dated result. Store raw/private evidence in ignored `out/hardware/`. Update the
visual plan only to the level actually verified. None of these tasks needs
waiting for a SIM; physical tests need the user present when sound, light,
motion, accessories or unplugging are involved.
