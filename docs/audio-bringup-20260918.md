# Audio foundation checkpoint — September 18, 2026

User priority: spend limited Codex usage on difficult hardware work; defer shell
polish/widgets to other tools. Selected audio because both speakers and the
microphone are prerequisites for useful telephony.

## Continuing work: speaker tests and volume keys

Both physical amps at SE4 addresses 0x34/0x35 identify as TFA9874 revision
0x0c74. QUP0 must also be enabled (initial missing-parent test fixed with a
one-shot helper; consolidated amplifier overlay now includes it).

Adapted GPL TFA driver from the related-device reference, checked every common
register field against guacamole's own container and optimal 0c74 sequence
against its downstream `tfa_init.c`. Added the stock upper **Receiver** profile
and `Earpiece Mode` Receiver/Speaker control, initially Receiver. QUAT MI2S RX
uses SD1/GPIO140, clock/FS GPIO137/138, 48 kHz stereo S24_LE with 3.072 MHz BCLK.
SM8150 machine driver now checks clock errors and releases BCLK on close.
No OTP/MTP programming or calibration executed. External DSP speaker protection
is not yet integrated; this remains a manual, quiet, short-test setup.

Card now exposes **hw:0,3** (was device 2 before the speaker link). Both one-second
-60 dBFS channel-isolated tests and a lower/right-only -48 dBFS test completed:
clocks locked (`status1=e2c0`), upper Receiver system=0008 / lower Speaker=0018
while active; both returned to system=0001, active=0, clocks off afterward.
User heard one of the first two tones, location uncertain. Awaiting lower-only
listening result; do **not** claim both speakers acoustically verified yet.
Logs: `speaker-first-tones.log`, `lower-minus48.log`, `speaker-card.log`.

ALSA utilities and PipeWire/PipeWire-Pulse/WirePlumber installed using the
working official California HTTPS mirror, via a temporary pacman config.
PipeWire services have not been configured or started.

Volume keys: stock PM8150 GPIO6 up, GPIO7 down, active-low, 15 ms debounce,
input/pull-up/VIN1. Initial live overlay hit a kernel NULL dereference in
`pmic_gpio_probe` -> `regmap_read`: OF live notifier searches only the platform
bus for a parent, but this PMIC is an SPMI device. It created a parentless GPIO
controller. Both amps stayed powered down; reboot required to clear this
failed probe. Fixed overlay suppresses that notifier's creation with OF_POPULATED,
then creates the device explicitly under `spmi_find_device_by_of_node` after
checking its regmap. Fix compiled and **verified on a clean boot**: both keys enumerate, no deferred devices, taint stays 4096 (only out-of-tree modules). Fault log retained in
`out/audio-test/volume-keys-oops.log`. Never repeat the old module.

Clean boot `3cf9dc5c-e395-4b01-bcae-62952ea39efc`: corrected volume keys and
consolidated `phone-audio-test.sh speakers` both pass. ADSP/MPSS running,
card hw:0,3 present, both amps powered down, no deferred probes or kernel faults.
PipeWire/ WirePlumber now expose a static Internal speakers sink. ALSA route
applies a fixed -36 dB attenuation before the hardware; generic UI volume is
additional attenuation. PipeWire format must be S24_32LE, not packed S24LE.
Quickshell volume panel and media-key bindings installed and visually checked.
Next: complete separate lower/upper acoustic tests;
add bounded-volume application output + themed volume OSD; verify reboot and
sleep recovery before enabling persistent startup. Microphone remains untested.

User's requested delivery after audio: current README/working-status table,
real screenshots (Fastfetch, wallpaper, shade, launcher, overview, keyboard),
remove pull_sdcard.sh and personal identifiers/private material from publishable
files **and history**, then push to the existing local Git server for review.
Public GitHub publication explicitly waits for the user's later approval.

## Application audio and shell integration

PipeWire 1.6.8, WirePlumber and PipeWire-Pulse expose `Internal speakers`.
Board ALSA `route` applies fixed **-36 dB** attenuation to signed integer PCM;
this cap remains after any application/software-volume change and is not a
substitute for the unfinished stock DSP protection path. `pw-play` of one second
of silence activates both chips with locked clocks; two seconds after completion
the PCM closes and both chips return to power-down. Root PulseAudio and the
separate `mobile-browser` account both connect successfully. Browser access is
limited to the existing display socket and the PulseAudio socket; root D-Bus,
Hyprland IPC and general PipeWire socket are not shared.

`VolumeOsd.qml` and `volume.py` provide the portable themed floating slider,
mute and +/-5% actions. Hyprland binds the standard media keys with repeat;
no previous media bindings were present. Slider renders correctly in a real
screenshot. Backend check: 50 -> 55 -> 50; request 101 rejected, volume unchanged.
Physical button/earpiece follow-up still awaits user feedback. A later USB stall
during screenshot transfer recovered without reboot; same healthy boot, no new
Oops/deferred devices, ADSP running, both amps off and charger Full.

`devices/oneplus7pro/audio/start.sh` is installed as `guacamole-audio-start`;
the existing board session-prepare hook starts it when the local
`/root/audio-bringup/autostart-enabled` marker exists. The supervisor verifies
hashes, starts board modules, discovers the PCM by card ID/name, then owns all
three audio children. It refuses to adopt unrelated servers and tears down its
children/route if one exits. A stale manually launched Pulse server initially
blocked this check (its executable resolves to pipewire); corrected cleanup and
live supervisor startup passed. The complete automatic hook is installed but
**verified through a complete software reboot** on unchanged #188. Boot
`dcca1845-3070-43d3-9e21-85fe257b5c64` automatically starts ADSP, both amps,
volume keys, PipeWire, WirePlumber and PulseAudio. Quickshell volume IPC works,
Hyprland sees the key device, silent application playback closes the PCM and
powers both amps down afterward. No deferred devices/new kernel fault. Audio
system suspend is still untested. Logs: `audio-autoboot.log` and
`autoboot-playback.log`.

52 existing touch/QML tests and five backend tests pass; shell/Python syntax
checks and git whitespace checks pass. Keep the module/kernel-version guard:
these out-of-tree modules only match the prepared #188 kernel.

## Original foundation checkpoint

Unchanged kernel #188, release
`6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty`, boot
`65942a28-ceec-430b-a072-05e594903681`. No flashing or reboot performed.

- ADSP boots the phone's signed firmware and stays `running`, alongside MPSS.
- APR services 3 (core), 4 (AFE), 7 (ASM), 8 (ADM) enumerate and bind.
- Qualcomm NGD SLIMbus enumerates both WCD9340 endpoints.
- Physical codec reports chip major `0x108`, minor `0x1`, version `0x411`.
- WCD9340 codec, GPIO child and SoundWire driver bind.
- ALSA card 0: `sm8150 - OnePlus 7 Pro`, card ID **Pro**.
- PCM **device 2**, `MultiMedia1`, exposes playback and capture. Current nodes
  are `/dev/snd/pcmC0D2p`, `/dev/snd/pcmC0D2c`, `/dev/snd/controlC0`.
  Do not assume device 0; live overlay child order affects enumeration.
- No deferred devices at final check. Wi-Fi connected, HTTPS 200, charging.

**Not yet verified:** opening a routed PCM stream, audible sound, microphone
samples, physical earpiece routing, audio across suspend/reboot, audio power
consumption. No sound was played or recorded. External amplifiers remain absent
from the test DT. No speaker gain, calibration, OTP/MTP or factory data writes.

## Implemented pieces

`scripts/build_adsp_test.sh`: builds guarded ADSP-only live overlay against the
exact #188 prepared tree. Validates ELF32 firmware LOAD segment ranges and split
file lengths against reserved `[0x8be00000,0x8dc00000)` before packaging. The
live `memory@8be00000` is 30 MiB; modem `memory@8d800000` actually starts at
**0x8dc00000** despite its old node name. No overlap. The older downstream base
DTS has a 26 MiB ADSP reservation and must not replace the verified live layout.
Firmware source is the existing `.work/guacamole-radio-firmware/image/adsp.*`,
extracted from the same guacamole Lineage modem image used for radio bring-up.

`scripts/build_audio_modules.sh`: narrowly builds ALSA core, ASoC, QDSP6,
WCD9340, NGD SLIMbus and SoundWire modules in a separate work directory. Uses
#188 vmlinux.symvers plus native5 radio qcom_common exports. No change to the
running kernel config or radio modules. Kernel emits its usual missing full
Module.symvers warning; extra symbol tables resolve all required symbols.

`scripts/build_audio_card_test.sh`: builds a live codec/card DT overlay. Uses
standard SM8150 WCD9340 topology, GPIO143 reset, GPIO123 IRQ, 9.6 MHz BB_CLK2,
five 1.8 V S4A codec supplies verified against guacamole downstream audio DTS.
Minimal FE MultiMedia1 links to SLIMBUS_0_RX/AIF1_PB and SLIMBUS_0_TX/AIF1_CAP.
These are transport endpoints, not a claim of board-level speaker/mic routing.

Three runtime integration issues were resolved:

1. WCD codec initially probed before its SLIM interface device existed, returning
   EINVAL. A single manual codec bind succeeded once both devices enumerated.
   Saved loader now loads NGD controller before MFD/codec drivers so both bus
   endpoints exist first. **Fresh-boot ordering still needs verification.**
2. Base DT has an empty `/sound` node, already considered available. Adding
   compatible/status did not create its platform device. Card overlay now
   explicitly publishes this node if no platform device exists. A one-shot
   `guacamole_audio_publish.ko` accomplished this for the initial live attempt;
   subsequent fresh starts use the corrected main overlay automatically.
3. Dynamic overlay child order enumerated backends before the frontend. Q6routing
   attempted to connect MM_DL/MM_UL widgets before Q6ASM created them, causing
   card registration to fail with -19. `q6routing-probe-order.patch` sets its
   ASoC component probe order to LATE. Replacing inactive q6routing/q6asm_dai
   modules made card registration succeed. Some unused WCD muxes log 'no paths';
   those are not evidence of a functioning or failing physical audio route.

## Runtime and recovery

Files live in `/root/audio-bringup`. `phone-audio-test.sh status` is read-only;
`start` checks hashes/kernel/running modem, starts ADSP, enables codec/card and
loads modules in dependency order. `phone-audio-modules.py` refuses missing
dependencies and kernel mismatch; no forced module loads.

There is **no automatic startup hook**. The tests stay active for this boot;
reboot removes overlays and returns to the previous audio-disabled baseline.
Do not rmmod live overlay modules: they deliberately have no unload path. No
request to enter fastboot is needed for continuing these userspace/module tests.
Do not combine new deep-suspend experiments until this added DSP is accounted for.

Optional `alsa-utils` installation failed during download (mirror HTTP timeout),
with no packages changed. Phone HTTPS and Wi-Fi are healthy. Host HTTPS to the
generic mirror hostname also had a certificate-name mismatch; no TLS bypass was
used. Install ALSA utilities via a valid official mirror before PCM/mixer tests.
Card verification used kernel `/proc/asound` and `/dev/snd`, not aplay/arecord.

## Prepared next steps

Extracted from the already-local guacamole Lineage `vendor.img`, read-only:
`/odm/etc/mixer_paths.xml`, `/odm/etc/audio_platform_info.xml`,
`/odm/firmware/tfa98xx.cnt`, saved in `out/audio-test/stock/`.

- Stock `handset-mic` uses **amic4**, not AMIC5: ADC4, AMIC4_5=AMIC4,
  AMIC MUX0=ADC4, DEC0, CDC_IF TX0, AIF1_CAP SLIM TX0. Downstream
  `18821/sm8150-oem.dtsi` maps AMIC4 to MIC BIAS1. Add that supply route,
  a separate capture frontend, then test a short bounded capture with user
  participation. Do not blindly import the full Android mixer state.
- Stock TFA container CRC is valid, SHA256
  `4e2a59f7eb23014d81714dd701c14f8d4f8088d2f29bad938df6671da304a15e`.
  Describes devices 0x34 and 0x35, embeds `9874_dummy.patch`, has receiver,
  speaker and calibration profiles. This supports a TFA9874 hypothesis but
  **physical amplifier chip IDs are not yet read**.
- Guacamole downstream lists reset GPIO37 for 0x34, GPIO100 for 0x35,
  speaker I2S ID3 / QUAT MI2S. Verify exact bus/pinmux and read chip IDs first;
  then adapt the bounded amplifier driver using this phone's own parameters.
  Calibration profiles are not an instruction to recalibrate or write OTP.
- Keep sleep/wake, charging and independent modem checks in the next test.

Reference, already cloned under `.work/hotdog-reference`:
[7T Pro bring-up](https://github.com/Sr-0w/hotdog-linux-bringup), especially patches
0033–0035, 0038–0039, 0043–0045 and its `HiFi.conf`. Related-device reference;
the guacamole firmware, chip ID, reservations and wiring were checked separately.

Evidence: `out/audio-test/adsp-live.log`, `codec-reprobe.log`,
`audio-card-registered.log` (failed pre-fix attempt), `card-route-fixed.log`,
`final-inventory.log`, build logs and the stock container summary. Complete
local checkpoint: `out/checkpoints/20260918-audio-card/`.
