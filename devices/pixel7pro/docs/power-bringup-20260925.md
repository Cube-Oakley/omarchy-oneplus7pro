# GS201 thermal and CPU scaling — September 25, 2026

Native Linux now has seven thermal zones, three cpufreq policies and three CPU
cooling devices. The standard cpufreq-dt, OPP, clock, thermal and schedutil
frameworks are in use. This is deliberately a bounded frequency profile, not the
full stock operating range or a completed GPU/display pipeline.

## Tested on the phone

- Thermal groups BIG, MID, LITTLE, G3D, ISP, TPU and AUR poll firmware channel 9.
  Sysfs reports temperatures in millidegrees Celsius. The driver retains firmware
  sensor initialization and does not change hardware thresholds or IRQs.
- Board test policy uses 60°C passive CPU cooling and 80°C critical reboot.
  These are conservative bring-up limits, not factory-calibrated product policy.
  Reboot returns to the stock kernel's thermal control; native shutdown/charging
  support is still incomplete. The emergency fallback delay is 3 seconds.
- Software emulation at 55°C appeared in sysfs and clearing it restored the real
  reading. Emulating 85°C caused a reboot at uptime 39 seconds in image A, far
  before its 900-second test timeout. ADB subsequently reported Android booted.
  The serial connection closed before the critical kernel message could be
  captured; this is behavioral reboot evidence, not a retained crash log.
- All 15 configured CPU rates matched fresh ACPM firmware readback.
- At simulated 65°C, step_wise reduced BIG 1106→984 MHz, MID 1197→1024 MHz and
  LITTLE 1197→1098 MHz. Each cooling device entered state 1 and cleared back to
  state 0/its original frequency after removing the emulation. Physical
  temperatures remained about 43°C. No physical overheat test was performed.
- A two-second CPU6 loop produced 622,889,984 iterations at 500 MHz and
  1,377,929,216 at 1106 MHz: a 2.212× ratio. This tests actual execution rate in
  addition to firmware readback; it is not an application performance benchmark.
- schedutil raised CPU6 to 1106 MHz during that workload and returned it to
  500 MHz afterward. An earlier test using `taskset` failed because the RAM
  BusyBox lacks that applet; only the later affinity-setting helper is load proof.

## Frequency scope and dependencies

| Policy | CPUs | Allowed MHz |
|---|---|---|
| policy0 | 0–3 | 738, 930, 1098, 1197 |
| policy4 | 4–5 | 400, 553, 696, 799, 910, 1024, 1197 |
| policy6 | 6–7 | 500, 851, 984, 1106 |

The stock GS201 driver delegates voltage/clock transitions to ACPM. Its
pre/post callbacks make no separate AP-side regulator change. The live stock
DT's MID/BIG→LITTLE minimum-frequency tables require at most 738 MHz for every
MID/BIG operating point listed above, so LITTLE's floor is 738 MHz. The referenced
LITTLE→MIF table is empty in this DT. `cpu-constraints.json` records those exact
tables and the checked bound. Frequencies above the inherited CPU boot rates are
not exposed. Full dynamic constraints, binning/voltage data and a valid energy
model must be handled before expanding the profile.

The firmware query now rejects a nonzero firmware status word. ACPM clocks use
CLK_GET_RATE_NOCACHE so cpuinfo_cur_freq reads firmware, not just a CCF cache.
TMU's temperature byte now matches Google's unsigned vendor ABI, preventing
values above 127 from wrapping negative. High-temperature physical readings
were not tested.

The thermal provider has a standalone binding and uses the existing standardized
`samsung,acpm-ipc` phandle. CPU cooling uses existing CPU phandles patched from
the live DT, and OPP tables are shared per cluster. No proprietary cpufreq driver
or userspace frequency-control loop was introduced.

## Replay and preservation

Image B: `out/checkpoints/20260925-power-v14/image-b/boot-pixel-shell.img`

SHA256: `3a38b75c3be2335e89d72ede9c2328875c91c083504f00ff1f7f043ae563c1e4`

Kernel: `7.3.0-rc2-pixel-power14-g5225b8eec4c9-dirty`; 1200-second RAM timeout.
Image A preserves the earlier thermal-only test with SHA256
`dcc7e91fef439dc89984044c03dcc1570944d9d5d34186bacd670f6bb5cfe031`.

```sh
python scripts/boot-pixel-shell.py \
  --image out/checkpoints/20260925-power-v14/image-b/boot-pixel-shell.img \
  --sha256 3a38b75c3be2335e89d72ede9c2328875c91c083504f00ff1f7f043ae563c1e4
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/activate'
# Verify seven temperatures and critical trips before enabling CPU policies.
python scripts/pixel-shell.py --command 'echo 1 > /sys/module/pixel_acpm/parameters/cpufreq'
```

CPU activation additionally checks that all eight CPUs are online, the seven
thermal zones exist, fresh firmware temperatures are 5–59°C and all three CPU
rates equal the inherited boot rates. Policies start with the userspace governor.
Thermal emulation is enabled solely for validation; clear emul_temp to zero after
any cooling test. Never carry an emulated temperature into ordinary workloads.

`devices/pixel7pro/kernel/power-v14/` preserves the cumulative kernel patch,
config, overlay, build-helper snapshot and base revision. Apply the patch to the
clean pinned base, not on top of earlier native checkpoints. It passed a clean
index apply check. Keep the image/source hashes with any reproduction.

Evidence includes thermal-a.txt, critical-reboot-a.txt, cpufreq-register-b.txt,
frequency-sweep-b.txt, cooling-b.txt, cpu-work-b.txt, cpu-worker.S and results.json.
The source research directory contains pinned Google cpufreq/calibration/TMU
sources from revision b3c9095e01cefb36f35723b5c66638bf15f5144a. The thermal binding
passed dt_binding_check including its example; new thermal/test C passes
checkpatch, and the kernel build has no compiler warnings. The temporary overlay
emits dtc warnings for stock CPU names with leading zeroes and runtime-patched
cooling phandles. The core prints energy-model errors because no validated power
model is supplied; frequency control and state-based cooling still work.

No partitions were flashed, slots changed, or OnePlus files modified. No GPU
rendering or full display scanout is claimed by this checkpoint.
