# Omarchy on OnePlus 7 Pro — progress (2026-09-16 evening)

**Codex update, ~23:05 PDT:** **Eight cores + USB + GPU rendering verified** on
kernel #172 (`codex-smp2`). Each CPU passed a pinned checksum workload; Adreno
passed the shader/pixel-readback test. Frozen checkpoint:
`out/checkpoints/20260916-8cpu-gpu/`. USB startup now waits for controller
registration. See [CPU/GPU work](cpu-gpu-work-20260916.md).

**Codex update, ~22:25 PDT:** Adreno **offscreen shader rendering verified** on
the restored kernel; repaired the hidden render-node path. An early-SMP
eight-core test image is built and awaiting a fastboot test. See
[CPU/GPU work](cpu-gpu-work-20260916.md) for evidence, image, and rollback.
The older progress below describes the state before these tests.

Phone: guacamole / SM8150, serial `$PHONE_SERIAL`. Host gadget: `1d6b:0104`, phone `172.16.42.1`. Hardware reset: Vol Up+Down+Power. START menu = healthy ABL. Do **not** use `/proc/bringup_reboot_bootloader` (900e).

Restored at pause: **wallpaper desktop**
`out/pmos/boot-embed-hypr-pin.img` + `out/dtbo-filtered-gpu-sqe.img`
(Hyprland on leftover simpledrm, 4 little cores, delayed Adreno, swaybg Omarchy wall, cursor hidden.)

---

## Should we do path 2?

**Yes.** Path 1 (GPU as render-only + leftover ABL framebuffer) is a bring-up hack. It got a visible desktop, but it will not give native Omarchy:

- Leftover scanout is ABL’s MDP still scanning `0x9C000000`. Linux does not own DSI, DSC, or the panel. Any DPU/dispcc probe fights that engine (glitch bars, then garbage).
- `hyprpaper` dies on simpledrm (`PRIME export is not supported`). Wallpaper only works via `swaybg` shm.
- Hyprland 0.56 / Aquamarine cannot match an EGL device to simpledrm (`eglQueryDeviceStringEXT`). Compositor is software (llvmpipe) even when Adreno `card1` exists.
- GLES apps (kitty, browsers, Quickshell) need a real KMS CRTC + Freedreno, not a bootloader framebuffer.
- 1440×3120@60 on 4-lane DSI does not fit uncompressed; the panel is **command-mode DSC AMOLED**. ABL already programmed DSC/PPS. Mainline DPU sending raw RGB is the orange/green scanline mess.

Path 2 is DPU + DSI + DSC + a real guacamole panel driver, then Hyprland/Freedreno on that KMS device. That is the actual phone display stack. SM8150 DSC is still ugly upstream (freedesktop drm/msm#24, garbled on SM8150 vs working SDM845), so expect panel init sequences and PPS from downstream DT, not a one-line fix.

---

## What works now (restore image)

| Piece | State |
|---|---|
| USB gadget NCM | `172.16.42.1`, host-initiated `nc :23` shell |
| CPUs | 0–3 little only. Gold cores: 32-bit EL1 mismatch / RCU stall |
| GPU | Adreno 640 delayed ~90s, `msm.separate_gpu_kms=1`, `card1`/`renderD128`, SQE `a630_sqe.fw`, GMU `a640_gmu.bin` |
| Scanout | ABL leftover simpledrm `card0` Unknown-1 1440×3120 |
| Desktop | Hyprland 0.56 Lua, `AQ_DRM_DEVICES=/dev/dri/card0`, `swaybg` + `/usr/share/hypr/wall0.png` |
| Touch | not in DT |
| Clock | 1970 (no RTC) — Hyprland splash year |

---

## What we proved on DPU (not on the restore image)

DPU **does** come up if delayed until USB+Hyprland exist (~120s after late_init):

1. Drop USB QMP PHY clocks from `dispcc` or fw_devlink parks probe forever.
2. Mark DSI PHY + DSI ctrl `status=okay` **before** creating MDSS, or DPU `component_master_add_with_match(NULL)` Oopses.
3. msm DSI only `component_add`s when a MIPI **panel** attaches → stub `oneplus,guacamole-panel` in `panel-simple` (cmd, 4-lane, 1440×3120).
4. `dsi_tx_buf_alloc_6g` GEM IOVA Oopses on KMS-only VM → use `dma_alloc_coherent`.
5. msm fbdev probe same GEM Oops → skip `msm_fbdev_driver_fbdev_probe`.
6. KMS-only driver lacked `DRIVER_GEM_GPUVA` → uninitialized gpuva list, `get_vma_locked` Oops on SETCRTC. **Fix: add `DRIVER_GEM_GPUVA` to `DRIVER_FEATURES_KMS`.**
7. **Do not** `iommu_group_add_device` DPU onto MDSS group → **900e**.
8. After GEM_GPUVA: `dsi-fill` SETCRTC **succeeded** (`1440x3120 fb=91`, **DSI-1 enabled**, 0 Oops).
9. Panel still showed leftover wallpaper + glitch bars (two scanout engines).
10. Halted INTF_1 timing engine (already **0x0** — cmd mode, not video) and painted leftover FB green. User: **top-half orange/green glitch lines, wallpaper gone**. That is uncompressed DPU RGB into a DSC cmd-mode panel, leftover content gone.

DPU hw rev **0x50000001**. IOMMU: DPU `mapped=0`, MDSS `mapped=1`.

---

## Frozen images

| File | What |
|---|---|
| `out/pmos/boot-embed-hypr-pin.img` + `out/dtbo-filtered-gpu-sqe.img` | **Restore now.** Wallpaper desktop. |
| `out/pmos/boot-embed-4cpu-hypr.img` + `out/dtbo-filtered-4cpu-hypr.img` | Older 4cpu Hyprland, no delayed GPU |
| `out/pmos/boot-embed-gpu-sqe.img` + `out/dtbo-filtered-gpu-sqe.img` | GPU DRM, frozen logo (Aquamarine picked card1) |
| `out/pmos/boot-embed-dpu.img` + `out/dtbo-filtered-dpu.img` | Latest DPU experiment (halt leftover + magenta fill) |

---

## Next work (path 2)

1. Real guacamole panel driver from downstream DT (init + PPS), not `panel-simple` stub.
2. DSC 1.1/1.2 on DPU (`dsc_0`/`dsc_1` in `dpu_5_0_sm8150.h`) + DSI cmd mode. Compare PPS to OOS/Lineage.
3. Keep leftover scanout until DSC actually paints; do not SETCRTC raw RGB onto the AMOLED.
4. Then Hyprland `AQ_DRM_DEVICES=/dev/dri/card2` + Freedreno `renderD128` (GPU card1).
5. Gold CPUs still blocked (32-bit EL1). Touch later (s6sy761 / QUP).

Kernel tree: `.work/linux-sm8150`. Bring-up: `arch/arm64/kernel/bringup_usb.c`. DTS: `arch/arm64/boot/dts/qcom/sm8150-oneplus-guacamole.dts`. Stub panel: `drivers/gpu/drm/panel/panel-simple.c` (`oneplus,guacamole-panel`).

Host shell: `nc 172.16.42.1 23` (host-initiated). Phone wget outbound still fails.
