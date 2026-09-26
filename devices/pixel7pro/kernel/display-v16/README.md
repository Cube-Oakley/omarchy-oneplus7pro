# GS201 display diagnostics v16

The `image-a` checkpoint preserves the first timing-only build. Its cumulative
patch applies to the pinned clean kernel base; do not apply it on top of v15.
The saved builder expects the project layout and pinned firmware/BusyBox inputs.

`image-b` adds display-idle diagnostics and an opt-in pre-copy wait. `image-c`
defaults that wait on and restores the retained ABL opaque ARGB byte layout,
with an explicit `legacy_bgra` diagnostic switch for reproducing the earlier
channel rotation. Each directory is a standalone cumulative source checkpoint.

`image-d` adds a standard shmem write-combined allocation hook for display-owned
buffers exported to the non-coherent GPU. Image C's CPU-only motion test is
physically clean, while a small GPU-write/CPU-read regression fails. Image D is
the corresponding cache-coherency correction: the same regression now passes,
and the user confirms clean GPU-animation edges with no trails. Frame-rate and
occasional-pause limitations remain. See the detailed record for measurements.

See [measurements and limitations](../../docs/display-pipeline-20260925.md).
This is still a retained-buffer bridge, not a complete DPU/DSI driver or 120 Hz
support. Earlier CPU/thermal and GPU implementations are included unchanged.
