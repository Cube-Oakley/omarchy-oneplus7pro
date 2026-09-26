# Cellular baseline: firmware, carrier profiles and modem state — September 22, 2026

Phases 1 and 2 of the [cellular plan](cellular-plan-20260922.md), done without a
SIM. Everything here was read-only: no profile was loaded, selected, activated,
deactivated or deleted, and the modem was not put online. The user has ordered a
Tello SIM (T-Mobile network, physical nano-SIM, voice/SMS/data). Device
identifiers (IMEI and similar) stay in ignored `out/cellular/`.

## Modem firmware

The running build is `MPSS.HE.1.0.c10-00093-SM8150_GEN_PACK-1.505508.2.505991.36`,
variant `sm8150.genmd.prod` (string in `modem.b19`; `verinfo/ver_info.txt` is
stale). The OOS12 H41 and Lineage 23.2 `modem.img` are byte-identical. QMI
reports revision `Q_V1_P14`.

The library holds 242 software MCFG profiles (`mcfg_sw.mbn`).
`scripts/mcfg_inventory.py` parses each one's ELF MCFG segment and `MCFG_TRL`
trailer (name, version, IIN and PLMN lists) into `out/cellular/mcfg-manifest.tsv`.
The layout is observed, not from vendor documentation, and unknown fields are
kept raw. The original extraction truncated long names, so three
`sm8150.{gen,genmd,gennw}.prod` defaults collapsed; which recovered default
belongs to `genmd` is unresolved.

## Modem state without a SIM

Bounded `qmicli` queries (`out/cellular/qmi-readonly-20260922.log`):

| Query | Result |
| --- | --- |
| DMS operating mode | `shutting-down` (the stable pre-online state) |
| UIM card status | both slots `absent` |
| NAS serving system | `not-registered-searching` |
| LTE bands enabled | 1–14, 17–43, 46–49, 66–68, 71, … (includes T-Mobile's 2, 4, 12, 66, 71) |
| Voice | `voice-centric`, voice domain `ps-preferred` |
| WDS 3GPP profiles | default (empty APN), `ims`, `sos` (emergency), `hos` |

The modem, ADSP and Wi-Fi stayed healthy, and no `invalid ipcrouter packet`
messages appeared (earlier qmicli PDC attempts produced two).

## Carrier profiles on the modem

`scripts/phone-pdc-probe.c` is a small libqmi program built on the phone. It
reads the selected software configuration, lists the resident ones and asks each
for its description, version and size. Each step has a 10 s limit and the
process a 90 s watchdog. It does not request the platform list that crashed
qmicli 1.38. Output: `out/cellular/pdc-probe-20260922.log`.

- **Active: `Free-VoLTE`** (Free Mobile, France), version `0x08019a01`, left over
  from the phone's Android use. Nothing is pending.
- **25 resident software configurations**, all European or international:
  Deutsche Telekom variants, Vodafone, Telia, KPN, Proximus, ICE, DNA, Elisa,
  Tele2, ETISALAT, CMHK, Free, Tele_volte, plus `Common-Commercial` and
  `Volte_PTCRB`. **No North American profile is resident.**
- One resident, id `30373037` (ASCII "0707"), answers Get Config Info with
  `InvalidQosId (41)`. That is the error the earlier qmicli run reported.

The PDC configuration ID is the SHA-1 of the whole `.mbn` file.
`scripts/match_mcfg_residents.py` matched all 24 residents that report metadata
to exactly one library file each, with the same name, version and size. Unlike
the related 7T Pro, the residents here come from this firmware's own library.
The `0707` entry matches nothing.

## The profile a T-Mobile SIM needs

Only one library profile covers T-Mobile US, and it is not resident:

| Field | Value |
| --- | --- |
| File | `modem_pr/mcfg/configs/mcfg_sw/generic/NA/TMO/Commercial/mcfg_sw.mbn` |
| Name | `Commercial-TMO`, carrier index 5, on the OEM list |
| Version | `0x08010515` (trailer) |
| Size | 74136 bytes |
| PDC ID (file SHA-1) | `cb45c810b0532a8dd30b8f2324ba6b1967ecd55d` |
| SHA-256 | `e8a58c89618027546f62974286618f7a95b7f22564f42ecbb738bddfc9de4da0` |
| Network evidence | IIN 8901260 and PLMN 310-260 (T-Mobile US); no other profile lists either |

## When the SIM arrives

1. Insert it with the phone running, then reboot through the recovery path.
   SIM hot-insert is untested with this stack.
2. Read-only: UIM card and application state, PIN state and retries, and the
   IIN prefix. Keep ICCID and IMSI in `out/` only. Never guess a PIN.
3. Rerun the PDC probe to see whether the modem selected a profile itself. If
   `Free-VoLTE` is still active, load `Commercial-TMO` by its SHA-1, select and
   activate it on the same subscription, and read back active/pending. Keep
   `Free-VoLTE` resident as the rollback. Do not delete residents.
4. Only then one bounded online transition and a NAS registration check, as the
   plan's phase 4 gate requires.

## Firmware for the data path (IPA)

The IPA firmware is not in the modem image. It is in the Lineage 23.2
`vendor.img` under `/firmware`: `ipa_fws.mdt` (5 segments, SHA-256
`34a2dcc5637a095a9471562a1d363affc7aaadeda1d049164d7454d10511edf8`) with
`ipa_fws.b00`–`b04`, `ipa_fws.elf` and `ipa_uc.*`. It has no readable version
string and has not been compared with a stock OOS vendor image.

## IPA driver port (phase 3, prepared, not deployed)

`devices/oneplus7pro/kernel/radio/ipa/` holds the port and its
[README](../kernel/radio/ipa/README.md). It is six patches
for the running #188 tree:

- hotdog 0144, 0145 and 0147: IPA v4.1 platform data, registers and binding
- two subsets of hotdog 0156: the `ENDP_INIT_CTRL` register, which our endpoint
  code needs below v4.2, and the bounded GSI command wait
- one guacamole correction checked against its downstream `ipa_utils.c`: IMEM
  at `0x146bd000` rather than the sc7180 value, and a fourth destination
  resource group

`build-ipa-module.sh` builds `ipa.ko` and `rmnet.ko` with the running kernel's
vermagic and no errors.

`guacamole-ipa.dts` is a boot-DTB overlay, not a live one: SMP2P entries are read
at probe and reserved memory is fixed at boot. It adds the IPA node (IOMMU
streams `0x520`/`0x522`, SPI 311/432, RPMH IPA clock, the downstream bus paths),
the modem SMP2P `ipa` entries, and moves the IPA carveouts to guacamole's OEM
addresses (`0x99500000`, `0x99510000`) inside the old CDSP span. Merged onto the
DTB read back from the running phone (`/sys/firmware/fdt`), the union of
reserved and of no-map memory is unchanged and nothing overlaps; interconnect
and clock IDs match the kernel's SM8150 headers. Firmware is AP-loaded
(`qcom,gsi-loader = "self"`), as stock does with PAS id 15.

### Result on the phone

This bring-up kernel ignores the bootloader's DTB and boots from a copy embedded
in the Image (`arch/arm64/kernel/embedded_dtb.S`, `.incbin
"bringup-guacamole.dtb"`). A first flash that changed only the boot image's DTB
section therefore booted the old tree unchanged (confirmed from
`/sys/firmware/fdt`). Kernel **#189** is #188 rebuilt with the IPA overlay merged
into `bringup-guacamole.dtb`: same source, config, `utsrelease.h`,
`vmlinux.symvers` and built-in initramfs, so every existing module still loads.
Image: `out/checkpoints/20260922-ipa-kernel189-test/`; flash with
`scripts/flash_ipa_dtb_test.sh [test|rollback]` (rollback is #188).

#189 booted (boot `4c6ec9cc-d758-4843-8397-d4d98cde29f6`) with the IPA node,
the modem SMP2P `ipa` entries and the planned reserved memory. Modem, ADSP,
Wi-Fi (HTTPS 200), audio and the boot-slot mark were as on #188, with no deferred
devices. The firmware was copied to `/lib/firmware/qcom/sm8150/oneplus/guacamole/`
and `ipa.ko` loaded by hand from `/root/radio-bringup/ipa/`:

```
ipa 1e40000.ipa: channel 4 limited to 256 TREs
ipa 1e40000.ipa: limiting IPA memory size to 0x00002800
ipa 1e40000.ipa: IPA driver initialized
ipa 1e40000.ipa: IPA driver setup completed successfully
ipa 1e40000.ipa: unexpected init_completed response
```

`rmnet_ipa0` appeared, which the driver creates only after the QMI handshake
with the modem completes. With `rmnet.ko` loaded, `rmnet_data0` (mux 1) was
created on it and deleted. Afterwards the modem and ADSP were running, Wi-Fi
returned HTTPS 200, PipeWire was up and DMS still reported `shutting-down`.
Logs: `out/cellular/ipa-test/`.

The warning is ordering, not failure: the driver arms its microcontroller
power reference on the modem's power-up notification, so loading it after the
modem is running makes the microcontroller's INIT_COMPLETED unexpected and
leaves `uc_loaded` false. Load `ipa.ko` before the modem starts when this
becomes part of the radio startup. Suspend with IPA loaded is untested.

### Original flash plan

A flash test needs: the unchanged #188 kernel with a DTB carrying the radio
guards plus this overlay (the image builder takes one extra overlay today),
`ipa_fws.mdt`/`.b00`–`.b04` in `/lib/firmware/qcom/sm8150/oneplus/guacamole/`,
and `ipa.ko` loaded by hand after the modem is up. Pass: IPA binds, the
firmware authenticates, the data netdev appears, an rmnet link can be created
and deleted, and modem, Wi-Fi and audio stay healthy. The DTB lives in the boot
image, so rollback is reflashing the saved #188 image through fastboot (the
flash scripts' rollback mode), not a plain reboot. Unverified: TrustZone acceptance at the OEM address, clock
and bandwidth figures (from the reference), `dma-coherent`, and behavior across
suspend and modem restart.
