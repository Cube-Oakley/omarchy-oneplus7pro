# Pixel physical touch prerequisites — September 25, 2026

Historical read-only inventory. The subsequent [touch bring-up](touch-bringup-20260925.md)
now has a working, user-confirmed temporary physical input driver. The inventory
below records the prerequisites before that work.
The current v11d input device is only the USB-fed uinput development keyboard.
Native `/sys/class/spi_master` and `/sys/bus/spi/devices` are empty, as is
`/sys/class/power_supply`. See `20260925-hypr-v11d/touch-preflight.txt`.

The saved stock live DT (`out/restart-20260924/root-baseline/live.dts`, node
`/spi@10D10000/touchscreen@0`) identifies:

- Parent SPI0 at 0x10d10000, `samsung,exynos-spi`, 64-entry FIFO, USI dependency.
- Child `synaptics,tcm-spi`, chip select 0, max 10 MHz, mode 0.
- Separate vdd/avdd regulators and active/suspend pin groups.
- IRQ GPIO, active-low reset GPIO, explicit power and reset delays.
- Firmware variants `synaptics.img` and `synaptics_b.img` selected by panel map.

Phandle numbers in that decompiled DT are local references, not stable GPIO or
clock IDs to copy into another tree. Resolve each to its vendor node first.
The pinned mainline tree includes `google,gs101-spi` and `google,gs101-pinctrl`
support, but no direct GS201 match was found in those tables and no Synaptics TCM
touchscreen driver entry was found in the touchscreen Kconfig. GS101 similarity
is a source reference, not proof that its register/clock tables fit GS201.

Google's vendor source lives at
[synaptics_touch](https://android.googlesource.com/kernel/google-modules/touch/synaptics_touch/).
The saved stock kernel is 5.10.214 (December 2024 build). Google's Pantah 5.10
Android 15/QPR1 branch currently points to
`20b90037e7023858ec387cb2a4392f378b88855f`; its transport, main driver and build
files were fetched as a matching-family **research** baseline. Exact build-manifest
provenance still needs checking. The QPR2 branch is 6.1 and was not substituted.
Sources, branch resolution and SHA256 records are in
`out/checkpoints/20260925-touch-research/`.

The vendor Makefile force-enables Google touch-bus negotiation, heatmap/offload,
DRM-bridge integration and reflashing. The main driver has a `STARTUP_REFLASH`
work path. Do not transplant that build recipe into a first native touch probe.
Explicitly exclude startup reflash, ROM-boot/reflash interfaces and unrelated
Google integration until identity and report-only operation are understood.

Next sequence:

1. Resolve SPI0's USI, clock, pinctrl, regulator and interrupt dependencies from
   saved stock DT and matching vendor sources. Inventory firmware requirements.
2. Establish native GPIO/IRQ and the SPI controller with GS201-verified mappings.
   Do not enable a GS101 clock table merely because the compatible looks similar.
3. Read controller identity with bounded timeouts before reset/configuration or
   firmware operations. Port the minimum TCM transport/report path to Linux input.
4. Retain working USB serial/SSH and RAM-only boot. Preserve a known working
   display image throughout the change.
5. Once real events arrive in evtest/libinput, ask the user for a physical tap and
   drag test, then verify the unchanged shared shell's navigation and keyboard.

No SPI, GPIO, regulator, PMU or firmware writes were made during this inventory.
