# Telephoto camera — September 24, 2026

The rear telephoto, a Samsung S5K3M5, works on its first boot with it: the
sensor answers, streams full-resolution raw frames through CSIPHY0, CSID0 and
VFE0 RDI0, and its focus actuator moves the lens. Everything is runtime
modules and an overlay, on the main camera's stack ([camera](camera-20260922.md)).
With both rear cameras in one overlay, libcamera lists both, and Omarchy
Camera switches between them with 1× and 3× buttons. The user's photos with it
came out "not bad" once the lens could reach its focus (below).

## Wiring

The stock tree (`18821/sm8150-oem-camera-t0.dtsi`, `qcom,cam-sensor@1`) is
the same as the OnePlus 7T Pro's: CCI0 master 0, CSIPHY0 with four D-PHY
lanes, MCLK0 on GPIO13, reset GPIO28, VANA from BOB through the GPIO148
switch, VDIG PM8009 LDO2 (stock asks 1.056 V), VIO PM8150L LDO1, and the
focus actuator's rail from BOB through the GPIO35 switch. The I2C addresses
are not in the tree; the 7T Pro found the sensor at 0x10 (chip id 0x30d5)
and, on Samsung Electro-Mechanics modules, an LC898217XC at 0x74 (O-Film
modules carry an AK7374 at 0x0c instead).

## Pieces

- `devices/oneplus7pro/kernel/camera/s5k3m5.c`: the linux-next driver as the
  7T Pro carries it (hotdog r181: 0058, 0081), with two changes. The supplies
  come up one at a time, analogue before digital (AF, VANA, VDIG, VIO), and go
  down in reverse, where `regulator_bulk_enable` raced them: on this board a
  digital rail first tripped the PMIC's undervoltage lockout on the Sony
  slots. And the sensor links its focus actuator (`lens-focus`, as our IMX586
  driver does), so the lens powers with it. The driver needs MCLK at exactly
  24 MHz (stock ran 19.2) and a 602.5 MHz link.
- `v4l2-cci.ko`: the register helper the driver uses; our `.config` leaves
  `V4L2_CCI` unset, so `scripts/build_camera_modules.sh` builds it with its
  I2C half. The existing camera modules rebuild byte-identical.
- `guacamole-camera.dts` builds per slot: `-DCAMERA_MAIN` gives the IMX586
  overlay (`guacamole_camera.ko`, byte-identical to before), `-DCAMERA_TELE`
  the telephoto's (`guacamole_camera_tele.ko`): its pins, the two switched
  rails, LDO2 at 1.056 V, the lens at 0x74, the sensor at 0x10 and CAMSS
  `port@0`. Both together give `guacamole_camera_rear.ko`
  (`scripts/build_camera_overlay.sh` builds all three). CAMSS completes only
  once every sensor on its graph has bound, so a slot that failed would take
  the other down with it: the single-slot overlays are for bringing a sensor
  up. The loader refuses a second overlay, so one variant per boot.
- `scripts/phone-camera-test.sh bus|sensor main|tele|rear`.
- `devices/oneplus7pro/adapter/camera/libcamera/s5k3m5.yaml`, in libcamera-guacamole
  since 0.7.2-8: the 7T Pro's tuning file (black level 4096, white balance,
  exposure, autofocus) with our contrast and saturation defaults and, since
  0.7.2-9, an identity colour matrix (below).

## Results

- `bus tele`: LDO2 set to 1.056 V; "LC898217XC actuator ready" at `4-0074`,
  so this unit's telephoto is a Samsung Electro-Mechanics module, like its
  main camera.
- `sensor tele`: the driver bound `4-0010` (it binds only after reading chip
  id 0x30d5), powered up in the new order without incident, and runtime
  suspended; the lens link is in place, and CAMSS completed its graph.
- Raw capture, `SGRBG10_1X10/4208x3120` through CSIPHY0 → CSID0 → VFE0 RDI0,
  `pgAA`: 16,423,680-byte frames (stride 5264), no kernel errors, the 7T Pro's
  figures exactly. At the default exposure (256 lines, about 2.5 ms, gain 1)
  a room reads black; at 3310 lines and gain 8 the ceiling above the phone
  showed. Focus 400 was clearly sharper than 0 on the same scene: the
  actuator moves the lens. Test pattern 1 is a solid colour, black by default.
  Frames stay in `out/camera/tele/`.

## Both rear cameras

With `bus rear` and `sensor rear` both sensors bound (`5-001a` and `4-0010`,
the lenses at `5-0072` and `4-0074`), each linked to its own CSIPHY (1 and 0),
and `cam -l` listed two back cameras. They share CSID0 and VFE0 RDI0, which
libcamera's simple pipeline routes to whichever camera starts: short captures
alternating tele, main, tele all streamed (the telephoto's 1440x1080 test ran
on its 2104x1184 mode at 60 fps, the main camera at 30 fps). Only one rear
camera can stream at a time.

Omarchy Camera now orders the cameras back first, largest sensor first on
each side, so the main camera opens first and the telephoto is second. A row of
lens buttons over the viewfinder shows the cameras on the side in use, each
labelled with its zoom (the app knows the 7 Pro's three rear sensors; any
other shows its model), and a tap switches. The switch keeps libcamera
running and releases one camera before taking the other. It is refused while a
photo is being taken, and a photo cut short by the app going to the background
now counts as failed, where before the shutter could stay dimmed.
`qs ipc call camera lens N` and `cameras` drive it for tests.

Over IPC the app switched to the telephoto and back, took a 3120x4200 upright
photo on the telephoto (a single frame at first: the burst merge needs a
colour matrix, see Dim rooms), and after switching back merged an eight-frame
photo on the main camera as before.

The phone was rebooted through the port-23 recovery script with the rear
stack loaded and idle three times, and came back normally each time on #194.
The camera notes record a hang on the same kind of reboot on September 23, so
these are good data points, not a fix.

## Focus range

The user's first telephoto photos were zoomed in correctly but slightly out of
focus, and dim. Autofocus had settled at 157 of the lens's 0-400. That range
is the 7T Pro's, whose check tried 0, 100, 200, 300 and 400 on a ceiling
and found 400, the end of the range, sharpest. The LC898217XC takes 0-1023.

A sweep over the whole range, with the lens held on through its runtime PM
control and positions written to register 0x84 as the driver does, measured
the sharpness of the frame's centre (the green channel's gradient energy)
with the user aiming at a subject about 1 m away, then across the room:

| Position | 0 | 256 | 384 | 448 | 512 | 576 | 640 | 704 | 768 | 896 | 1023 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 m | 93 | 139 | 147 | 213 | 337 | 482 | 452 | 495 | 373 | 267 | 208 |
| Across the room | 193 | 273 | 331 | 380 | 426 | 601 | 669 | 606 | 508 | 299 | 225 |

Below about 450 the voice coil hardly lifts the lens off its stop; focus lives
above that, the room at 640 and 1 m around 700, so 0-400 left every subject
out of reach. The overlay now gives the telephoto's lens the whole range and
starts it at 640 (`onnn,max-focus-position = <1023>`,
`onnn,default-focus-position = <640>`). libcamera's autofocus then steps 255
and 51 and, with the phone still, completed at 660, 658 and 703 on the same
scenes. The main camera keeps 0-400.

## Dim rooms

In the user's room the telephoto ran at its longest exposure at 30 fps
(3310 lines) and the sensor's highest gain (16x): it gathers less light than
the main camera, which bins four pixels into one and has the faster lens.
Its stills were single frames, because Omarchy Camera merges a burst only
when the frames carry a colour matrix. The tuning file now has an identity
matrix, which leaves the colours as they were and applies the saturation
default (the image processor skips it without a matrix): the telephoto's
stills now merge up to eight raw frames and are much brighter. Held in the
hand at 3x, each 33 ms frame can still blur and the merge cannot always align
them.

Continuous autofocus rescanned every few seconds in the hand: it scanned
again when the sharpness read below 65% of the scan's best sample for three
frames, and hand shake does that on a long lens. Patch 0020
(libcamera-guacamole 0.7.2-10, for both cameras) follows the sharpness
smoothed over about eight frames, takes the reference from that once the lens
has settled, and scans again only after half a second below 60% of it. On a
still phone, ten seconds brought no rescan.

## Found on the way

Our copy of the 7T Pro's CAMSS patch 0076 (the `gcc_camera_axi` clock for the
VFEs, their "r83" fix) has a wrong hunk header: `patch` applies its first hunk
with fuzz and silently drops the VFE1 hunk (the 7T Pro's r181 tree has the
same gap). VFE0 has the clock, and both cameras use VFE0; VFE1 needs the fix
before anything streams through it.

## Next

1. A telephoto colour calibration. The spec sheet calls this camera 8 MP;
   the sensor reads out 4208x3120 (13 MP), and the photos keep nearly all of
   it (3120x4200 upright).
2. Longer exposures in dim light (a lower frame rate: the driver's vertical
   blanking reaches 62415 lines), and a check of whether the main camera's
   0-400 lens range also stops short of its close focus.
3. The pop-up front camera (Sony IMX471 on CCI1, CSIPHY2) with its motor
   and hall sensors, the motor only with the user present. The ultra-wide
   works: [ultra-wide](camera-ultrawide-20260924.md).
4. Fix 0076's VFE1 hunk.
