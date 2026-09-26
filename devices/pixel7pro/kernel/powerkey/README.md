# GS201 / S2MPG12 power-key input

`pixel-powerkey.c` reads PMIC STATUS1 via the existing ACPM PMIC protocol and
reports debounced `KEY_POWER` events. Load only after ACPM activation on a checked
Pixel kernel. The driver performs no PMIC writes, IRQ acknowledgements, regulator
changes or system suspend. Five consecutive read failures release the key and
stop polling; unload/reload restarts it. This initial polling path cannot wake a
suspended CPU. Physical presses/releases and a complete screen sleep/wake cycle
were confirmed on v19 image A.

Build externally against the exact configured kernel, in an ignored output
directory, using `make -C <kernel> ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
M=<output> modules`. If `Module.symvers` predates ACPM, obtain the exported
`devm_acpm_get_by_node` entry from that build's `vmlinux.symvers` and pass it via
`KBUILD_EXTRA_SYMBOLS`; never ignore an unresolved-symbol error.

After loading, trigger `udevadm trigger --subsystem-match=input --action=add`
if the device existed before udev started. The Pixel GPU launcher now does this.
Shared `hypr-mobile.lua` routes the key to `power-button.py`, `display-power.sh`
and `CrtPower.qml`. There is no device-specific copy of the animation.

Register/transport provenance: Google GS kernel
`b3c9095e01cefb36f35723b5c66638bf15f5144a`, `s2mpg12-register.h`,
`s2mpg12-core.c` and `acpm_mfd.c`, checked against this handset's stock DT.
See [implementation and validation](../../docs/persistence-power-20260925.md).
