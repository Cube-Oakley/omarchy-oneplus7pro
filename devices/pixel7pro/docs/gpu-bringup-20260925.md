# GS201 GPU bring-up — September 25, 2026

The v15 B2 RAM image powers and initializes the Pixel 7 Pro's Mali-G710 through
Linux genpd, ACPM clocks and the unmodified upstream Panthor driver. Firmware
starts and `/dev/dri/card1` plus `/dev/dri/renderD128` appear. With a small Mesa
model-table addition, the GPU passes shader/readback tests and renders Hyprland
and the shared mobile desktop. The retained-display bridge remains card0;
this is not yet full Linux ownership of DPU/DSI scanout.

## Tested kernel path

The new `gs201-g3d-pd.c` provider exposes parent top and child cores domains. It
uses the vendor secure PMU write call, rather than writing protected PMU registers
directly. Top-domain collapse saves 48 ordered CMU/SYSREG entries and TrustZone
context. Resume restores both. GPU security configuration uses the same SMC as
the stock GPU power callback. All waits are bounded; firmware errors are logged
and propagated. This is a GS201 GPU-specific provider, not a general GS201 PMU.

The explicit power-cycle test observed both domains off, then both on, with raw
GPU_ID `0xa8620004`. Runtime autosuspend also reaches `suspended`. Do not read GPU
registers while its domain is off. The earlier `gpu-before.txt` label at offset
0x8 says L2_FEATURES incorrectly: that offset is CORE_FEATURES. Panthor's actual
L2_FEATURES reading is `0x08130306`.

The lowest stock clock tuple is **302 MHz top / 202 MHz shader stacks**. The test
requires inherited 151 MHz rates, raises top first, then stacks, and verifies
fresh ACPM readback. One OPP is exposed; this is not complete GPU DVFS, GPU thermal
cooling or a validated energy model. Seven real thermal zones and bounded CPU
schedutil policies from [v14](power-bringup-20260925.md) remain active. The GPU
activation guard requires a fresh 5–59°C G3D temperature.

Panthor identified seven shader cores (`shader_present=0x1110055`), AS mask0xff,
MMU features0x2830 and CSF interface1.5.0. Its firmware git identifier is
`95a25d71030715381f33105394285e1dcc860a65`. The protected-mode-entry warning means
Panthor ignores that unsupported firmware section. The regulator warning is
expected for this firmware-controlled voltage path; probe succeeds. Neither
message establishes shader execution by itself.

## Firmware and source provenance

Firmware comes from the official [linux-firmware revision
930ef9046e3848df688d98b7d5e68154b031dc66](https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware/+/930ef9046e3848df688d98b7d5e68154b031dc66/),
`arm/mali/arch10.8/mali_csffw.bin`, 282624 bytes, SHA256
`a27847ea11f8efb3136340c3ba8aab413ae25145eeb4a7f64ff5edd829a2405b`.
Its redistribution licence is included in the RAM image. Firmware, licence and
WHENCE hashes are recorded in `firmware-source.json` in the kernel checkpoint.

PMU/retention/SMC sequences were checked against the pinned official Google GS201
kernel and GPU revisions listed in [the pipeline record](hardware-pipeline-20260925.md).
Downloaded paths and hashes are in the v15 research `source.json`. The exact
factory build source manifest is still unverified; tested ABI behavior is recorded
separately from source-family matching.

## Mesa investigation

Unmodified Arch Mesa26.2.3 selects llvmpipe even when explicitly given the Panthor
render node. A syscall trace shows successful Panthor device queries, followed by
software fallback before VM creation. The exact official Mesa26.2.3 source lacks
the G710 model entry: `panfrost_open_device()` silently returns when
`pan_get_model()` finds no match. The G610 entry is present. The Pixel GPU has
architecture10.8/product2, variant0, whereas G610 is architecture10.8/product7.

The isolated test patch adds the G710 identity using the G610 shader-core
parameters. Arm documents the shared core throughput in its [Offline Compiler
guide](https://documentation-service.arm.com/static/648aeb7f153eb247a5450a90).
This is an experimental enablement, not a claim of GLES conformance. Patch and
build details live in `devices/pixel7pro/adapter/userspace/mesa/`. The shared Arch archive
and OnePlus source are unchanged. Test libraries install only under
`/opt/pixel-mesa` in the Pixel RAM filesystem.

The offscreen test `mainline/pixel-gpu-render-test.c` rejects llvmpipe, compiles and
submits a GLES2 shader, and checks pixel readback against RGBA64,128,191,255.
A successful EGL context or render-node open alone is insufficient.

## Hardware rendering and integrated session results

The patched Mesa build passed the hardware-only shader test at uptime1076.79s:

```text
GL vendor=Mesa renderer=Mali-G710 MC7 (Panfrost)
version=OpenGL ES 3.1 Mesa 26.2.3
readback RGBA=64,128,191,255 GL_error=0x0
PASS: Mali-G710 shader rendered and pixels verified
```

A later probe first confirmed runtime_status=suspended, then opened display-only
card0. Mesa's existing kmsro path paired it with Panthor and the same shader
passed again. G3D measured38°C. No Mesa display-device-name patch was necessary.

`pixel-gpu-session-start.sh` then started Hyprland, Quickshell, the shared mobile
UI, on-screen keyboard service and Kitty using only the isolated libraries.
Aquamarine explicitly selected card1/renderD128 and logged
`Renderer: Mali-G710 MC7 (Panfrost)`. Its first GLES3.2 context request failed
because this driver exposes GLES3.1; its normal GLES3.0 retry succeeded. The
retained bridge committed frames with zero refresh timeouts in the recorded log.
The native Wayland screenshot `gpu-desktop.png` shows the shared UI and terminal.
The terminal's old “software display” banner is static saved-image text.

The original GPIO touch source was rebuilt against this exact kernel and loaded
for a bounded600s test at uptime1207s. Hyprland enumerated the touchscreen. The user confirmed the physical UI is
**significantly faster**, but still noticeably laggy. The target is smooth120Hz;
this feedback is not an end-to-end latency measurement. At uptime1235s
real zones measured39–47°C. No GPU fault or reset was logged through that capture.
This is a small functional test, not a stability, conformance or performance suite.

Evidence: `shader-patched-mesa.txt`, `shader-kmsro-resume.txt`,
`hyprland-gpu-start.txt`, `hyprland-renderer.txt`, `mobile-gpu-state.txt`,
`touch-gpu-start.txt`, `gpu-desktop.png` and `results.json`.
The isolated Mesa package hash and full build options are preserved in the
[userspace checkpoint](../adapter/userspace/mesa/README.md).

## Image and replay

- Image B2: `out/checkpoints/20260925-gpu-v15/image-b2/boot-pixel-shell.img`.
- SHA256: `25670ed9fddb406888ac931d7f17744e2588a1e7755faecb407174a5cd18cf20`.
- Kernel: `7.3.0-rc2-pixel-gpu15-g5225b8eec4c9-dirty`.
- Automatic reboot: 1800 seconds, to the unchanged stock slot A.
- Source: `devices/pixel7pro/kernel/gpu-v15/`, cumulative patch/config/overlays.
- Base: `5225b8eec4c9bb21aecff6295fab6346a3c3738e`.

The complete patch passed a clean-base index apply check. GPU-domain and GPU
bindings passed schema checks. New provider/test code passed checkpatch. The
kernel build has no compiler warnings. Runtime-applied overlay phandles and the
inherited interrupt parent still produce documented dtc warnings.

```sh
python scripts/boot-pixel-shell.py \
  --image out/checkpoints/20260925-gpu-v15/image-b2/boot-pixel-shell.img \
  --sha256 25670ed9fddb406888ac931d7f17744e2588a1e7755faecb407174a5cd18cf20
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/activate'
# Inspect real temperatures and driver logs before proceeding.
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_gpu/parameters/domains'
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_gpu/parameters/cycle'
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_gpu/parameters/render'
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/cpufreq'
```

Evidence: `power-cycle-a2.txt`, `power-cycle-b2.txt`, `panthor-bind-b2.txt`,
`cpu-enable-b2.txt`, `shader-test-b2.txt` (initial software fallback),
`mesa-strace.txt`, `health-during-build.txt`. Arch restore uses the unchanged
mobile archive SHA256
`9b204df8aff3f54625f347d11d4e1370b44a83aef12e6371d588c8581ba54e57`.
Phone userspace, test keys and network services disappear at reboot. Remove the
session's temporary host NetworkManager profile after the USB session ends.

No partitions were flashed, no slots changed and no OnePlus files modified.
Hardware rendering would still leave real DPU/DSI atomic scanout and standard
SPI/IRQ touch transport as separate unfinished work.

Later [v16 display work](display-pipeline-20260925.md) found that the retained
bridge's channel rotation made software-black pixels appear blue on the panel.
Image C restores the original ABL opaque ARGB byte layout; physical labeled-color
validation now passes. This corrects a display-side issue independently of the
v15 GPU shader/readback results. The immutable v15 image preserves the earlier,
incorrect color layout.
Image D then fixes cached reads of display-owned buffers exported to Panthor;
its identical GPU-write/CPU-read regression changes from all pixels failing to
all passing. Prefer D for ongoing work; C preserves the isolated color correction.
