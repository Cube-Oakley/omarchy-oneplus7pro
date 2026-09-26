# Pixel physical touch bring-up — September 25, 2026

The S3908 touchscreen responds in the native v11d RAM boot. A temporary GPIO SPI
input module registers with Linux and Hyprland as a physical touchscreen. The user confirmed that the interface responds to physical touch, although it
is very slow. Kernel logs and an independent evdev capture confirm real contact
coordinates, touch-down and touch-up events.

## Recovered hardware path

Google's [Pantah wiring reference](https://android.googlesource.com/kernel/devices/google/pantah/+/9810b5840267f30cd3cc81d6b054de313140af58/dts/gs201-ravenclaw-touch.dtsi),
checked against this phone's saved stock live DT, identifies SPI0:

| Signal | GPIO | Controller base / bank offset |
| --- | --- | --- |
| SCLK, MOSI, MISO, CS | gpp20 pins 0, 1, 2, 3 | PERIC1 0x10c40000 / 0x00 |
| Active-low reset | gpp23 pin 2 | PERIC1 / 0x60 |
| Active-low interrupt | gpa7 pin 0 | FAR_ALIVE 0x180e0000 / 0x20 |
| AP-to-AOC bus ownership | gph1 pin 0 | HSI1 0x11840000 / 0x20 |
| AOC-to-AP acknowledgement | gpa8 pin 7 | FAR_ALIVE / 0x40 |

GS201 vendor pinctrl source confirms bank offsets and register layout: CON+0,
DAT+4, PUD+8, DRV+12. Only specified pin fields are modified. The initial bootloader
state has SPI pins as GPIO inputs, CS high, reset configured as an output **low**,
and both ownership signals low. The vendor touch bus negotiator defines raw
ownership value zero as AP. GPIO polarity flags must not invert that raw check.

`mainline/pixel-touch-inspect.c` reads the five banks without writing them. It
checks the machine compatible and the DT register base/size before mapping
`/dev/mem` read-only. Native DT uses 2 address cells + 1 size cell, not the saved
stock dump's four-cell representation.

## Successful probes

`mainline/pixel-touch-gpio-probe.c` claims the three GPIO pages, checks machine/DT
and exact inherited pin state, requests AP ownership, makes GPIO mode-0 SPI,
releases reset after 20 ms, waits 200 ms, and reads startup data. It restores reset,
SPI pin configuration/data/pulls and ownership pin state before returning.

The first startup response was:

```
a5 10 18 00 01 01 53 33 39 30 38 47 41 31 42 30 2d 31
35 2e 30 00 00 a3 3e 00 00 04 5a ...
```

Decoded using the [pinned Google/Synaptics TCM source](https://android.googlesource.com/kernel/google-modules/touch/synaptics_touch/+/20b90037e7023858ec387cb2a4392f378b88855f/tcm/):
TCM v1, application mode, part `S3908GA1B0-15.0`, build 4104960, max write 1024.
No firmware download was needed. The next probe sends only GET_APPLICATION_INFO
(0x20) and GET_TOUCH_REPORT_CONFIG (0x25), with bounded response waits and lengths.
Application status is zero; maximum coordinates are 1439×3119, ten objects,
128-byte report configuration and 256-byte maximum report payload.

Both completed probes restored all five inspected GPIO bank snapshots exactly.
No firmware, PMIC, SPI clock/controller or storage writes were performed.

## Temporary physical input driver

`mainline/pixel-touch-input.c` extends the checked transport into an explicitly
opted-in module. It preserves the controller's existing report format and accepts
only the observed application geometry/status and exact 128-byte format. The
format has an 11-byte prefix and 12 bytes per active object, including slot,
classification, X/Y, pressure, widths and vendor fields. The initial input path
publishes finger/glove positions through ten Linux MT slots; unused slots are
released each frame. Complete packet framing, length, coordinates and duplicate
slot IDs are validated before publishing events. Unsupported/malformed packets
stop polling and restore pins.

This is deliberately a short-lived bring-up transport, not the final hardware
SPI driver. GPIO bitbanging is slow and polling adds latency. The worker defaults
to 300 seconds (allowed 10–600), restores hardware on timeout/unload, and checks
AOC ownership each iteration. The full RAM image also reboots at 1800 seconds.

Build against the **exact current v11d kernel build**, including Module.symvers:

```sh
mkdir -p out/checkpoints/20260925-touch-v12/input-module
cp mainline/pixel-touch-input.c out/checkpoints/20260925-touch-v12/input-module/pixel_touch_input.c
printf 'obj-m := pixel_touch_input.o\n' > out/checkpoints/20260925-touch-v12/input-module/Makefile
make -C mainline/linux ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  M="$PWD/out/checkpoints/20260925-touch-v12/input-module" modules
```

Copy the module into the phone's RAM root through the current SSH wrapper, then:

```sh
insmod /root/pixel_touch_input.ko probe=1 seconds=300
# Tap/drag during the bounded window. Stop sooner with:
rmmod pixel_touch_input
```

On the first load, Linux created `/dev/input/event1`, udev set
`ID_INPUT_TOUCHSCREEN=1`, and `hyprctl devices` listed the S3908 under Touch.
The first session processed 42 touch reports without a protocol error before
explicit unload. All inspected GPIO banks again matched the original snapshot.
An independent 55-second evdev capture contains 61 events / 13 synchronized
frames, including three contact lifecycles, X/Y movement and release. This was a
sparse tap test, **not** a throughput benchmark. The user confirmed UI response.

The first bitbang implementation used 5 µs per half-cycle. A follow-up combines
SCLK-low/MOSI updates and uses a configurable 1 µs delay (allowed 1–10), still
well below the controller's 10 MHz maximum. The 131-byte configuration read fell
from about 29 ms to 14 ms based on kernel log timestamps. That measures transport
only, not end-to-end touch latency. It also records aggregate transfer timing
when the worker stops. The first working source/module are retained separately
as `input-first-source.c` and `input-first.ko`.

Software rendering and the retained framebuffer copy remain major performance
constraints; Hyprland was using roughly two CPU cores averaged over this session.
Hardware SPI/interrupt input and GPU/display acceleration are separate follow-up
work. Do not attribute all UI lag to the touchscreen or claim GPU acceleration.

Artifacts are in `out/checkpoints/20260925-touch-v12/`: initial/read-only GPIO
snapshots, startup and info probes, warning-free module builds, compositor input
inventory, source snapshots and hashes. The directory name v12 denotes this touch
experiment; **no v12 boot image was built or flashed**. The working display image
and saved shared mobile rootfs remain unchanged. The OnePlus project was not edited.

## End of experiment and direction

The user confirmed the shorter-delay driver still responds but is only slightly
faster, and explicitly prioritized proper CPU/GPU/display drivers. The second
run handled 16 touch reports without protocol errors. It moved 2624 bytes over
1,001,082 µs of measured transfer time (includes scheduling interruptions), then
was explicitly unloaded. All five GPIO snapshots again matched their originals.
The driver is now stopped; source and both module versions are saved. This is
proof for a future standard SPI/input driver, not a production architecture.

The RAM session was intentionally rebooted into the stock reference kernel for
read-only hardware inventory. The current native CPU inventory had all eight
cores online, but no cpufreq policies or thermal zones. Full Linux ownership of
GS201 clock/power/firmware interfaces is the next foundation to investigate.
