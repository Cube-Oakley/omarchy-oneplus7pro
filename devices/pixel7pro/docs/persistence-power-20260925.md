# Pixel persistence and power button — September 25, 2026

Active implementation after consolidation into `omarchy-mobile`. The immediate
objectives are persistent native Arch Linux and power-button screen sleep/wake,
including the same CRT close/open animation used by the OnePlus shared shell.

## Verified starting point

Android ADB reappeared after restarting the host server. Root access, `cheetah`,
stock build AP4A.250205.002 and active slot A were checked. Battery was 100%,
23.8°C. Local evidence is in `out/checkpoints/20260925-persistence-power/`;
raw device inventories and downloaded vendor sources remain ignored.

Stock input exposes `s2mpg12-power-keys` separately from the volume GPIO keys.
The stock device tree routes PMIC requests through ACPM channel 2. Google's
pinned GS kernel `b3c9095e01cefb36f35723b5c66638bf15f5144a` defines PM bank 1,
STATUS1 register 0x0a, PWRON bit 0, and PMIC bus 0. This is not the GS101 GPIO
power-key wiring. The initial module polls that non-destructive status register
and emits standard `KEY_POWER` events; interrupt wake from CPU suspend remains
separate work. It does not read interrupt-clear registers or alter PMIC settings.

Stock UFS exposes the main logical unit with `super` and `userdata`, plus separate
bootloader logical units. Userdata is mounted through device mapper and Android
inline encryption; it cannot simply be mounted as a Linux root. The mainline
Exynos UFS driver supports GS101 but does not yet match GS201. Storage work starts
with the actual GS201 register/PHY/clock configuration and read-only validation,
not relabeling GS201 as GS101. Preserve calibration and identity partitions.

## Installation decision

The user explicitly authorizes replacing Android and its userdata: this handset
is dedicated to the Linux project and contains no important Android data. Use
userdata for the native Linux root once UFS is validated. Preserve bootloader,
calibration/identity partitions and verified host recovery images. There is no
requirement to retain a bootable Android installation.

## Implementation in progress

- `kernel/powerkey/pixel-powerkey.c`: read-only ACPM polling input driver with
  two-sample debounce and bounded transport-failure handling. Compiled for v19.
- V19 image A: DRM disable sends DCS display-off after idle DMA, 60 Hz restore and
  bandwidth release; enable restores mode and sends display-on. Power-mode
  readback verifies the display-enable bit. It retains panel rails/PHY/DSC state;
  this is screen blanking, not deep suspend or full rail power-off.
- Shared `hypr-mobile.lua`, `power-button.py`, `display-power.sh` and `CrtPower.qml`
  own key policy and CRT sequencing. No separate Pixel animation is needed.
- V19 B has physical confirmation of clean screen off/on and CRT transitions.
  Persistent install is in progress; no partition has yet been written.

V19 image A SHA256:
`6222d912f52202059f07936d000e6f2bd30ed30832b9844125438476ebb70ee3`.
The kernel compiled without warnings and boots in RAM with all seven thermal
zones reading 29–32°C after ACPM activation. Its automatic reboot is 1800 seconds.

## Acceptance

1. Physical presses and releases reach the standard Linux input device exactly
   once per action; unloading/reloading and transport failure leave no stuck key.
2. The shared CRT close finishes before panel-off; wake restores the panel and
   plays the opening animation. Repeat with the actual key, check DRM counters,
   USB access and thermal state, and obtain physical confirmation.
3. UFS reads match stock reference data before any root-filesystem writes.
4. Install into an explicitly chosen storage layout, verify writes by readback,
   and demonstrate file and configuration persistence over independent boots.
5. Update the checkpoint and plan site using measured results. Keep CPU suspend,
   wake IRQs, panel rail power-off and charging distinct from screen blanking.

## First physical test

V19 A passes native 60/120 Hz scanout and DCS display-power readback (off 0x99,
on 0x9f). The power-key driver logs real presses/releases. The first user test
had no effect because the launcher triggered only DRM udev discovery; the key
was absent from Hyprland. Triggering input discovery fixes this; the launcher now
does both. The user then confirms sleep and wake, but sees console text flash
on both transitions. DRM disable was restoring the old boot framebuffer before
blanking. Image B keeps the compositor's final frame and pins its DMA buffer
across DPMS, replacing it only after a completed new transfer. B is being built.

Initial UFS probe brings the link up, but NOP OUT times out before any block
device appears. The standard core allocated the transfer list above 4 GiB despite
the platform's initial mask. A follow-up variant explicitly limits DMA to 32 bits;
this hypothesis is not yet verified. No filesystem or partition write occurred.

## Clean CRT transition confirmed

The user confirms v19 B closes and wakes cleanly, without console text. Physical
key events drive the shared shell, DCS reads verify panel off/on, and the display
has zero recorded transfer failures or underruns. **Only the screen sleeps:**
the CPU remains awake, the key uses polling, and there is no suspend adapter.
The panel's rails/PHY stay powered; display updates stop and the additional
120 Hz memory-bandwidth floor is released while blanked.

Kernel patch/config are saved in `kernel/panel-v19/`; input source is in
`kernel/powerkey/`. The shared power-button tests pass (11 tests).

The UFS DMA limit and uncached-allocation tests alone did not fix NOP OUT.
GS201's vendor initialization also sets standard UniPro device/connection
attributes. Readback found CPort connection state 0; configuring that connection
makes NOP complete. Device-initialization query responses are the next issue.
The read-only SYSREG_HSI2 IOCC result is 0x13, confirming read/write coherency
bits set in the retained handoff. No block device has yet been verified.

## UFS read validation

Coherent DMA plus the CPort settings resolves the management responses. The
32-bit DMA hypothesis was wrong: SCSI buffers can be above 4 GiB, and the
controller advertises 64-bit addressing. Restoring that mask enumerates all
four UFS logical units and the expected GPT partitions. Full SHA256 reads match:

- `boot_a`: `6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10`
- `init_boot_a`: `7e3f27da39717be9170ef982aa0bebf0e2806a66650520ad562843a1dc6a0117`

Userdata is `sda31`, 245977141248 bytes. The driver stays at PWM gear 1 initially;
reads are slow. V19 C removes the automatic test reboot timer for installation.
A separate persistent bootstrap will mount only an ext4 root with the expected
layout and installation marker, start the existing desktop automatically, and
retain the RAM USB recovery shell. It never formats a filesystem during boot.

A fresh C boot shows that the earlier successful diagnostic sequence does not
yet reproduce with 64-bit descriptor allocations: query responses fail. The
next candidate separates low-4-GiB coherent command descriptors from 64-bit
file-data buffers. A PWM gear 4 experiment reaches device initialization but
then produces link errors; it is rejected for installation. No storage writes
have occurred. Image E tests the corrected allocation policy at PWM gear 1
from a fresh boot, with the persistent bootstrap included.

## Automatic UFS discovery in image F

The first query failure is tied to the inherited controller state: a complete
failed-probe teardown and one immediate reinitialization succeeds. Image F
bounds that recovery to one retry, never retries a bound controller, and retains
all layout/doorbell checks. Fresh RAM boot enumerates every logical unit and
partition by 1.1 seconds. The bootstrap then refuses the encrypted Android
userdata as expected, leaving USB recovery available. PWM gear changes were
removed; the driver uses the original startup speed.

Image F SHA256:
`6f03b908269c086b8e9be66bc196518e11d983225fbc01235ef40039fa154a8c`.
No automatic reboot timer. The next step is the guarded userdata installer,
including boot-image hashes and an unmount/remount write-readback check before
the Arch copy. No filesystem has yet been formatted.

## Filesystem installation started

Image F's guarded installer reread both boot partitions and matched the saved
hashes. The authorized Android userdata replacement is now performed: `sda31`
is ext4, label `omarchy-root`, with the original partition table unchanged. A
16 MiB random-file write passed SHA256 readback after unmount/remount. The
prepared 2.5 GiB Arch root is being copied; persistent desktop boot and boot-slot
installation remain pending. The marker is written only after a complete copy.

The unused generic `linux-aarch64` and `linux-firmware` packages were removed
from the staging root through pacman; the pinned Pixel Mali firmware is retained.
This avoids copying about 1.4 GiB of unrelated kernel/firmware files. UFS remains
at PWM gear 1 and is slow. The first installer preflight stopped on an unrelated
udev queue timeout without writing; it now validates the three required GPT
partition names directly through sysfs.

Android userdata is gone. Do not treat a normal reboot into the still-stock
`boot_a` as a recovery path during installation. Recovery is the verified
bootloader plus saved host images; slot B is not a fallback. Calibration, identity
and bootloader partitions are preserved.

The earlier descriptor-address hypothesis remains unproven: both allocation
policies failed on the first inherited probe. The working driver conservatively
keeps descriptors below 4 GiB, permits 64-bit data buffers, and performs the
bounded failed-probe recovery. It still needs full GS201 PHY/clock ownership.

## Sparse root installation and recovery

The native PWM gear 1 copy was too slow for the 2.5 GiB root. A complete snapshot
of the prepared RAM root was saved on the host, with the latest startup scripts,
then populated into an ext4 image matching the exact userdata geometry. Host
`e2fsck -fn`, file contents, permissions and sparse chunk sizes were checked.
More than 98% of the expanded image is unused space that fastboot skips.

The incomplete on-device copy was stopped and deliberately discarded. A forced
reboot skipped flushing that disposable copy; the complete root remained saved
on the host. The experimental PMU bootloader selector reached Android recovery
instead. Recovery displayed the Android data-corruption message because userdata
was now Linux ext4. Recovery ADB successfully returned the phone to the bootloader.
Do **not** choose Factory reset: it would erase the Linux filesystem.

`flash-pixel-root.py` checked the unlocked cheetah, successful active slot A,
userdata geometry and image checksum, then flashed only userdata in 20 sparse
chunks. All chunks succeeded in 72.7 seconds. No partition table, calibration,
identity, bootloader or boot partition was changed by this operation.

Sparse image SHA256:
`7ef443b2cc04712204c3becc16e9a3ece5c196877680988b1bbb9eded1a30efb`.
Image G RAM boot SHA256:
`eefa70189bf032f68d821bf9a1695229b15f0a20d2b0ffcbfbc0a4d35d80d42a`.
Kernel ELF build ID: `1edf1b92a5f315ef6d9436b549509d327e339651`.
G has no automatic reboot timeout. Persistent desktop validation precedes any
boot-slot installation. Root archives, images and SSH material remain local.

## Installation tooling

These helpers target only the inspected 256 GB cheetah layout; they are not a
general installer for other Pixels or capacities. Paths below are relative to
`devices/pixel7pro/`. Keep the serial in ignored `out/device.serial`.

- `scripts/build-pixel-root-image.py --archive <prepared-root.tar> --output <new-dir>`
  builds the full-geometry ext4 image, checks it and emits the sparse image plus
  a checksum/geometry manifest. The input is a prepared, tested Arch snapshot,
  not an arbitrary distribution archive. Output includes private SSH material.
- `scripts/flash-pixel-root.py --image-dir <new-dir>` checks the image and
  fastboot target without writing. `--replace-android-data` explicitly enables
  the userdata write; it leaves the bootloader active and does not switch slots.
- RAM-boot the exact persistent kernel using `scripts/boot-pixel-shell.py` with
  its explicit image path and SHA256. Validate the mounted root, desktop,
  thermals and physical controls before proceeding.
- `scripts/install-pixel-boot.py --image <boot.img> --sha256 <sha256>
  --kernel-build-id <kernel-build-id.txt> --ssh-wrapper <trusted-local-wrapper>`
  performs a read-only preflight, including the running kernel's GNU build ID,
  root marker, partition geometry, desktop processes and original boot hash.
  `--replace-android-boot` enables a write to **boot_a only**, followed by a
  direct-I/O SHA256 readback. It never reboots automatically. Preserve the saved
  factory boot image and recovery route before enabling this step.

The bootstrap retains a RAM recovery PID1 and runs the native Arch desktop in
the mounted ext4 root. It is not yet a systemd service boot. For orderly restart,
signal this PID1 (`kill -TERM 1` from recovery): it stops writers, syncs and
remounts the persistent root read-only before rebooting. Do not use forced
reboot during ordinary use. The bootloader mode selector remains experimental.

Initial cold startup exposed slow library/font reads at PWM gear 1. The desktop
launcher permits longer shader/compositor startup and the session tolerates a
failed temporary touch probe while retaining USB recovery. Until RTC support is
available, session startup uses the root marker/previous boot-log timestamp as
a clock floor; this does not provide accurate offline wall time.

## First desktop from installed storage

Image G mounted ext4 userdata automatically and read the saved proof file back.
The GPU shader test passed. Cold library reads and Pango/fontconfig discovery
made the first desktop take about ten minutes; the 243 MiB font directory was
being scanned and caches written, rather than the compositor having crashed.

The first session began with a 1970 clock. Setting host time after Hyprland had
started left its shell layers at alpha 0, despite mapped shell windows and a
visible Kitty window in a captured frame. After restarting the desktop with
the corrected clock and warm caches, all shared layers reported alpha 1,
configuration errors were empty, the keyboard/terminal ran and scanout remained
120 Hz with zero transfer failures/underruns. Clock setup now precedes desktop
startup, using the conservative floor described above.

Updating the running Bash startup file in place also interrupted its final
logging step. The complete saved script passed syntax and checksum checks; the
desktop launcher was rerun successfully and then recorded the boot. Future
deployments must replace running scripts atomically. This first boot included
manual recovery; it is not evidence of unattended startup after a reboot.

The guarded boot installer is now checking the original boot_a before writing
the RAM-tested G image. A new file created in the installed root will be checked
after independent normal boots. Boot-slot installation and autonomous startup
are not considered complete until those checks pass.

The boot_a preflight passed, including the original stock-image hash and the
running G kernel build ID. The 64 MiB G image was written in 119.7 seconds, then
read back using direct I/O with SHA256 exactly matching the artifact above.
No other partition was written. The user confirms seeing and interacting with
Hyprland from the installed root before the restart, with noticeable slowness.

An orderly restart was requested through recovery PID1. USB did not return
within the initial observation window; the user sees console text. This is
under diagnosis and does not yet establish autonomous boot or clean reboot.
