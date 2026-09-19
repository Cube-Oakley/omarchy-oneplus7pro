/* ==========================================================================
   HARDWARE page data
   s: "ok" working · "partial" running, unproven · "no" not working · "absent" no such hardware
   ========================================================================== */
PAGE_HARDWARE = {
  id: "hardware",
  nav: "Hardware",
  cardBlurb: "Every component physically inside guacamole, plus the platform pieces the phone leans on: "
           + "boot chain, power management, storage, sensors and radio.",
  eyebrow: "Project plan · Hardware",
  title: "Hardware",
  blurb: "Everything physically present in the OnePlus 7 Pro, plus the platform pieces the phone depends on "
       + "(boot chain, power management, storage). A row here is a component, not a feature idea.",

  sections: [
    {
      id: "soc",
      title: "SoC & platform",
      items: [
        { n: "Snapdragon 855 CPU (8 × Kryo 485)", s: "ok",
          note: "All eight cores online and individually tested.", ref: "docs/status.md" },
        { n: "CPU frequency scaling & idle states", s: "partial",
          note: "Cores run, but the scaling policy and idle states are untouched and unmeasured — this is "
              + "part of the unfinished battery-life work.", ref: "docs/mobile-roadmap.md" },
        { n: "Adreno 640 GPU", s: "ok",
          note: "Freedreno hardware rendering; Hyprland and Quickshell both run on the GPU (renderD128).",
          ref: "docs/cpu-gpu-work-20260916.md" },
        { n: "RAM (8 GB)", s: "ok", note: "In normal use; memory and swap policy not yet tuned for mobile." },
        { n: "UFS storage (256 GB)", s: "ok",
          note: "Persistent Arch Linux ARM rootfs on UFS. Full-LUN backup/restore helpers exist for recovery.",
          ref: "docs/backup.md" },
        { n: "A/B slots + stock OnePlus ABL boot", s: "ok",
          note: "Direct Linux boot through the OOS12 ABL on slot B; slot A stays a working Android fallback.",
          ref: "docs/pathway.md" },
        { n: "Hexagon ADSP (audio DSP)", s: "ok",
          note: "ADSP firmware loads and runs; it carries the audio path today.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Hexagon NPU (cDSP / AI engine)", s: "no",
          note: "Not mainlined for SM8150. Anything we run locally today has to fall back to CPU or GPU.",
          ref: "docs/pathway.md" },
        { n: "SLPI / SSC sensor subsystem", s: "no",
          note: "The sensor hub the physical sensors hang off. The related 7T Pro work drives it through "
              + "libssc → SEE rather than raw IIO; that is the likely path here too.", ref: "docs/pathway.md" },
        { n: "s2idle suspend / resume", s: "partial",
          note: "Repeated suspend cycles pass with touch, Wi-Fi, modem and charging recovering cleanly. The SoC "
              + "never reaches its deepest states (AOSD/CXSD/DDR residency stays zero).",
          ref: "docs/deeper-suspend-20260917.md" },
        { n: "Deepest idle power states", s: "no",
          note: "CX/MX/MMCX/MSS sleep votes still held; one isolated MSS release wedged modem resume.",
          ref: "docs/mss-handoff-test-20260917.md" },
        { n: "Thermal sensing & throttling policy", s: "no",
          note: "Thermal zones and governors untouched; sustained-load behaviour (games, video, a local model) "
              + "has never been measured on this build.", ref: "docs/mobile-roadmap.md" },
        { n: "RTC and alarms", s: "ok",
          note: "RTC binds under its correct SPMI parent; a five-second alarm fired while awake. RTC wake from "
              + "suspend is still to be proven.", ref: "docs/status.md" },
        { n: "Power button", s: "ok",
          note: "pm8941 pwrkey; two unplugged physical sleep/wake cycles confirmed by the user.",
          ref: "docs/power-button-policy-20260917.md" },
        { n: "Volume up / down keys", s: "partial",
          note: "Both keys enumerate cleanly after the SPMI-parent fix; physical press-and-hold behaviour not "
              + "yet confirmed by the user.", ref: "docs/audio-bringup-20260918.md" },
        { n: "Battery gauge (TI bq27541)", s: "ok",
          note: "Standard power_supply class: capacity, voltage, current and temperature, live while unplugged.",
          ref: "docs/battery-gauge-20260917.md" },
        { n: "Charging (PM8150 charger)", s: "ok",
          note: "Persistent conservative charging at 500 mA / 4.20 V, confirmed by independent PMIC readback.",
          ref: "docs/charging-20260917.md" },
        { n: "Warp Charge fast charging", s: "no",
          note: "Needs real charger/cable negotiation, temperature limits, taper and fault handling — raising "
              + "the current limits is not fast charging.", ref: "docs/mobile-roadmap.md" },
        { n: "True power-off / shutdown", s: "no",
          note: "Power-off attempts currently reboot the phone instead of staying off.",
          ref: "docs/shutdown-20260917.md" },
        { n: "Secure element / hardware keystore", s: "no",
          note: "Keymaster/keystore class of hardware. Needed eventually for screen-lock credentials, "
              + "pairing keys and any app that wants hardware-backed secrets.", ref: "docs/pathway.md" },
        { n: "Bring-up recovery path (Sahara/crashdump, guarded flash)", s: "ok",
          note: "Read-only Sahara dumps and guarded flashing helpers with serial, hash and slot checks.",
          ref: "scripts/" }
      ]
    },

    {
      id: "display",
      title: "Display & touch",
      items: [
        { n: "AMOLED panel, 1440 × 3120 DSC (DSI)", s: "ok",
          note: "Native DPU/DSI scanout at 60 Hz, correct colours, stable output. No ABL leftover framebuffer.",
          ref: "docs/native-display-work-20260917.md" },
        { n: "90 Hz refresh mode", s: "no", note: "Panel runs 60 Hz; the 90 Hz mode is not enabled yet." },
        { n: "Panel power off / wake", s: "ok",
          note: "Blank and restore driven by the power key, charging preserved.",
          ref: "docs/power-button-policy-20260917.md" },
        { n: "Backlight / brightness control", s: "no",
          note: "Fixed vendor brightness override (320/1023); no user-visible brightness path.",
          ref: "docs/mobile-roadmap.md" },
        { n: "Always-on / ambient display (panel doze)", s: "no", note: "Not attempted." },
        { n: "Multitouch (Samsung S6SY761)", s: "ok",
          note: "User-tested including five-finger input; survives suspend/resume.",
          ref: "docs/touchscreen-work-20260916.md" },
        { n: "Touchscreen gesture surface / edge rejection", s: "partial",
          note: "Bottom-edge and top-edge zones work as shell gestures, but palm and accidental-touch rejection "
              + "is untested.", ref: "docs/mobile-gestures-20260917.md" },
        { n: "Haptic / vibration motor", s: "no",
          note: "Not brought up. Needed for key feedback, long-press confirmation and call alerting.",
          ref: "docs/mobile-roadmap.md" }
      ]
    },

    {
      id: "audio",
      title: "Audio",
      items: [
        { n: "WCD9340 codec + SLIMbus", s: "partial",
          note: "Codec enumerates and ALSA exposes playback and capture (hw:0,3). The capture route has never "
              + "been exercised, so only the playback side has any evidence.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Main loudspeaker (TFA9874, lower amp)", s: "partial",
          note: "Amp identified (rev 0c74), clock lock achieved on isolated quiet tests, both amps return to "
              + "power-down afterwards. Independent acoustic confirmation still pending.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Earpiece receiver (TFA9874, upper amp)", s: "partial",
          note: "Stock-derived receiver profile wired up and clocking; one initial tone was heard by the user, "
              + "location uncertain. A hard prerequisite for calls.", ref: "docs/audio-bringup-20260918.md" },
        { n: "Stereo playback (speaker + receiver together)", s: "no",
          note: "Dual-output mixing and channel assignment untested; nothing has been heard from both at once.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Application playback (PipeWire)", s: "partial",
          note: "PipeWire/PipeWire-Pulse/WirePlumber expose an internal speakers sink with a fixed −36 dB cap. "
              + "YouTube playback has been reported inaudible.", ref: "docs/audio-bringup-20260918.md" },
        { n: "DSP speaker protection / calibration", s: "no",
          note: "No OTP/MTP programming or calibration run; the conservative output cap stays until this exists.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Primary microphone", s: "no", note: "Capture path untested; no recording has ever been produced.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Secondary / noise-cancelling microphones", s: "no",
          note: "Number, placement and routing on this unit are not yet verified. Needed for speakerphone and "
              + "video, and for anything voice-driven.", ref: "docs/mobile-roadmap.md" },
        { n: "Speakerphone audio path", s: "no",
          note: "Route switching between receiver, speaker and headset is the part a call actually depends on.",
          ref: "docs/mobile-roadmap.md" },
        { n: "Audio during suspend", s: "no", note: "Audio suspend has not been tested.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "USB-C headset / adapter audio", s: "no",
          note: "No analogue jack on this handset, so USB-C is the only wired-audio route; unattempted." }
      ]
    },

    {
      id: "radio",
      title: "Radio & connectivity",
      items: [
        { n: "Wi-Fi (WCN3990 / ath10k_snoc)", s: "ok",
          note: "NetworkManager connect, saved-network reconnect, internet access, and recovery after suspend.",
          ref: "docs/wifi-20260917.md" },
        { n: "Bluetooth", s: "no", note: "Not brought up. Same WCN3990 package as Wi-Fi.",
          ref: "docs/mobile-roadmap.md" },
        { n: "Cellular modem subsystem (QMI / QRTR)", s: "partial",
          note: "QMP attached, handover issued, QMI/QRTR queries answered, no daemon crashes. A running "
              + "remoteproc is not a usable modem.", ref: "docs/modem-foundations-20260917.md" },
        { n: "SIM detection & SIM PIN handling", s: "no",
          note: "Both SIM slots report absent; no SIM has been tested under Linux. The global SKU has one "
              + "nano-SIM tray.", ref: "docs/modem-foundations-20260917.md" },
        { n: "RF front end, EFS & calibration (IMEI)", s: "partial",
          note: "EFS LUN backed up for recovery and never flashed from another device. IMEI validity and "
              + "antenna behaviour under Linux are unverified.", ref: "docs/backup.md" },
        { n: "Cellular data (LTE)", s: "no", note: "IPA data path not validated; no registration, no bearer.",
          ref: "docs/mobile-roadmap.md" },
        { n: "SMS / texting", s: "no", note: "No tested cellular service yet, so no end-to-end SMS.",
          ref: "README.md" },
        { n: "Voice calls / IMS / VoLTE", s: "no",
          note: "Needs modem registration plus working speaker, earpiece and microphone first.",
          ref: "docs/mobile-roadmap.md" },
        { n: "Wi-Fi calling", s: "no", note: "Depends on IMS plus stable call audio; not started." },
        { n: "GPS / GNSS", s: "no", note: "Not brought up.", ref: "docs/mobile-roadmap.md" },
        { n: "NFC", s: "no", note: "Not brought up." }
      ]
    },

    {
      id: "sensors",
      title: "Sensors — physical silicon",
      blurb: "The parts actually wired to the SLPI/SSC sensor subsystem. Nothing here is enabled yet.",
      items: [
        { n: "Accelerometer", s: "no", note: "Not brought up; blocks auto-rotate and every motion sensor.",
          ref: "docs/pathway.md" },
        { n: "Gyroscope", s: "no", note: "Not brought up.", ref: "docs/pathway.md" },
        { n: "Magnetometer (magnetic field / compass)", s: "no", note: "Not brought up." },
        { n: "Barometric pressure", s: "no",
          note: "Present on this handset (reported in its Android sensor list); not brought up.", ref: "docs/pathway.md" },
        { n: "Ambient light sensor", s: "no", note: "Not brought up; required for auto-brightness." },
        { n: "Proximity sensor (ear-away / call detection)", s: "no",
          note: "Required before the screen can switch off against a face during a call.",
          ref: "docs/mobile-roadmap.md" },
        { n: "Hall sensor (pop-up camera endstops)", s: "no",
          note: "Bounds the pop-up selfie mechanism; nothing enabled yet.", ref: "docs/pathway.md" },
        { n: "In-display optical fingerprint reader", s: "no",
          note: "Not brought up; needed for unlock and app authentication.", ref: "docs/mobile-roadmap.md" }
      ]
    },

    {
      id: "sensors-derived",
      title: "Sensors — derived & fused",
      blurb: "Android on this handset reports around seventeen “sensors”. Only a handful are silicon — the "
           + "rest are computed from those, so they are not separate hardware work. They get their own rows so "
           + "a missing derived sensor is never mistaken for a missing chip. Worth re-reading the list off the "
           + "device from Android before we commit to what we reproduce.",
      items: [
        { n: "Gravity", s: "no", note: "Derived: accelerometer with tilt removed. No separate hardware." },
        { n: "Linear acceleration", s: "no", note: "Derived: accelerometer minus gravity. No separate hardware." },
        { n: "Rotation vector", s: "no",
          note: "Fused accelerometer + gyroscope + magnetometer; the useful one for stable orientation. Needs "
              + "all three physical sensors and their calibration data." },
        { n: "Geomagnetic rotation vector", s: "no",
          note: "Fused variant that tolerates a badly biased magnetometer. Derived, no separate hardware." },
        { n: "Game rotation vector", s: "no",
          note: "Accelerometer + gyroscope without the magnetometer, so it does not drift with magnetic "
              + "interference but has no absolute heading. What games and AR use." },
        { n: "Orientation (pitch / roll / azimuth)", s: "no",
          note: "Euler angles from the rotation vector. What auto-rotate and a compass UI consume." },
        { n: "Uncalibrated accelerometer / gyro / magnetic field", s: "no",
          note: "Same silicon, raw output with the estimated bias reported alongside. Only matters if we do our "
              + "own sensor fusion instead of using the SLPI's." },
        { n: "Step detector", s: "no",
          note: "Activity recognition derived from the accelerometer; low-power versions want the sensor hub." },
        { n: "Step counter", s: "no",
          note: "Same source as the step detector, counted. Cheap to keep on the hub, expensive on the CPU." },
        { n: "Significant motion", s: "no",
          note: "Fires when the handset is actually moved, deliberately ignoring small vibrations. Useful for a "
              + "phone that should know it changed hands or moved — and cheap to do on the sensor hub." },
        { n: "Sensor service for Linux (iio-sensor-proxy or SSI)", s: "no",
          note: "The layer every consumer (rotation, auto-brightness, compass apps, agents) reads. Decide "
              + "between raw IIO upstream and the SLPI unified-sensor interface before we build on it.",
          ref: "docs/pathway.md" }
      ]
    },

    {
      id: "cameras",
      title: "Cameras",
      items: [
        { n: "Rear wide — 48 MP Sony IMX586 (OIS)", s: "no", note: "Not brought up; libcamera path planned.",
          ref: "docs/pathway.md" },
        { n: "Rear ultra-wide — 16 MP", s: "no", note: "Not brought up." },
        { n: "Rear telephoto — 8 MP (OIS)", s: "no", note: "Not brought up." },
        { n: "Pop-up front camera — 16 MP Sony IMX471", s: "no", note: "Not brought up." },
        { n: "Pop-up camera motor & lifecycle", s: "no",
          note: "Unique to the 7 Pro / 7T Pro. Motor control, endstops and safe retraction (drop detection) "
              + "still to do.", ref: "docs/pathway.md" },
        { n: "ISP / image pipeline (IPE)", s: "no",
          note: "Sensors without the ISP give raw frames only. This is the long pole for usable photos, video "
              + "and any future scanning/QR features.", ref: "docs/pathway.md" },
        { n: "Video codec (Venus: hardware encode / decode)", s: "no",
          note: "Not brought up. Likely part of why web video is choppy, though that is not proven.",
          ref: "docs/next-session.md" },
        { n: "LED flash / torch", s: "no", note: "Not brought up." }
      ]
    },

    {
      id: "usb",
      title: "USB & expansion",
      items: [
        { n: "USB-C peripheral networking (NCM + ACM)", s: "ok",
          note: "Gadget Ethernet plus pinned-key SSH for development, with reconnect support.",
          ref: "docs/usb-networking-20260917.md" },
        { n: "USB host mode (keyboard, mouse, Ethernet)", s: "no",
          note: "Role switching, PHY and kernel support unverified. Currently high-speed peripheral only.",
          ref: "docs/mobile-roadmap.md" },
        { n: "USB-C DisplayPort / dock output", s: "no",
          note: "Monitor output, layout/scaling and simultaneous charging all unverified. This is the gate for "
              + "any docked desktop experience.", ref: "docs/mobile-roadmap.md" },
        { n: "SuperSpeed USB (5 Gbps)", s: "no",
          note: "Deliberately disabled during bring-up — enabling the QMP PHY crashed the kernel. Still open.",
          ref: "docs/status.md" }
      ]
    },

    {
      id: "not-present",
      title: "Not present on this handset",
      blurb: "Tracked so they stay off the wish list. Grey means there is no hardware to bring up.",
      items: [
        { n: "3.5 mm headphone jack", s: "absent", note: "Removed on this generation; USB-C only." },
        { n: "microSD card slot", s: "absent", note: "Storage is fixed at factory UFS." },
        { n: "Wireless charging", s: "absent", note: "Contact charging only." },
        { n: "eSIM", s: "absent", note: "Physical nano-SIM only on this SKU." },
        { n: "Notification LED", s: "absent", note: "Alerts must come from the screen, haptics or sound." },
        { n: "IR blaster", s: "absent", note: "No infrared transmitter on this model." }
      ]
    }
  ]
};
