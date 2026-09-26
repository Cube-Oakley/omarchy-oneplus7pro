# GS201 GPU v15 checkpoint

Cumulative kernel patch against `kernel-base.txt`, including the preceding
USB, retained display, ACPM, thermal and CPU work. Apply to the clean base only;
a clean-index apply check passed. Image B2 is the hardware-tested build.

The new genpd provider controls G3D top and cores through the vendor secure PMU
ABI, with ordered clock/register retention and TrustZone save/restore. The RAM
bring-up controls gate activation on machine identity and real temperatures.
Unmodified Panthor starts the pinned arch10.8 firmware at the lowest stock GPU
clock pair (302 MHz top, 202 MHz stacks).

See [the detailed GPU record](../../docs/gpu-bringup-20260925.md).
The archived build helper belongs in the project's scripts directory when used;
its relative paths expect the original pinned BusyBox, firmware and boot inputs.
No flash operation is part of the builder or RAM boot helper.
