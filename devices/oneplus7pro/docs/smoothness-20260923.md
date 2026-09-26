# Smoothness: CPU and GPU frequency scaling — September 23, 2026

Question from the user: can this 2019 phone be smooth at 90 Hz? The first
finding was that the software had the brakes on.

## CPU frequency scaling was off

`qcom-cpufreq-hw` is built in (`schedutil` is the default governor) and every
CPU node already points at the OSM node `cpufreq@18323000`, but the embedded
boot DTB disables that node. It was switched off during the minimal bring-up
together with UFS, GPU, SPMI, Wi-Fi and others, all since re-enabled; no
failure was ever recorded against it. Without it there were no cpufreq
policies, each core stayed at its boot clock, and the CPU thermal zones had no
cooling devices at all.

`guacamole_cpufreq.ko` (`devices/oneplus7pro/kernel/power/guacamole-cpufreq.dts`,
`scripts/build_cpufreq_overlay.sh`) enables the node at runtime:

| Policy | CPUs | Range |
| --- | --- | --- |
| policy0 | 0–3 (A55) | 300 MHz – 1.79 GHz |
| policy4 | 4–6 (A76) | 710 MHz – 2.42 GHz |
| policy7 | 7 (A76 prime) | 826 MHz – 2.84 GHz |

The energy model created a performance domain per cluster (energy-aware
scheduling), and three CPU cooling devices joined the GPU's. A single-threaded
Python loop, pinned per core:

| Core | Before | After |
| --- | --- | --- |
| cpu0 | 3.96 s | 3.73 s |
| cpu4 | 2.64 s | 0.75 s |
| cpu7 | 2.44 s | 0.71 s |

The big and prime cores had been sitting near their minimum clocks: 3.5x
faster now. The little cluster reaches 1.79 GHz under load; it had booted close
to it. No cooling device was throttling, CPUs stayed at 36–38 °C, and the
modem stayed up. The desktop hook loads the module at boot when
`/root/power-bringup/cpufreq-enabled` exists (set on the phone); the next boot
DTB can simply leave the node enabled.

## GPU frequency scaling works

The Adreno 640 scales with `simple_ondemand` over 257–585 MHz, its full range,
and spends real time at 585 MHz. (The GMU's delayed platform-device creation
logs "create failed", but the GPU renders and scales.)

## Presentation timing

The broken vsync throttling measured on September 17 (Qt fell back to
timer-driven animation, [display performance](display-performance-20260917.md))
predates the native DPU/DSI pipeline. Now the shell's GL contexts use
`swapInterval 1` without warnings, and Hyprland drives the panel at exactly
60.000 Hz.

## 90 Hz

The panel is a Samsung S6E3HC2 in DSI command mode with DSC, the same
controller as the 7T Pro's; our driver came from that port. Stock (LineageOS
23.2 `dsi-panel-samsung_oneplus_dsc.dtsi`) keeps two WQHD timings: 60 Hz with
vertical porches 400/28/1156, and 90 Hz with 4/4/8. Everything else is the
same, including the DSC stream, because 1472 x 4704 x 60 = 1472 x 3136 x 90:
the pixel clock and DSI link rate do not change. The only panel command that
differs is control-display `0x53`: `0x20` at 60 Hz, `0x30` at 90 Hz.

`devices/oneplus7pro/kernel/display/panel-60-90hz.patch` offers both modes
(the 7T Pro's approach, 0028): 60 Hz stays preferred, and the on-sequence picks
the `0x53` byte from the mode being enabled. A refresh change is a full modeset
with a brief blank; stock's seamless switch is not implemented. Stock also
swaps gamma tables per rate (read from panel OTP at boot); we write neither, so
colour at 90 Hz may differ slightly.

**Kernel #191** (`scripts/build_kernel191.sh`, flashed with
`scripts/flash_kernel191.sh`, rollback #190) is #190 plus that patch and the
cpufreq node enabled in the boot DTB, which retires the runtime overlay (the
desktop hook now skips it when policies exist). Boot
`#191`: CPU policies from the DTB, both modes offered
(`availableModes: 1440x3120@60.00Hz 1440x3120@90.00Hz`).

Hyprland takes 90 Hz through the board's `device.json` (`"displayMode":
"1440x3120@90"`, validated by `overlay/mobile/theme.py`), or live with
`hyprctl eval 'hl.monitor({output="",mode="1440x3120@90",position="auto",scale=3})'`
(`hyprctl keyword` is refused under the Lua config). Measured with
`DRM_IOCTL_WAIT_VBLANK` over 180 frames:

```
180 vblanks (180 sequence steps) in 2.005 s -> 89.78 Hz; median 11.13 ms, p95 11.87 ms, max 12.10 ms
```

No refresh was missed, so the tighter transfer margin at our 867 Mbps per lane
(about 10.4 ms of the 11.1 ms frame, where stock ran 1.1 Gbps) holds.

## Radio startup and UFS device names

The first #191 boot left the modem offline: the radio startup refused with
`Unexpected label: /dev/sdf2`. UFS LUNs get their `sdX` names in
probe-completion order, and with full boot clocks LUN 2 finished last, so the
modem's LUN 5 became `sde`. The label check correctly refused the wrong
partition. `scripts/phone-radio-test.sh` now finds `modemst1/2`, `fsg`, `fsc`
and the OEM backups by GPT name (exactly one match each) and still verifies
the label; a rerun brought up the modem, Wi-Fi, audio and Bluetooth.

## App switcher

At 90 Hz the user found the shell smoother, but opening the switcher still
stuttered, and a swipe up paused for 50–100 ms before the app followed the
finger. They compared it against a Pixel 9 Pro Fold, which tracks the finger
from the first frame. The fixes are all in `overlay/mobile/WorkspaceOverview.qml`
and `shell.qml`.

**Thumbnail cost.** Every card copied its window live, at full resolution, from
the moment the opening animation started. Now the current app's card starts
at once, the others once the zoom-out has nearly landed, and each card stops
copying 264 ms after its first real frame, like Android's thumbnails. Over 4 s
with the switcher open and three apps:

| | Before | After |
| --- | --- | --- |
| Shell CPU | 1.45 CPU-s | about 0.22 CPU-s |
| Hyprland CPU | 0.47 CPU-s | about 0.07 CPU-s |
| GPU time at 585 MHz | about 3.8 s | about 0.95 s |

**Pause at the start of a swipe.** When the finger went down, the front card
had no picture: its copy only started when the switcher became active, and
the card stayed hidden for another 64 ms because the first captured frame is
often black. Nothing moved until then. The shell now keeps a recent copy of
the screen, taken every 0.7 s while an app is in front and nothing covers it,
and the front card crops its window out of that copy, so it follows the
finger from the first frame. Its own fresh copy replaces the crop about
100 ms later. It copies the screen rather than the window because closing a
window while it is being copied kills the shell, and an app can close itself
at any time. The copy view is created a second after startup: one created with
the shell had no window to set up its buffers and never captured. The user:
"significantly better now, like a lot lot better".

**Cost of the copies.** Each copy wakes the GPU. With an app in front, copying
every 0.7 s, the shell used about 0.15 CPU-s more per 10 s, and the GPU was
awake about 15% of the time instead of 2.5%. Copies now stop 2 s after the
last touch or key (ext-idle-notify through `IdleMonitor`), after one final
copy. Untouched for 10 s: no copies, with the shell's CPU and the GPU's time
the same as without the feature. A copy is also taken 0.35 s after the front
app changes or the switcher, shade or screen-off animation goes away. A card
may start from a frame up to 2 s old (the app kept changing without input) and
then switch to its fresh copy.

**Opening a different app flashed.** Tapping a card first moved that app to
the front of the recent-use order, then started the expand. The reorder
rebuilt every card (logged: both cards created 2–4 ms after the tap), so the
expanding card lost its picture mid-animation and could change position.
Picking the app that was already in front changed nothing, which is why only
other apps flashed. The expand now starts first, and the reorder waits until
the real window is showing (logged: cards rebuilt 280 ms after the tap, after
the reveal). A card tapped while off to the side also grew in place and then
jumped to the window; it now slides to the middle as it grows.

The user confirmed the flash was gone.

## Intermittent pause while the switcher opens

Next the user noticed an occasional pause partway through opening the
switcher, more often when closing and reopening it quickly. A debug build
logged every frame over 16 ms from a `FrameAnimation`, with test hooks that
replay the swipe-and-hold and a tap on the front card (not committed). It found
three causes.

**No screen copy after a quick reopen.** Closing the switcher discarded the
copy and took a new one 0.35 s later, so a reopen within about half a second
found none (`rects=0` in the log) and fell back to the slow start. A window's
copy is now kept while the window is still in front at the same position and
size. Ten open/close cycles 0.3–2.5 s apart all found one.

**The status probe.** Every 3 s the shell ran `omarchy-mobile-stats`, a Python
snapshot of CPU, memory, thermals and processes. Holding the switcher open
showed 30–77 ms stalls about 3 s apart. The same script with its output
discarded caused none, and neither did a lowered priority, `nice -n 19`. The
stall came from the result: each new snapshot rebuilt the rows of the shade's
performance page (cores, temperatures, processes) even with the shade
closed, about 60 ms of main-thread work. The snapshot now runs only while that
page is open (`StatusProbe.active`), and its rows only exist then. The status
bar's CPU and memory bars read `/proc/stat` and `/proc/meminfo` through
`FileView` every 3 s instead, with no process. The script had also cost about
0.1 CPU-s every 3 s.

**The theme poll.** The shell, the Settings app and each mobile app ran
`omarchy-mobile-theme sync`, about 0.2 CPU-s of Python, every 3 s. That was
roughly 13% of a core with the shell and Settings open. Each result was
applied as a new object, so every themed binding re-evaluated. The palette is
now applied only when it changed, and `MobileTheme` watches `palette.json`, so
a theme picked in Settings reaches the shell at once. The sync still runs
every 30 s to catch changes made outside the shell, such as `omarchy theme
set` in a terminal.

**Hot reloads left old copies running.** Each hot reload during this work left
the previous copy's timers and probes running inside the shell, and the shell
used for testing had about 20. A clean restart ran the stats script zero times
in 30 s, where the reloaded shell ran it every 5 s. Killing the shell also
leaves its `nmcli`, `dbus-monitor` and `udevadm` monitors orphaned.
`scripts/phone-shell-restart.py` restarts it with the same environment and
stops those helpers; measurements now use a fresh shell.

On a clean debug shell after these fixes: four 6 s holds had one 20 ms frame
between them, and ten quick open/close cycles had no slow frame while
opening. Two 18–30 ms frames came just after an opening, and one 29 ms frame
at the end of an app's expand. Idle system CPU with an app in front went from
4.1% to 2.3% of all cores; the Settings app still ran the old theme poll until
its next start.

## Next

- The user's verdict on the switcher after these fixes.
- The user's verdict on colour at 90 Hz; per-rate gamma if needed.
