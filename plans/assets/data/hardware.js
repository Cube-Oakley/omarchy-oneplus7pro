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
          note: "schedutil scales all three clusters (up to 1.79 / 2.42 / 2.84 GHz) with energy-aware "
              + "scheduling and CPU thermal cooling; big cores ran 3.5x faster once enabled. Loaded at boot as "
              + "an overlay; deeper idle states remain unfinished.", ref: "docs/smoothness-20260923.md" },
        { n: "Adreno 640 GPU", s: "ok",
          note: "Freedreno hardware rendering; Hyprland and Quickshell both run on the GPU (renderD128). "
              + "Frequency scaling works (257–585 MHz, simple_ondemand).", ref: "docs/smoothness-20260923.md" },
        { n: "RAM (8 GB)", s: "ok", note: "In normal use; memory and swap policy not yet tuned for mobile." },
        { n: "UFS storage (256 GB)", s: "ok",
          note: "Persistent Arch Linux ARM rootfs on UFS. Full-LUN backup/restore helpers exist for recovery.",
          ref: "docs/backup.md" },
        { n: "A/B slots + stock OnePlus ABL boot", s: "ok",
          note: "Direct Linux boot through the OOS12 ABL on slot B; slot A stays a working Android fallback. "
              + "Each boot marks slot B successful, so ABL's retry counter no longer runs out into the "
              + "\"boot image destroyed\" screen.", ref: "docs/microphone-20260922.md" },
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
        { n: "Thermal sensing & throttling policy", s: "partial",
          note: "September 22: 25 thermal zones and one cooling device exposed; plausible temperatures read. Trip points, cooling action and sustained-load behavior remain unverified.",
          ref: "docs/hardware-plan-20260922.md" },
        { n: "RTC and alarms", s: "ok",
          note: "RTC binds under its correct SPMI parent; a five-second alarm fired while awake. RTC wake from "
              + "suspend is still to be proven.", ref: "docs/status.md" },
        { n: "Power button", s: "ok",
          note: "pm8941 pwrkey; two unplugged physical sleep/wake cycles confirmed by the user.",
          ref: "docs/power-button-policy-20260917.md" },
        { n: "Volume up / down keys", s: "partial",
          note: "Both keys enumerate cleanly after the SPMI-parent fix; physical press-and-hold behaviour not "
              + "yet confirmed by the user.", ref: "docs/audio-bringup-20260918.md" },
        { n: "Three-position alert slider", s: "no",
          note: "Guacamole wiring and physical events need verification, followed by ring/vibrate/silent policy.",
          ref: "docs/hardware-plan-20260922.md" },
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
        { n: "90 Hz refresh mode", s: "partial",
          note: "Kernel #191 offers 60 and 90 Hz and the shell runs at 90 Hz: 89.8 Hz measured, no missed "
              + "refreshes. Stock's per-rate gamma is not applied yet.", ref: "docs/smoothness-20260923.md" },
        { n: "Panel power off / wake", s: "ok",
          note: "Blank and restore driven by the power key, charging preserved.",
          ref: "docs/power-button-policy-20260917.md" },
        { n: "Backlight / brightness control", s: "partial",
          note: "Backlight sysfs interface exists and reads 320/1023. Physical brightness changes and Settings control remain untested; no value was changed during investigation.",
          ref: "docs/hardware-plan-20260922.md" },
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
          note: "Works after the user reseated the bottom board. S16 output is capped at -18 dBFS, where a "
              + "1 kHz tone reaches about 5% distortion, behind a leveler and limiter. No speaker protection "
              + "yet.", ref: "docs/speakers-20260922.md" },
        { n: "Earpiece receiver (TFA9874, upper amp)", s: "partial",
          note: "Left channel; heard at the ear and measured by the top mic. Distorts far earlier than the "
              + "bottom speaker, so media reaches it capped at -42 dBFS. A hard prerequisite for calls.",
          ref: "docs/speakers-20260922.md" },
        { n: "Stereo playback (speaker + receiver together)", s: "partial",
          note: "Both play a mono mix, verified at the mic; the earpiece is about 17 dB quieter at its cap, "
              + "so true stereo is not used.", ref: "docs/speakers-20260922.md" },
        { n: "Application playback (PipeWire)", s: "ok",
          note: "YouTube plays clean and audible through the volume groups and a processing sink (400 Hz "
              + "high-pass, leveler, limiter). An 8-period buffer fixed silent and ticking playback.",
          ref: "docs/speakers-20260922.md" },
        { n: "DSP speaker protection / calibration", s: "no",
          note: "No OTP/MTP programming or calibration run; the per-speaker output cap stays until this exists.",
          ref: "docs/audio-bringup-20260918.md" },
        { n: "Primary microphone", s: "partial",
          note: "AMIC4, the stock handset mic, records through PipeWire as Internal microphone and starts with "
              + "the audio stack after reboot. Recordings of music played nearby were confirmed clean by ear. "
              + "Not yet tested across suspend; gain is a fixed conservative default.",
          ref: "docs/microphone-20260922.md" },
        { n: "Secondary / noise-cancelling microphones", s: "partial",
          note: "AMIC1 and AMIC3 also respond to room sound (+27 and +36 dB over quiet) and sound clean. AMIC3 is "
              + "the top mic; AMIC1 is probably near the rear cameras. Not exposed to applications yet.",
          ref: "docs/microphone-20260922.md" },
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
        { n: "Bluetooth", s: "partial",
          note: "WCN3990 loads its stock firmware, scans and pairs; OnePlus Bullets headphones play A2DP "
              + "(aptX HD) and Wi-Fi keeps working. Starts after the desktop (just enabled, not yet rebooted). Calls (HFP), PIN "
              + "keyboards and waking from suspend are untested.", ref: "docs/bluetooth-20260922.md" },
        { n: "Cellular modem subsystem (QMI / QRTR)", s: "partial",
          note: "QMP attached, handover issued, QMI/QRTR queries answered, no daemon crashes. A running "
              + "remoteproc is not a usable modem.", ref: "docs/modem-foundations-20260917.md" },
        { n: "SIM detection & SIM PIN handling", s: "no",
          note: "Both reported slots are absent; no SIM tested under Linux. Verify physical tray capacity and slot mapping before provisioning.",
          ref: "docs/cellular-plan-20260922.md" },
        { n: "RF front end, EFS & calibration (IMEI)", s: "partial",
          note: "EFS LUN backed up for recovery and never flashed from another device. IMEI validity and "
              + "antenna behaviour under Linux are unverified.", ref: "docs/backup.md" },
        { n: "Cellular data (LTE)", s: "partial",
          note: "IPA v4.1 binds on kernel #189 and the modem data interface appears; an rmnet link can be "
              + "created. No SIM yet, so no registration or bearer.",
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
          note: "Earlier checklist claimed an Android pressure sensor; recheck the actual stock inventory and physical part before selecting a driver.",
          ref: "docs/hardware-plan-20260922.md" },
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
        { n: "Gravity", s: "no",
          note: "Derived estimate of gravitational acceleration. No separate hardware.",
          ref: "docs/hardware-plan-20260922.md" },
        { n: "Linear acceleration", s: "no", note: "Derived: accelerometer minus gravity. No separate hardware." },
        { n: "Rotation vector", s: "no",
          note: "Fused accelerometer + gyroscope + magnetometer; the useful one for stable orientation. Needs "
              + "all three physical sensors and their calibration data." },
        { n: "Geomagnetic rotation vector", s: "no",
          note: "Orientation derived from accelerometer and magnetometer; depends on magnetic calibration. No separate hardware.",
          ref: "docs/hardware-plan-20260922.md" },
        { n: "Game rotation vector", s: "no",
          note: "Accelerometer and gyroscope without magnetic heading; avoids magnetic interference but can accumulate yaw drift. No separate hardware.",
          ref: "docs/hardware-plan-20260922.md" },
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
        { n: "Rear wide — 48 MP Sony IMX586 (OIS)", s: "partial",
          note: "Streams 4000x3000 raw over its C-PHY. A patched libcamera (the 7T Pro's IMX586 helper and "
              + "contrast autofocus, plus our statistics, lens-timing and memory fixes) runs it through the GPU "
              + "software ISP: 30 fps previews, full 3992x3000 at 15 fps. GNOME Snapshot shows it through "
              + "PipeWire, autofocus lands, and photos save. Image quality is still modest. Two crashes came "
              + "under full CPU load with the camera stack loaded; the cause is open.",
          ref: "docs/camera-20260922.md" },
        { n: "Rear ultra-wide — 16 MP", s: "no",
          note: "Sony IMX481 on CCI1 / CSIPHY3, per the stock tree. Not powered yet.", ref: "docs/camera-20260922.md" },
        { n: "Rear telephoto — 8 MP (OIS)", s: "no",
          note: "Samsung S5K3M5 on CCI0 / CSIPHY0, per the stock tree. Not powered yet.", ref: "docs/camera-20260922.md" },
        { n: "Pop-up front camera — 16 MP Sony IMX471", s: "no", note: "Not brought up." },
        { n: "Pop-up camera motor & lifecycle", s: "no",
          note: "Unique to the 7 Pro / 7T Pro. Motor control, endstops and safe retraction (drop detection) "
              + "still to do.", ref: "docs/pathway.md" },
        { n: "ISP / image pipeline (IPE)", s: "no",
          note: "Raw capture through CAMSS (CSIPHY, CSID, VFE raw path) works, processed by libcamera's "
              + "software ISP on the GPU (debayer, black level, white balance, exposure, autofocus). The "
              + "hardware ISP is unverified.",
          ref: "docs/hardware-plan-20260922.md" },
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
