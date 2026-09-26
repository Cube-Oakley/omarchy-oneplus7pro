# Native GS201 firmware access — September 25, 2026

The native Linux kernel now talks to the Pixel's ACPM firmware through a GS201
common-clock provider, the Exynos mailbox driver and the upstream ACPM protocol
implementation. Frequency and temperature queries have been tested on the phone.
This is a prerequisite for CPU/GPU power management, not GPU acceleration.

## Verified results

Image C first proved frequency reads; image D repeated them and added temperature
reads. USB serial stayed responsive throughout. Three rounds in D returned:

| Firmware clock ID | Domain | Reported frequency |
|---|---|---|
| 2 | CPUCL0, CPUs 0–3 | 1,197 MHz |
| 3 | CPUCL1, CPUs 4–5 | 1,197 MHz |
| 4 | CPUCL2, CPUs 6–7 | 1,106 MHz |
| 5 | G3D | 151 MHz |
| 6 | G3DL2 | 151 MHz |
| 12 | DISP | 400 MHz |

These are firmware-reported frequencies. GPU clock queries do not establish
that the GPU is powered, that Linux owns it, or that it can render.

Temperature channel 9 returned BIG 43°C, MID 44°C, LITTLE 44°C, G3D 42°C,
ISP 45°C, TPU 42–43°C and AUR 41–42°C. Stock DT maps these groups to IDs 0–6.
Only `READ_TEMP` (0x02) was sent: no sensor initialization, threshold, interrupt,
emulation, suspend/resume or control request. Readings alone do not establish
working Linux thermal zones, cooling or shutdown protection.

Evidence is under `out/checkpoints/20260925-acpm-v13/`: `activate-c.txt`,
`queries-c.txt`, `activate-d.txt`, `temperature-first-d.txt` and
`temperature-repeat-d.txt`. C also completed five repeated CPU-query rounds.

## Clock and transport work

The new `clk-gs201.c` implements the verified CMU_APM subset at 0x18000000:
FUNC mux 0x1000, FUNCSRC mux 0x1004, FUNC gate 0x2084 and AP mailbox gate
0x20d4. The inherited mux selection is exposed read-only. Gates use the real
bit-21 enable and bit-20 manual controls; only these two gates receive setup
writes. No PLL, mux, CMU option or SYSREG write is issued. The FUNC gate is
critical and the mailbox driver holds its gate enabled.

Firmware owns the ALIVE PLL. The four source rates (394, 197, 50 and 99 MHz)
are vendor nominal rounded values, not independently measured PLL rates. The
board oscillator/pad clock phandles come from the live DT. This is a limited
bring-up provider, not a complete GS201 clock tree.

A manually applied, RAM-only overlay disables the vendor ACPM node and supplies
new CMU, mailbox (0x18210000, GIC SPI 78), SRAM (0x18500000, 0x48000 bytes)
and protocol nodes. It uses explicit GS201 compatibles. The overlay stays
installed until reboot; do not remove it live. OF emits warnings about memory
leaks on removal of changed properties, which is not an operation we perform.

The phone's firmware has 15 descriptors at SRAM offset 0x9270. Channel types
matter: type 1 is a ring queue; type 2 is a buffer/register interface. Some
buffer descriptors contain firmware-local addresses such as 0xa8200080; others
are placeholders. Treating all descriptors as SRAM rings is incorrect.

The ACPM driver now skips non-queue/non-polling channels, rejects transfers to
unsupported channels, and checks table, queue length, message length and SRAM
ranges before mapping queue pointers. The activation guard additionally checks
queue indices, machine identity and the stock SRAM resource. Channels 0 and 9
are verified polling rings with 16-byte messages. Neither type-2 transfers nor
interrupt-completion channels are implemented by this increment.

`CONFIG_EXYNOS_ACPM_CLK` remains disabled in the test profile, preventing the
ACPM clock consumer from querying everything or enabling frequency-setting
consumers at probe. The CMU provider and mailbox driver are active. Test glue
calls the upstream firmware API directly and exposes queries only.

## Reproduce the tested image

Latest image D:

- `out/checkpoints/20260925-acpm-v13/image-d/boot-pixel-shell.img`
- SHA256 `289a9bf3c2892a491d296eae0317ebf882511eb3684f0579e7cc3f251ec09055`
- Kernel `7.3.0-rc2-pixel-acpm13-g5225b8eec4c9-dirty`
- Automatic reboot after 600 seconds; all phone changes are in RAM.

Image C remains preserved with SHA256
`1cc2da1aeea742969ec71e70c4c4a8dde320be6fa352c3729a23336610b62e0f`.
The graphical v11d image and archived mobile userspace are separate fallbacks.
No Arch session or touch module was started in C/D.

From the project root, with the phone visible to authorized ADB or fastboot:

```sh
python scripts/boot-pixel-shell.py \
  --image out/checkpoints/20260925-acpm-v13/image-d/boot-pixel-shell.img \
  --sha256 289a9bf3c2892a491d296eae0317ebf882511eb3684f0579e7cc3f251ec09055
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/inspect'
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/activate'
python scripts/pixel-shell.py --command 'echo 2 > /sys/module/pixel_acpm/parameters/query; dmesg | tail -5'
python scripts/pixel-shell.py --command 'echo 0 > /sys/module/pixel_acpm/parameters/temperature; dmesg | tail -5'
```

Activation is once per RAM boot. Query IDs must be 0–13; temperature IDs 0–6.
This is privileged test glue, not a userspace ABI for the eventual OS. Kernel
sources live in `mainline/linux`; the overlay source is
`mainline/pixel-acpm-overlay.dts`. The build helper compiles its embedded DTBO:

```sh
python scripts/build-pixel-shell.py --acpm --seconds 600 --jobs 12 \
  --output out/checkpoints/NEW-UNUSED-DIRECTORY
```

The build helper performs no device operations. The boot helper validates the
phone/product, unlocked bootloader, successful stock slot A and image hash,
then uses `fastboot boot`. No partition was flashed or slot changed.

## Source preservation and validation

`devices/pixel7pro/kernel/acpm-v13/` contains the complete cumulative kernel
patch, config, overlay and base revision. Apply to the pinned clean Linux base,
not on top of the older native/ACPM patches. The image directories preserve
actual image/config/source hashes; the full image D build completed without
compiler warnings. The earlier `acpm-foundation/` patches are historical.

The new GS201 CMU binding passed `dt_binding_check`, including its example DTB.
The transport diff and the new CMU/test-glue C files pass checkpatch with zero
errors/warnings. The cumulative archival patch is not submission-ready: full
checkpatch also reports older bring-up style issues and the generated DTBO byte
array's formatting. `git diff --check` passes. No claim of GS101 hardware
regression testing is made.

Official GS201 reference revision:
[b3c9095e01cefb36f35723b5c66638bf15f5144a](https://android.googlesource.com/kernel/gs/+/b3c9095e01cefb36f35723b5c66638bf15f5144a/).
The `research/source.json` manifest records exact paths and downloaded hashes for
CMUCAL, ACPM DVFS and TMU protocols. Exact stock build provenance is still
unverified; the runtime tests establish only the exercised ABI subset.

## Next driver gates

1. Expose validated temperature reads through the thermal framework, with
   reviewed critical trips and cooling. Compare GS201's TMU response semantics
   carefully: the vendor temperature byte is unsigned whereas the upstream
   protocol currently uses a signed byte. The observed 41–45°C range is unaffected.
2. Validate CPU operating points and firmware voltage/interconnect coordination;
   integrate cpufreq and cooling before frequency transitions or sustained load.
   Stock frequency lists alone are not complete safe OPP tables.
3. Bring up GS201 PMU/genpd, GPU top/core clocks, IRQ/DMA integration and matching
   CSF firmware, then validate Panthor rendering and shader readback.
4. Replace retained scanout with GS201 atomic KMS, DPU/DPP, SysMMU, DSI and panel
   drivers. Keep shared Omarchy userspace independent of these device changes.

No OnePlus project files were modified.
