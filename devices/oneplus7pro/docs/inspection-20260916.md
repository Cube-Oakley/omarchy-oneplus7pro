# Live inspection — 2026-09-16 (Codex)

Read-only inspection over USB NCM, `172.16.42.1:23`. No phone settings,
CPU hotplug state, device nodes, or flash partitions changed.

## Confirmed running state

- Kernel `6.17.0-sm8150-g379d8fe35c7c-dirty`, build **#159**, Sep 16 15:28:10 PDT.
  Matches the documented restored Hyprland image, rather than the later DPU
  experiment currently present in the source tree.
- Arch Linux ARM persists on ext4 `/dev/sda19`, mounted at `/newroot`.
  PID 1 remains the BusyBox initramfs script; Arch programs run in a chroot.
- CPUs possible/present: `0-7`; online: `0-3`; offline: `4-7`.
- USB host interface `enp198s0f0u2`, `172.16.42.2/24`; gadget `1d6b:0104`.
- Hyprland, seatd, swaybg, and Xwayland are running. Display connector
  `card0-Unknown-1` is enabled at 1440x3120 through simpledrm.
- Adreno registers `card1` around 125.6 seconds into boot. No DPU card2.

## Confirmed render-device path bug

The live init creates `/dev/dri/renderD128 -> card0` before launching Hyprland.
This symlink remains after the GPU registers:

| Record | Actual device |
| --- | --- |
| `/sys/class/drm/renderD128/dev` | `226:128`, Adreno at `2c00000.gpu` |
| `/dev/dri/renderD128` | Symlink to `card0`, device `226:0`, simpledrm |

Programs opening the usual render-node path therefore reach the framebuffer,
not Adreno. This must be addressed before interpreting GPU userspace tests.
The launcher also explicitly forces `llvmpipe`, `kms_swrast`, and
`LIBGL_ALWAYS_SOFTWARE=1`. Aquamarine reports no matching EGL device; Xwayland
reports llvmpipe and disables glamor.

GPU firmware files exist, but this boot's captured dmesg does not show SQE/GMU
firmware loading or a successful GPU rendering workload. DRM registration alone
does not establish working hardware acceleration. The older notes' successful
firmware-load observations came from other boots.

Next graphics test: expose the correct render device in a controlled way and
test offscreen GPU rendering separately from compositor/panel modesetting.
The real DSI/DSC panel work remains a separate, unvalidated path on this boot.

## CPU hypothesis to test

The local patch in `kernel/smp.c` sets `setup_max_cpus = 0`; the arm64 SMP
patch keeps secondaries present for later hotplug. The live log confirms that
only CPU0 participates in initial SMP bring-up and that `32-bit EL1 Support`
is detected before CPUs 1-3 are started by init. Live `CONFIG_KVM=y`.

In this source, `arch/arm64/kernel/cpufeature.c` defines that EL1 capability
under CONFIG_KVM and verifies later CPUs against finalized system capabilities.
Its comments explicitly describe parking a later CPU that lacks an enabled
capability. This is a plausible explanation for the historical CPU4-7 mismatch:
initializing system features from CPU0 alone can make the later heterogeneous
cores incompatible with the established feature set.

This is a source-and-log-based hypothesis, not a reproduced CPU4 failure during
this inspection. Investigate restoring normal early SMP feature discovery;
disabling KVM is a narrower possible diagnostic for this particular check,
but would not resolve other capabilities finalized from CPU0 alone. Do not
bypass capability checks or repeat the recorded forced-hotplug stall blindly.

## Captured evidence

Local logs (under gitignored `out/`):

- `codex-live-inspection-20260916.log`: mounts, CPU state, device nodes, full dmesg.
- `codex-live-details-20260916.log`: build identity, DRM sysfs records, live kernel
  config subset, init and launcher, installed graphics package versions.
- `codex-compositor-inspection-20260916.log`: Hyprland and Xwayland logs, recent dmesg.

The first capture used unqualified `tail`, which is absent in the initramfs;
the final capture explicitly used `busybox tail` and obtained those logs.
