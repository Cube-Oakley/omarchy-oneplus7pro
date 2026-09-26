# GS201 UFS handoff driver

`pixel-ufs.c` connects the standard Linux UFS/SCSI core to cheetah's retained
bootloader configuration. It is an experimental bring-up driver, not complete
GS201 platform support: the bootloader still owns PHY calibration and clocks.
Runtime suspend, HS gears, inline encryption and clock scaling are disabled.
The default link remains PWM gear 1. A diagnostic PWM gear 4 experiment
failed with link errors and needed a reboot to recover; that option is not
included in the installed driver. Higher gears need the corresponding PHY/calibration work.

Required handoff details established on the connected 256 GB Pixel:

- HCI 3.0 at `0x14700000`, vendor registers at `0x14701100`, stock DT IRQ.
- Standard PRDT layout with 4 KiB segments; stock GS201 marks the old Exynos
  PRDT/OCS defects fixed. Do not copy the corresponding legacy quirks.
- CPort needs `N_DEVICEID=0`, `N_DEVICEID_VALID=1`, `T_PEERDEVICEID=1` and
  `T_CONNECTIONSTATE=1` before link startup. Omitting these times out NOP OUT.
- Retained SYSREG_HSI2 IOCC reads `0x13`: DMA must be coherent. Noncoherent
  allocations produced stale management responses.
- The controller advertises 64-bit DMA and RAM extends above 4 GiB. A 32-bit
  data-buffer mask fails SCSI mapping. Descriptor-address experiments did not
  explain the first-probe failure: both layouts failed before recovery. The
  working policy conservatively keeps coherent descriptors below 4 GiB while
  allowing 64-bit data buffers; this is not proof of a hardware descriptor limit.

With these settings, Linux enumerates all four logical units and their GPT
partitions. Full reads of `boot_a` and `init_boot_a` match the independently saved
stock/Magisk reference SHA256 values. Ext4 on userdata also passes a 16 MiB write/remount/readback test. The Arch root
was installed through a checked host-built sparse image. Image G mounts it and
passes GPU shader readback. Saved files survive reset and another recovery RAM
boot; autonomous boot remains under diagnosis. Cold
library reads take minutes at the current PWM gear 1 speed.

The inherited link returns invalid `0xff` to the first initialization queries.
The module now permits one complete failed-probe teardown/reinitialization,
without bypassing layout or outstanding-request guards. Image F discovers all
partitions in a fresh boot by 1.1 seconds. A second failure aborts module loading;
a bound controller is never retried. The cause of this handoff defect still needs
a full GS201 platform-driver fix.

`pixel-ufs-inspect.c` is the earlier read-only register inspection utility.
`reprobe=1` relaxes only the initial HCE check after an unsuccessful probe; it is
for unmounted development sessions, never for a mounted root.

Sources: Google's pinned [GS201 Exynos UFS driver](https://android.googlesource.com/kernel/gs/+/b3c9095e01cefb36f35723b5c66638bf15f5144a/drivers/scsi/ufs/ufs-exynos.c),
the matching `gs201/ufs-cal-if.c` tables, and the UFS core/GS101 driver in the
repository's pinned Linux base. Raw inventories and vendor downloads stay local.
See the [installation record](../../docs/persistence-power-20260925.md).
