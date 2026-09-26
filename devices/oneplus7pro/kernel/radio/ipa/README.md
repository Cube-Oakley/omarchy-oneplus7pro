# IPA v4.1 for guacamole (SM8150) — prepared, not deployed

Cellular plan phase 3 ([cellular plan](../../../docs/cellular-plan-20260922.md)).
Nothing here has run on the phone: no flash, no module load, no firmware copy.

## Contents

| File | What it is |
| --- | --- |
| `0001-net-ipa-add-IPA-v4.1-platform-data.patch` | hotdog `0144`, verbatim |
| `0002-net-ipa-add-IPA-v4.1-register-definitions.patch` | hotdog `0145`, verbatim |
| `0003-dt-bindings-net-qcom-ipa-add-sm8150.patch` | hotdog `0147`, verbatim (binding only) |
| `0004-net-ipa-describe-ENDP_INIT_CTRL-for-IPA-v4.1.patch` | subset of hotdog `0156` (`reg/ipa_reg-v4.1.c`) |
| `0005-net-ipa-bound-the-wait-for-a-committed-GSI-transaction.patch` | subset of hotdog `0156` (`gsi_trans.[ch]`) |
| `0006-net-ipa-correct-IPA-v4.1-data-for-guacamole.patch` | this project: two corrections from guacamole's downstream |
| `guacamole-ipa.dts` | boot-DTB overlay: IPA node, modem SMP2P `ipa` entries, carveouts |
| `build-ipa-module.sh` | build-only: patched `ipa.ko`, upstream `rmnet.ko`, overlay check |

Provenance: [hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup)
at `47087509c4289c2580c54f5433e55366b2e00445`,
`kernel-checkpoints/clearstaff-403b56c-r181/patches/`, author Robin Snyders;
kernel code, GPL-2.0. Author lines are kept; 0004/0005 are marked as subsets.

## SoC-generic versus board-specific

- **SoC-generic (ported):** v4.1 platform data (0001), v4.1 registers (0002) plus
  the missing `ENDP_INIT_CTRL` (0004; `ipa_endpoint.c` programs it for every
  version below 4.2, so 0002 alone is incomplete), and the bounded GSI command
  wait (0005; the reference's SSR-notifier deadlock on the same SoC).
- **Board-specific (not copied):** hotdog `0146` (its DT and hotdog's firmware
  path) — replaced by `guacamole-ipa.dts`.
- **Not taken from 0156:** `ipa_power.c` `no_system_suspend` (the reference
  calls it a diagnostic, not a fix); the `qcom_q6v5` wake IRQs and PAS proxy
  power-domain hold (remoteproc policy, not IPA; this project already has its
  own tested modem hold); sdhc2, IMEM reboot-mode, Wi-Fi, DSI and other hunks.

## Checked against guacamole's own downstream

Source: `.work/lineage-kernel/src` (18857 DT, `drivers/platform/msm/ipa/ipa_v3`).

| Item | Downstream | Result |
| --- | --- | --- |
| Hardware version | `qcom,ipa-hw-ver = <15>` (IPA v4.1) | matches |
| Endpoints (APPS/Q6 CMD, LAN, WAN) | `ipa3_ep_mapping[IPA_4_1]` | channel, endpoint and TLV match for all eight endpoints 0001 uses (mainline has no APPS_LAN_PROD) |
| Source resource groups | `ipa3_rsrc_src_grp_config[IPA_4_1]` | match |
| Destination resource groups | 4 groups (`IPA_v4_0_DST_GROUP_MAX`) | 0001 declared 3; **0006 adds the 4th** ({2,2} sectors, {0,2} DMARs) |
| QSB limits | `{12, 8}` DDR, `{12, 4}` PCIe | match |
| IPA-local memory map | `ipa_4_1_mem_part` | all 24 regions match |
| SMEM filter table | `IPA_SMEM_SIZE` 8 KiB, no DT override | matches `0x2000` |
| IMEM modem tables | `ipa_smmu_ap` additional mapping `0x146BD000`, `0x2000` | 0001 had `0x146a8000` (the sc7180 value); **0006 corrects it** |
| SMMU streams | AP `0x520`, WLAN `0x521`, uC `0x522` | overlay uses `0x520`, `0x522` |
| Interrupts | SPI 311 (IPA), SPI 432 (GSI) | used |
| SMP2P | `smp2p_ipa_1_out/in`, entry `"ipa"` on mpss | added by overlay |
| Firmware loader | `qcom,ipa_fws` `qcom,pil-tz-generic`, PAS id 15, `pil_ipa_fw_mem` | AP-loaded: `qcom,gsi-loader = "self"` |
| Bus votes | MASTER_IPA→EBI/OCIMEM, AMPSS_M0→IPA_CFG | same paths; SVS2 bandwidths as in 0001 |

## Memory

Downstream generic `18857/sm8150.dtsi` puts IPA at `0x98700000`, but OnePlus'
`18857/sm8150-oem.dtsi` overrides the whole PIL tail. The running #188 DTB
(`bringup-guacamole.dtb`) has a staged layout from the radio work: mpss is the
OEM `0x8dc00000`+160 MiB, video/SLPI disabled, `0x97c00000–0x98b00000` kept
no-map, and IPA still at the legacy `0x98b00000`.

| Region | OEM | Running #188 | With overlay |
| --- | --- | --- | --- |
| ipa_fw | `0x99500000` 64 KiB | `0x98b00000` | `0x99500000` |
| ipa_gsi | `0x99510000` 20 KiB | `0x98b10000` | `0x99510000` |
| gpu | `0x99515000` | `0x98b15000` | unchanged (working) |
| spss | `0x99600000` | `0x98c00000` | unchanged |
| cdsp (disabled) | `0x99700000` 20 MiB | `0x98d00000`–`0x9a100000` | `0x98d00000`–`0x99500000` |
| old IPA spots | — | — | `ipa-legacy-hole` no-map |
| rest of old cdsp | — | — | `cdsp-legacy-tail` `0x99515000`–`0x9a100000` no-map |

Checked by merging onto the running DTB: the union of no-map RAM is unchanged
and no enabled regions overlap. No conflict with ADSP (`0x8be00000`, 30 MiB)
or mpss (`0x8dc00000`, 160 MiB). The OEM IPA spots were already inside the old
cdsp no-map span, so Linux has never allocated them.

`ipa_fws` from the Lineage `vendor.img` `/firmware` (extracted to ignored
`.work/ipa-port/firmware/`) is ELF32 and **relocatable**: load segments at
offsets `0x0–0x61c0` plus a hash segment, well inside 64 KiB. SHA256:
`ipa_fws.mdt` `34a2dcc5…edf8`, `.b00` `f8e8e7ad…724d`, `.b01` `433893c9…2247`,
`.b02` `2e181083…016d`, `.b03` `14024088…1507`, `.b04` `8d572c4b…3373`.

## Why a boot DTB, not a live overlay

The built-in `qcom_smp2p` driver parses its child entries only at probe
(`smp2p.c`, `for_each_available_child_of_node_scoped`), and smp2p-mpss is in use
by the running modem. IPA's `qcom,smem-states` and `ipa-setup-ready` interrupt
need the `ipa` entries, so they must be in the DTB at boot. Reserved memory is
likewise boot-time only. Deliver `guacamole-ipa.dts` the way
`guacamole-radio-guards.dts` is delivered: merged into the boot DTB by
`scripts/build_native_display.sh`. That script accepts one `NATIVE_EXTRA_DTS`;
the next image needs **both** the radio guards and this overlay. The kernel
Image can stay #188, so every existing module keeps its vermagic.

## Build status

`bash devices/oneplus7pro/kernel/radio/ipa/build-ipa-module.sh` applies 0001–0006
to a clean copy of the #188 driver, builds `ipa.ko` (alias
`qcom,sm8150-ipa`, depends `qcom_common`) and upstream `rmnet.ko`, both with
vermagic `6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty`, compiles the overlay
with plain `dtc` and merges it onto `bringup-guacamole.dtb`. No errors beyond the
usual missing full `Module.symvers` notice. Output: ignored `out/cellular/ipa/`.

## Unverified — evidence needed before relying on it

- TrustZone accepting PAS id 15 at `0x99500000`: a `qcom_scm_pas_auth_and_reset`
  success (or error code) in dmesg on first load.
- Core clock `100 MHz` and interconnect figures come from the reference, not
  derived here; downstream votes the IPA core through msm-bus (`IPA_CORE` 125–600).
- `dma-coherent`: downstream `ipa_smmu_ap` has it; mainline sdm845 and the
  reference omit it. Left out.
- Load ordering relative to the modem, and behaviour across the existing
  suspend path, modem crash/SSR and Wi-Fi (the reference saw post-SSR channel
  state errors that 0005 exposes but does not fix).
- Any IOMMU fault from stream `0x520`/`0x522` (this phone has crashed to 900e
  on SMMU mistakes before).

## What a flash test needs

1. Boot image: unchanged #188 kernel; DTB = `bringup-guacamole.dtb` source
   plus radio guards plus `guacamole-ipa.dts`, via the guarded flash scripts.
   The user enters fastboot by buttons (ABL has no `fastboot boot`); the new
   image spends boot retries until the boot-slot hook marks it.
2. Copy `ipa_fws.mdt` and `.b00`–`.b04` to
   `/lib/firmware/qcom/sm8150/oneplus/guacamole/`.
3. Keep `ipa.ko`/`rmnet.ko` out of `/lib/modules` so the new DT node cannot
   autoload IPA. After boot, with the modem running, `insmod ipa.ko` by hand
   and capture dmesg, remoteproc state, QRTR services and link list.
4. Pass (plan phase 3): IPA binds, firmware authenticates, the modem
   handshake completes, the data netdev appears, an rmnet link can be created
   and deleted, and modem, Wi-Fi and audio stay healthy through a reboot.
5. Rollback: reboot (nothing autoloads); flash the previous image if the DTB
   itself misbehaves.
