# Native reboot target

`pixel-reboot.c` registers a reboot notifier. Loading it only validates the stock
DT and maps the PMU for readback; no register is written until an orderly restart.
Normal restart selects mode 0. Setting the root-only `bootloader` parameter selects
0xfc on the next restart. The ordinary PSCI restart still performs the reset.

The module checks cheetah, `/exynos-reboot`, its syscon resource at `0x18060000`
and `reboot-cmd-offset=0x810`. It uses the same secure PMU write interface as
upstream `drivers/soc/samsung/gs101-pmu.c`, without binding GS201 to a GS101
power-management driver or writing battery-backed reboot storage.

Mode values and DT semantics come from Google's
[GS201 reboot module](https://android.googlesource.com/kernel/google-modules/power/reset/+/9b4bb088cf8f02bcebece637f0a1a6c33f3db29d/exynos-gs201-reboot.c).
The first hardware test of mode 0xfc reached Android recovery instead of the
bootloader. This target selector is experimental and must not be relied on for
recovery. Recovery ADB accepted `adb reboot bootloader` and restored fastboot.
The stock driver also writes battery-backed reboot storage; this module does not.
Do not reboot while installation is writing storage, and do not factory-reset
from Android recovery after installing the Linux root.
