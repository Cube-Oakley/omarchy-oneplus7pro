/* ==========================================================================
   Pixel 7 Pro (cheetah) — hardware bring-up
   s:   "ok" working · "partial" running, unproven · "no" not working · "absent" no such hardware
   cap: capability id from capabilities.js; the Compare page rolls rows up by it
   ========================================================================== */
HW.pixel7pro = {
  blurb: "Everything physically present in the Pixel 7 Pro, plus the platform pieces the phone depends on "
       + "(boot chain, firmware interfaces, power management, storage). Every result so far comes from "
       + "mainline Linux. Arch is installed on ext4 userdata and runs the shared desktop; boot_a is installed and checksum-verified. The first normal restart is under diagnosis.",

  sections: [
    {
      id: "soc",
      title: "SoC & platform",
      items: [
        { n: "Tensor G2 CPU (8 cores, three clusters)", s: "ok", cap: "cpu",
          note: "All eight CPUs online under mainline 7.3-rc2, with working GIC and timer interrupts.",
          ref: "devices/pixel7pro/docs/native-shell-20260925.md" },
        { n: "CPU frequency scaling", s: "partial", cap: "cpufreq",
          note: "Three cpufreq policies (CPUs 0–3, 4–5, 6–7) through ACPM firmware with schedutil: rates match "
              + "firmware readback and a pinned loop ran 2.2x faster at the top rate. Deliberately capped at the "
              + "inherited boot rates; the full range, voltage data and an energy model are still to come.",
          ref: "devices/pixel7pro/docs/power-bringup-20260925.md" },
        { n: "Mali-G710 MC7 GPU", s: "ok", cap: "gpu",
          note: "Upstream Panthor with CSF firmware; shader readback passes and Hyprland renders on it, with "
              + "fullscreen animation at 119.6–120.2 fps the user confirmed smooth. Needs an isolated Mesa build "
              + "carrying a missing G710 model entry.",
          ref: "devices/pixel7pro/docs/gpu-bringup-20260925.md" },
        { n: "GPU frequency scaling & cooling", s: "no",
          note: "One operating point only (302 MHz top / 202 MHz shader); no GPU DVFS, GPU cooling device or "
              + "validated power model yet.", ref: "devices/pixel7pro/docs/gpu-bringup-20260925.md" },
        { n: "RAM (12 GB)", s: "ok",
          note: "The whole Arch userspace, including a 4 GB mobile root, runs from RAM without trouble.",
          ref: "devices/pixel7pro/docs/device.md" },
        { n: "UFS storage (256 GB)", s: "partial", cap: "storage",
          note: "Linux enumerated all four UFS logical units and boot-image hashes match stock references. "
              + "Userdata is ext4; write/remount/readback passes, the installed desktop runs, and saved files survive reset plus a recovery RAM boot. PWM gear 1 makes cold startup slow.",
          ref: "devices/pixel7pro/docs/persistence-power-20260925.md" },
        { n: "Boot chain (unlocked bootloader, fastboot RAM boot)", s: "partial", cap: "boot",
          note: "Mainline Linux boots natively with an embedded initramfs through a hash-checked fastboot boot, "
              + "with a USB recovery shell and no automatic timeout. The exact RAM-tested kernel is installed in boot_a with direct checksum readback. USB does not return on normal boot; the same kernel boots from RAM. Header tracing appears absent on normal boot. A candidate embeds the required parameters directly in the kernel; hardware validation is pending.",
          ref: "devices/pixel7pro/docs/native-shell-20260925.md" },
        { n: "Bootloader and saved-image recovery", s: "ok", cap: "recovery",
          note: "Power + Volume Down reaches the verified bootloader; saved host images provide recovery. "
              + "Android userdata has been replaced for Linux. Slot B is not a fallback.",
          ref: "devices/pixel7pro/docs/status.md" },
        { n: "ACPM firmware interface (clocks, temperatures)", s: "ok",
          note: "Mailbox and ACPM protocol answer CPU, GPU, display and memory clock queries and all seven "
              + "temperature groups; the CPU scaling and GPU power work run through it.",
          ref: "devices/pixel7pro/docs/acpm-bringup-20260925.md" },
        { n: "Thermal sensing & throttling", s: "partial", cap: "thermal",
          note: "Seven thermal zones read real temperatures; emulated 65°C throttled all three clusters and "
              + "emulated 85°C rebooted the phone. Limits are conservative bring-up values; no physical "
              + "overheat test.", ref: "devices/pixel7pro/docs/power-bringup-20260925.md" },
        { n: "Tensor TPU (AI accelerator)", s: "no",
          note: "Only its temperature group is read; no driver.", ref: "devices/pixel7pro/docs/acpm-bringup-20260925.md" },
        { n: "Watchdogs", s: "partial",
          note: "Both inherited AP watchdogs are stopped so Linux survives past two minutes; nothing services a "
              + "watchdog yet.", ref: "devices/pixel7pro/README.md" },
        { n: "Suspend / resume", s: "no", cap: "suspend",
          note: "Not attempted. Only the GPU's runtime autosuspend has been exercised." },
        { n: "Deepest idle power states", s: "no", cap: "deepsleep", note: "Not attempted yet." },
        { n: "RTC and alarms", s: "no",
          note: "Not attempted; the clock is set from the computer at session start." },
        { n: "Power button", s: "ok", cap: "buttons",
          note: "S2MPG12 ACPM input driver reports physical press/release. User confirms clean shared CRT close/open and screen off/on. Polling input cannot wake a suspended CPU.",
          ref: "devices/pixel7pro/docs/persistence-power-20260925.md" },
        { n: "Volume up / down keys", s: "no", cap: "buttons", note: "Not attempted yet." },
        { n: "Battery gauge", s: "no", cap: "battery", note: "Not brought up.", ref: "devices/pixel7pro/adapter/README.md" },
        { n: "Charging", s: "no", cap: "charging",
          note: "Not brought up under Linux; charging was verified in the former Android baseline.",
          ref: "devices/pixel7pro/adapter/README.md" },
        { n: "Fast charging", s: "no", cap: "fastcharge", note: "Not attempted yet." },
        { n: "Wireless charging", s: "no", cap: "wireless", note: "Not attempted yet." },
        { n: "True power-off / shutdown", s: "no", cap: "poweroff",
          note: "The bring-up init turns ordinary shutdown into a reboot. One forced kernel power-off was issued; "
              + "a clean shutdown path is not verified.", ref: "devices/pixel7pro/docs/native-shell-20260925.md" },
        { n: "Security chip / hardware keystore", s: "no", note: "Not attempted yet." }
      ]
    },

    {
      id: "display",
      title: "Display & touch",
      items: [
        { n: "OLED panel, 1440 × 3120 (Samsung S6E3HC4, DSI)", s: "ok", cap: "display",
          note: "Native DMA scanout with real page flips, correct colours confirmed on the phone, zero transfer "
              + "failures. Linux still relies on the bootloader's panel, PLL and PHY setup.",
          ref: "devices/pixel7pro/docs/display-direct-20260925.md" },
        { n: "120 Hz refresh mode", s: "ok", cap: "refresh",
          note: "The driver switches the panel between 60 and 120 Hz; the desktop animates at 119.6–120.2 fps "
              + "with zero underruns, confirmed smooth by the user. Holds a fixed memory-bandwidth floor while "
              + "at 120 Hz; a shared bandwidth governor is still to come.",
          ref: "devices/pixel7pro/docs/panel120-20260925.md" },
        { n: "Panel power off / wake", s: "partial", cap: "display",
          note: "V19 B verifies DRM-controlled DCS display-off/on (power readback 0x99/0x9f); user confirms clean CRT transitions. "
              + "This retains panel rails and does not establish CPU suspend.",
          ref: "devices/pixel7pro/docs/persistence-power-20260925.md" },
        { n: "Backlight / brightness control", s: "no", cap: "brightness",
          note: "Not attempted; panel commands so far change refresh rate only, never brightness.",
          ref: "devices/pixel7pro/docs/panel120-20260925.md" },
        { n: "Always-on / ambient display", s: "no", note: "Not attempted yet." },
        { n: "Multitouch (Synaptics S3908)", s: "partial", cap: "touch",
          note: "A temporary module bit-bangs the controller's SPI bus over GPIO: the user confirmed the shell "
              + "responds, with heavy lag. The latest build stopped on a protocol error; a retry fix awaits a "
              + "physical test. A standard SPI and interrupt driver replaces it next.",
          ref: "devices/pixel7pro/docs/touch-bringup-20260925.md" },
        { n: "Haptic / vibration motor", s: "no", cap: "haptics", note: "Not attempted yet." }
      ]
    },

    {
      id: "audio",
      title: "Audio",
      items: [
        { n: "Audio DSP (AOC)", s: "no",
          note: "Not attempted. Stock Android loads it from vendor modules.", ref: "devices/pixel7pro/docs/device.md" },
        { n: "Loudspeaker", s: "no", cap: "speaker", note: "Not attempted yet." },
        { n: "Earpiece receiver", s: "no", cap: "earpiece", note: "Not attempted yet." },
        { n: "Microphones", s: "no", cap: "mic", note: "Not attempted yet." },
        { n: "Application playback (PipeWire)", s: "no",
          note: "No audio hardware under Linux yet; the shell's audio subscriber does not start.",
          ref: "devices/pixel7pro/docs/hyprland-mobile-20260925.md" },
        { n: "USB-C headset / adapter audio", s: "no", cap: "headset", note: "Not attempted yet." }
      ]
    },

    {
      id: "radio",
      title: "Radio & connectivity",
      items: [
        { n: "Wi-Fi", s: "no", cap: "wifi", note: "Not brought up.", ref: "devices/pixel7pro/adapter/README.md" },
        { n: "Bluetooth", s: "no", cap: "bluetooth", note: "Not brought up.", ref: "devices/pixel7pro/adapter/README.md" },
        { n: "Cellular modem", s: "no", cap: "cellular",
          note: "Not brought up.", ref: "devices/pixel7pro/adapter/README.md" },
        { n: "SIM detection & SIM PIN handling", s: "no", note: "Not attempted yet." },
        { n: "eSIM", s: "no", note: "Not attempted yet." },
        { n: "SMS / texting", s: "no", cap: "sms", note: "Needs the modem first." },
        { n: "Voice calls / VoLTE", s: "no", cap: "calls", note: "Needs the modem and audio first." },
        { n: "GPS / GNSS", s: "no", cap: "gps", note: "Not attempted yet." },
        { n: "NFC", s: "no", cap: "nfc", note: "Not attempted yet." },
        { n: "Ultra-wideband (UWB)", s: "no", note: "Not attempted yet." }
      ]
    },

    {
      id: "sensors",
      title: "Sensors",
      items: [
        { n: "Accelerometer", s: "no", cap: "motion", note: "Not attempted yet." },
        { n: "Gyroscope", s: "no", cap: "motion", note: "Not attempted yet." },
        { n: "Magnetometer (compass)", s: "no", cap: "compass", note: "Not attempted yet." },
        { n: "Barometric pressure", s: "no", note: "Not attempted yet." },
        { n: "Ambient light sensor", s: "no", cap: "light", note: "Not attempted yet." },
        { n: "Proximity sensor", s: "no", cap: "proximity", note: "Not attempted yet." },
        { n: "Under-display fingerprint reader", s: "no", cap: "fingerprint", note: "Not attempted yet." }
      ]
    },

    {
      id: "cameras",
      title: "Cameras",
      items: [
        { n: "Rear main camera", s: "no", cap: "camera-rear", note: "Not attempted yet." },
        { n: "Rear ultra-wide camera", s: "no", cap: "camera-rear", note: "Not attempted yet." },
        { n: "Rear telephoto camera", s: "no", cap: "camera-rear", note: "Not attempted yet." },
        { n: "Front camera", s: "no", cap: "camera-front", note: "Not attempted yet." },
        { n: "LED flash / torch", s: "no", cap: "flash", note: "Not attempted yet." },
        { n: "Image signal processor", s: "no",
          note: "Not attempted; its temperature group is the only part Linux reads so far." },
        { n: "Video codec (hardware encode / decode)", s: "no", note: "Not attempted yet." }
      ]
    },

    {
      id: "usb",
      title: "USB & expansion",
      items: [
        { n: "USB-C peripheral networking (CDC-ECM + ACM)", s: "ok", cap: "usbnet",
          note: "Serial console and USB Ethernet side by side; key-only SSH and a hash-matched 8 MiB SFTP round "
              + "trip verified. Runs on the USB PHY state the bootloader leaves behind.",
          ref: "devices/pixel7pro/docs/native-arch-20260925.md" },
        { n: "USB host mode (keyboard, mouse, Ethernet)", s: "no", cap: "usbhost",
          note: "Peripheral mode only. The development keyboard is fed from the computer over the USB link.",
          ref: "devices/pixel7pro/adapter/README.md" },
        { n: "USB-C DisplayPort / dock output", s: "no", cap: "dp",
          note: "Not a requirement for this phone, by the user's decision: Google documents wired projection "
              + "only from the Pixel 8, and native routing is unverified. Docking stays a shared-OS feature "
              + "for capable devices.", ref: "docs/shared-os-20260925.md" },
        { n: "SuperSpeed USB", s: "no",
          note: "USB 2 only; the controller reuses the inherited PHY state rather than driving the PHY.",
          ref: "devices/pixel7pro/README.md" }
      ]
    },

    {
      id: "not-present",
      title: "Not present on this handset",
      blurb: "Tracked so they stay off the wish list. Grey means there is no hardware to bring up.",
      items: [
        { n: "3.5 mm headphone jack", s: "absent", note: "USB-C audio only." },
        { n: "microSD card slot", s: "absent", note: "Storage is fixed at factory UFS." },
        { n: "Notification LED", s: "absent", note: "Alerts must come from the screen, haptics or sound." },
        { n: "IR blaster", s: "absent", note: "No infrared transmitter on this model." }
      ]
    }
  ]
};
