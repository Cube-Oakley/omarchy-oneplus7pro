# Ultra-wide camera — September 24, 2026

The rear ultra-wide, a Sony IMX481, works on its first boot with it: the
driver reads the chip ID, the sensor streams its full 4656x3496 raw mode at
30 fps through CSIPHY3, CSID0 and VFE0, and Omarchy Camera takes upright,
merged photos with it. It also focuses: its AK7374 actuator, which the 7T Pro
port left unpowered, now has power and autofocus, including tap to focus.
All three rear cameras load together, and the app's lens buttons read 0.6×,
1× and 3×. Runtime modules and an overlay, on
the stack of the [main camera](camera-20260922.md) and the
[telephoto](camera-telephoto-20260924.md).

## Wiring

Our stock tree (`18821/sm8150-oem-camera-t0.dtsi`, `qcom,cam-sensor@3`) and
the OnePlus 7T Pro's working port agree: the second camera control interface
(CCI1, `cci@ac4b000`) master 1 at 0x1a, CSIPHY3 with four D-PHY lanes, MCLK3
at 19.2 MHz on GPIO16, reset GPIO23, VANA from BOB gated by PM8150L GPIO2,
VDIG PM8009 LDO4 at 1.056 V and VIO PM8150L LDO1. CCI1's masters use GPIO31-32
and GPIO33-34. The only pin also named in the boot tree, GPIO23, belongs to
QUP SE18, which is disabled.

Stock gives this sensor a 270 degree roll where the other three cameras have
90, and the 7T Pro used 90. A first raw frame from the phone, propped up
facing a monitor, came out upright and unmirrored after the same quarter turn
as the other cameras, so the overlay says 90: stock's roll presumably pairs
with a readout flip in its own sensor settings.

Stock also lists a focus actuator for this slot (VAF from BOB through
PM8150L GPIO4); the 7T Pro used none. See [Focus](#focus).

## Pieces

- `devices/oneplus7pro/kernel/camera/imx481.c`: the 7T Pro's driver (hotdog
  r181: 0100 and 0101, which keeps the default exposure inside the 3532-line
  limit), plus the focus actuator link (below). It already powers up analogue
  first (VANA and its gate,
  VDIG with a 1.1 A load, then VIO), and asks BOB for the IMX586's 3.3-3.32 V.
  `scripts/build_camera_modules.sh` builds it; the other modules rebuild
  byte-identical.
- `guacamole-camera.dts`, `-DCAMERA_WIDE`: CCI1 with its pins, MCLK3, the
  reset pin, the VANA gate pin as stock sets it, the sensor and CAMSS
  `port@3`. It builds `guacamole_camera_wide.ko` alone, and the `rear`
  overlay now carries all three rear cameras. The main camera's overlay is
  unchanged.
- `scripts/phone-camera-test.sh bus|sensor wide`, and `rear` for all three.
- `devices/oneplus7pro/adapter/camera/libcamera/imx481.yaml` (libcamera-guacamole
  0.7.2-11): the 7T Pro's tuning file with our contrast and saturation
  defaults and, as for the telephoto, an identity colour matrix, which
  applies the saturation and lets Omarchy Camera merge bursts; since 0.7.2-12
  also Af.

## Results

- `bus wide`: CCI1 bound with two adapters (`i2c-6`, `i2c-7`) and the client
  `7-001a`; LDO4 at 1.056 V.
- `sensor wide`: the driver bound (it binds only after reading chip ID
  0x0481), CAMSS completed its graph with the sensor on CSIPHY3, and
  `cam -l` listed an internal back camera on `cci@ac4b000`.
- Raw 4656x3496 SRGGB10 frames of 20,360,704 bytes (stride 5824) at 30 fps;
  the kernel logged "streaming 4656x3496 RAW10 over four-lane D-PHY" and no
  errors.
- `rear` loaded all three sensors on one boot; streams alternating ultra-wide,
  main, telephoto and ultra-wide again each ran at 30 fps in the app's
  configuration (preview and raw).
- Omarchy Camera orders them main (48 MP), ultra-wide (16 MP), telephoto
  (13 MP), and labels the buttons by zoom: 0.6×, 1×, 3×. On the ultra-wide
  it merged eight frames into an upright 3496x4656 photo.

## Focus

The user's first ultra-wide photos were dark and soft, and there was no tap
to focus. The softness held with the phone propped still: small print a
metre away barely resolved. Both OxygenOS ultra-wide modules in the vendor
image (`com.qti.sensormodule.ofilm_imx481.bin` and `semco_imx481.bin`, from
the OxygenOS 10 P.31 OTA) name an `imx481_ak7374` actuator, along with PDAF
data and a CAT24C64 EEPROM. With the ultra-wide streaming and PM8150L GPIO4
(stock's VAF switch) held high, a read-only probe of its I2C master found a
device at 0x0c that answers only with that rail on; its register 0x02 read
0x40 and its position registers zero, as an idle AKM AK737x does. The lens
had been resting at the actuator's unpowered position.

A sweep wrote the 7T Pro's AK7374 start-up sequence (0x3c to register 0x00,
0x00 to 0x01, then 0x00 to 0x02 for active) and 10-bit positions to register
0x00, with the phone propped facing a box about half a metre away:

| Position | 0 | 128 | 256 | 320 | 384 | 448 | 512 | 576 | 640 | 768 | 1023 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sharpness | 378 | 407 | 520 | 740 | 1521 | 2220 | 2139 | 1916 | 1183 | 533 | 480 |

At rest the frame was badly blurred; at 448 the box's lettering and the
wall's texture were sharp. So the overlay now carries the VAF regulator
(PM8150L GPIO4, set up as stock), the actuator (`asahi-kasei,ak7374` at
0x0c, the 7T Pro's AK7374 support in our `ak7375.c`) and the sensor's
`lens-focus` link, and the tuning file gains Af. Two driver changes keep the
coil from holding the lens whenever a camera app is open, as for the main
camera: `imx481.c` links the actuator for runtime power, as our IMX586
driver does, and `ak7375-power-with-sensor.patch` stops `ak7375.c` powering
up while its subdevice is open (libcamera keeps it open) and keeps a focus
written while it is off for the next resume. After a capture the actuator
read runtime-suspended.

libcamera's first autofocus run chose poorly: its coarse samples were taken
while exposure was still rising from the sensor's default gain, and the
sharpness statistic grows with exposure (squared green differences over a
green sum that includes the black level). The sample at 510 read 289,416
during the coarse scan and 1,233,191 during the fine one. Patch 0021
(libcamera-guacamole 0.7.2-13, all cameras) starts a scan once exposure has
held for three frames, or after 20 frames at most. Two runs then completed at
561 and 563, and Omarchy Camera reported the ultra-wide focused at 572; its
photo of the same box is clearly sharper than before.

The room was still dim for it: 33 ms at the sensor's highest gain (16x), and
its 1.0 µm pixels, unbinned in the driver's only mode, gather less light than
the main camera's.

## Next

- Longer exposures in dim light (a lower frame rate: the driver's vertical
  blanking reaches 62039 lines), and a binned mode for the ultra-wide if
  stock's register tables can be found.
- A colour calibration for both new cameras (flat, warm colours without one),
  perhaps fitted against the main camera on the same scene, and the modules'
  EEPROM (lens shading, focus calibration).
- A zoom control that crops between lenses, then fusion across cameras, which
  needs a second capture path (VFE1, patch 0076's missing hunk) to stream two
  cameras at once.
- The pop-up front camera (Sony IMX471 on CCI1 master 0, CSIPHY2) with its
  motor and hall sensors, the motor only with the user present.
