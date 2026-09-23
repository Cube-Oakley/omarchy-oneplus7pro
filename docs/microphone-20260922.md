# Microphone trial and boot-slot incident — September 22, 2026

Continues the [hardware plan](hardware-plan-20260922.md) audio packet. Result:
**the internal microphone works**. AMIC4, the stock handset mic, records through
PipeWire as `Internal microphone` and starts automatically with the audio stack.
AMIC1 and AMIC3 are also real microphones. The session also crashed the phone
once and exhausted slot B's boot retries; both are recorded below with the
recovery and the fix.

## Starting state

The previous session built `scripts/build_microphone_test.sh` (MIC BIAS routes
from guacamole `sm8150-oem.dtsi`, a MultiMedia2 capture front end, and the
per-link SLIMbus channel-map fix) and loaded it live on boot `b43be7d0`. After
that, `arecord` failed with EINVAL, and the restarted audio supervisor exited
because PipeWire could not open `guacamole_quiet`. Speaker playback was down.

## Finding 1: the two front ends were crossed

Opening the raw PCM nodes without hw_params (`pcm-open-probe.py`) showed
MultiMedia2 opened only for playback and MultiMedia1 only for capture, the
reverse of the routes that were enabled. Linux 6.17 refuses a DPCM front end
with no connected back end at `open()` and prints the reason only once
(`dev_err_once`), so later failures were silent EINVAL.

Cause: the live overlay adds `dai@1` under `q6asmdai`, and live overlays prepend
new children, so the q6asm DAI list became `[MultiMedia2, MultiMedia1]`.
`q6asm-dai` has no `of_xlate_dai_name`, so ASoC resolved `<&q6asmdai N>` as an
index into that list, not by `reg`.

Fix: `devices/oneplus7pro/kernel/audio/q6asm-dai-xlate-by-id.patch` matches the
phandle argument to each DAI's id, as `q6afe-dai` already does. It is built by
`build_audio_modules.sh`. Live result after swapping in the patched
`q6asm-dai.ko` and machine driver: MultiMedia1 (device 4) playback and
MultiMedia2 (device 0) capture open; the unrouted directions are refused. This
also matters for a future static DT, where non-contiguous `dai@N` would hit the
same index fallback. Log: `out/audio-test/20260922/swap-q6asm-dai.log`.

## Finding 2: WCD934x keeps stale TX state across a card reload

`slim_tx_mixer_put()` returns early when the value equals `tx_port_value[]`.
That array survives a machine-driver reload, but the channel lists are reset
in component probe and `set_channel_map()`. SLIM TX0 was left "on" with no
list entry: writing 0 finds nothing to remove, writing 1 matches the cache,
and the port cannot be enabled until the codec driver reloads or the phone
boots. The live trial used stock guacamole's equivalent `handset-mic-re-*`
routing instead: AMIC4 -> ADC4 -> AMIC MUX5 -> DEC5 -> SLIM TX5.

## Finding 3: capture runs but returns exact digital zeros

With AMIC4 selected, DAPM during capture showed MIC BIAS1, AMIC4, ADC4,
AMIC4_5 SEL and AIF1 CAP all on, and MultiMedia2 started with back end
`SLIM Capture 1` (S24_LE, 2 ch, 48 kHz). Every sample was exactly zero at
S16/mono and at S24/stereo. The cause was the live card reload: on a fresh
boot with the microphone overlay and patched modules loaded before the card
first registered (`scripts/phone-microphone-trial.sh`, audio autostart paused
for that boot), the reference's TX0/DEC0 route returned real samples. The
2-channel S24 back end fixup did not need changing.

## Result: which inputs are microphones

Same gains for every input (ADC 20, DEC0 90), 3 s each. Music came from a
separate device about 30-50 cm away, not from the phone's own speakers:

| Input | Bias | Quiet RMS | Music RMS | Change |
| --- | --- | --- | --- | --- |
| AMIC1 | MIC BIAS1 | -50.4 dBFS | -19.3 dBFS | +31 dB |
| AMIC2 | MIC BIAS2 | -66.5 dBFS | -66.6 dBFS | none |
| AMIC3 | MIC BIAS4 | -50.3 dBFS | -9.8 dBFS | +40 dB |
| AMIC4 | MIC BIAS1 | -53.4 dBFS | -15.0 dBFS | +38 dB |
| AMIC5 | MIC BIAS1 | -60.4 dBFS | -60.5 dBFS | none |

AMIC3 and AMIC4 clipped at that gain. At ADC 8 / DEC0 78 the music clips
measured AMIC4 -42.6, AMIC1 -47.2 and AMIC3 -40.9 dBFS, against a quiet control
of -79.8, -74.5 and -77.3 dBFS: +37, +27 and +36 dB. The user listened to the
AMIC4, AMIC1 and AMIC3 clips and confirmed the song was recognizable and clean.
AMIC2 (the headset-jack input) and AMIC5 carry only front-end noise, as on the
related 7T Pro.

Rub test, change over the quiet control, one input at a time while the user
rubbed a fingertip at each location:

| Location | AMIC1 | AMIC3 | AMIC4 |
| --- | --- | --- | --- |
| Bottom edge by USB-C | +29 dB | +4.5 dB | +25 dB |
| Top edge by pop-up camera | +19 dB | +21 dB | +19 dB |
| Back near rear cameras | +27 dB (peak -4.6 dBFS) | +15 dB | +26 dB |

AMIC3 is the top microphone. AMIC1 and AMIC4 both respond to the bottom and
the back; structure-borne rubbing noise and sequential single-input captures
cannot separate them. AMIC4 matches stock `handset-mic` and is the default.
A simultaneous two-input capture is needed before assigning AMIC1's position.

## Packaged into the audio startup

- `build_audio_modules.sh` applies `sm8150-slimbus-every-link.patch` and
  `q6asm-dai-xlate-by-id.patch`. Only `q6asm-dai.ko` and `snd-soc-sm8150.ko`
  changed; every other module rebuilt byte-identical.
- `phone-audio-test.sh speakers` loads `guacamole_microphone.ko` with the other
  board overlays, before q6asm-dai probes.
- `audio/start.sh` finds MultiMedia2 capture by name, writes
  `/etc/alsa/conf.d/99-guacamole-mic.conf` from `alsa-mic.conf`, sets the AMIC4
  route before PipeWire, and clears the front end route on exit. The default
  gain started at ADC4 Volume 10 / DEC0 Volume 84; after the user found speech
  slightly quiet it is ADC4 12 / DEC0 88 (+6 dB).
- `20-guacamole-input.conf` describes the `Internal microphone` source with
  `flags = [ nofail ]`, so a capture failure cannot stop PipeWire and the
  speakers with it.

Installed with `out/audio-test/20260922/deploy-mic.sh` (backup in
`/root/audio-bringup/backup-before-mic-20260922/`; 70 verified files). A clean
reboot, boot `bf5aa910-8f01-424a-bc31-638124c013cf`, started speakers and
microphone automatically with no deferred devices. A PipeWire recording of
room sound measured -70.6 dBFS. Silent playback still set both amplifiers
active and powered them down afterward. The mic bias switches off and the PCM
closes about two seconds after recording stops.

Speech through `pw-record` at arm's length measured -48.7 dBFS RMS, -28.8 dBFS
peak, with no clipping; the default gain leaves room for speech close to the
phone. Clips are in ignored `out/audio-test/20260922/recordings/`.

## Incident: SoC hang, crash-dump mode and exhausted boot retries

While diagnosing finding 3, a loop read `registers` for **every** regmap under
`/sys/kernel/debug/regmap/`. One of them (clock controller, LLCC or thermal
block) hung the bus, and at 12:52 the phone entered Qualcomm crash-dump mode
(`05c6:900e`). `scripts/sahara_reset.py` failed (`reset rc -7`). A three-button
reset with USB plugged in cycled through EDL (`05c6:9008`) for about 2 minutes,
then booted `dba1392e`: ext4 journal recovery, the UDC reported `not attached`
(no USB), Wi-Fi did not come up, and its diagnostics stopped after 26 s.

The next three-button reset showed "the current image has been destroyed".
Fastboot showed `slot-unbootable:b yes`, `slot-retry-count:b 0`,
`slot-successful:b no`; slot A (Lineage) was untouched at 7. **Our Linux never
marks a boot successful, so every boot spends one retry.** Every flash script
ends with `fastboot set_active b`, which resets the count, so this had not
surfaced before. Recovery was `fastboot set_active b` (retry 7, unbootable
cleared; no image written) and `fastboot reboot`. Boot
`7ee44e4a-1d18-4d86-a238-16198c65d3cd` came back healthy: USB in 35 s, modem
and ADSP running, Wi-Fi connected, audio autostart and PipeWire up, no
deferred devices, taint 4096. Getvar log: `out/recovery-20260922-getvar.log`.

Rules from this:

- Read only the WCD934x regmaps (`217:250:1:0` codec, `217:250:0:0` interface),
  and only the registers you need. Never iterate over every regmap.
- Unplug USB before a three-button reset. Holding both volume keys with USB
  connected enters EDL.
- A slot that is not marked successful spends a retry on every boot. Linux
  now marks it (below); a freshly flashed kernel still spends retries until
  it reaches the desktop. If the screen reappears, `fastboot set_active b`.

## Boot-success marking

`devices/oneplus7pro/boot-slot.py` changes only bit 54 (successful) of the
`boot_<slot>` entry in both GPT copies on `sde`, and updates their CRCs.
`qbootctl -m` sets the bit on every A/B partition and needs
`/dev/disk/by-partlabel`, which this chroot lacks; ABL reads only `boot`. Host
tests build a synthetic 4 KiB-sector GPT and check the exact bytes changed and
each refusal case; util-linux `sfdisk --verify` accepts the result, and its
attribute listing shows only bit 54 added.

On the phone, read-only `status` matched fastboot (`boot_b` active, retry 6,
not successful; `boot_a` retry 7). The GPT regions were backed up first to
`out/private/gpt-sde-20260922/`. The manual `mark-successful` changed exactly
entry 38 byte 54 `0x37 -> 0x77` in both copies plus the four CRC fields,
verified by a direct-I/O read-back diff.

With the user's approval the tool was installed as
`/usr/local/sbin/guacamole-boot-slot`, the `desktop-prepare.sh` hook as
`session-prepare` (previous copy kept in `/root/boot-slot/`), and the
`/root/boot-slot/autostart-enabled` marker created. A clean recovery reboot
gave boot `e8adeb46-61d9-487a-b9b8-df968ebf0aa0` with `boot_b` still at
retry 6 and successful, so **ABL honours the bit and no longer spends a
retry**. The hook ran 60 s after the desktop and logged
`already marked successful`; modem, ADSP, Wi-Fi and PipeWire came up
normally. The write path of the hook runs next after a flash, because
`fastboot set_active` clears the bit. Log: `out/boot-slot/reboot-20260922.log`.

## Next

1. After the next flash, confirm the hook marks the new kernel from `mark.log`.
2. User listening check of the PipeWire speech clip, then tune the default gain.
3. Microphone across suspend/resume, simultaneous playback and capture, and a
   browser recording.
4. Simultaneous two-input capture to place AMIC1, then expose AMIC1/AMIC3 for
   noise suppression or stereo recording.
