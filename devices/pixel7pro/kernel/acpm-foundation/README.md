# GS201 ACPM foundation — source checkpoint

Apply the numbered patches in order to the project's pinned Linux base plus its
existing native bring-up patch. The working tree already contains these changes.
Do not apply them twice.

These extend standard Linux mailbox, firmware and clock drivers, based on verified
GS201 vendor register/ABI tables. They are compile checked, **not phone tested**.
No DT node, cpufreq policy, GPU domain or boot image is enabled by these patches.

See [hardware pipeline notes](../../docs/hardware-pipeline-20260925.md) for
provenance, validation, missing CMU/DT dependencies and runtime acceptance gates.

This is the historical first increment. The later [v13 checkpoint](../acpm-v13/README.md)
adds real CMU/DT support and firmware channel checks, and is hardware tested.
