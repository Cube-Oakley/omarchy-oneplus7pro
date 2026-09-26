# GS201 CPU/thermal v14 checkpoint

Hardware-tested seven thermal zones, bounded three-cluster cpufreq, thermal
cooling and schedutil. See [the detailed record](../../docs/power-bringup-20260925.md).

The patch is cumulative against kernel-base.txt and includes prior native
USB/display/ACPM bring-up. Apply to that clean base only. Config and overlay are
from image B. The build helper copy is archival: use it from the project's
scripts directory with the documented pinned BusyBox and boot-image inputs.

The CPU profile deliberately excludes higher stock frequencies. GPU/rendering,
full KMS, charging and a validated energy model remain separate work.
