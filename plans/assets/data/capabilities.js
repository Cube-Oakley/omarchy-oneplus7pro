/* ==========================================================================
   Capabilities — the rows of the Compare page.
   Each device's hardware rows name one of these ids in `cap`. A device's cell
   rolls its rows up: all working → working, none working → not working,
   anything in between → partial. No rows → "not tracked yet".
   Order and wording here are what a phone owner would ask about, not part names.
   `key: true` rows also appear in the overview's "At a glance" table.
   ========================================================================== */
CAPS = [
  { group: "Boot & platform", items: [
    { id: "boot",        n: "Boots Linux natively", key: true },
    { id: "storage",     n: "Installed on internal storage", key: true },
    { id: "cpu",         n: "All CPU cores" },
    { id: "cpufreq",     n: "CPU frequency scaling" },
    { id: "gpu",         n: "GPU acceleration", key: true },
    { id: "suspend",     n: "Suspend and resume", key: true },
    { id: "deepsleep",   n: "Deep idle power states" },
    { id: "thermal",     n: "Thermal monitoring and throttling" },
    { id: "recovery",    n: "Safe recovery path" }
  ]},
  { group: "Display & input", items: [
    { id: "display",     n: "Internal display", key: true },
    { id: "refresh",     n: "High refresh rate" },
    { id: "brightness",  n: "Brightness control" },
    { id: "touch",       n: "Touchscreen", key: true },
    { id: "buttons",     n: "Hardware buttons" },
    { id: "haptics",     n: "Vibration" }
  ]},
  { group: "Power", items: [
    { id: "battery",     n: "Battery level", key: true },
    { id: "charging",    n: "Charging", key: true },
    { id: "fastcharge",  n: "Fast charging" },
    { id: "wireless",    n: "Wireless charging" },
    { id: "poweroff",    n: "Power off" }
  ]},
  { group: "Connectivity", items: [
    { id: "usbnet",      n: "USB networking and SSH" },
    { id: "usbhost",     n: "USB host (keyboards, drives)" },
    { id: "dp",          n: "External display over USB-C" },
    { id: "wifi",        n: "Wi-Fi", key: true },
    { id: "bluetooth",   n: "Bluetooth", key: true },
    { id: "cellular",    n: "Mobile data", key: true },
    { id: "sms",         n: "SMS" },
    { id: "calls",       n: "Voice calls", key: true },
    { id: "gps",         n: "GPS" },
    { id: "nfc",         n: "NFC" }
  ]},
  { group: "Audio", items: [
    { id: "speaker",     n: "Loudspeaker", key: true },
    { id: "earpiece",    n: "Earpiece" },
    { id: "mic",         n: "Microphone", key: true },
    { id: "headset",     n: "Wired headset" }
  ]},
  { group: "Sensors & cameras", items: [
    { id: "motion",      n: "Accelerometer and gyroscope" },
    { id: "compass",     n: "Compass" },
    { id: "light",       n: "Ambient light" },
    { id: "proximity",   n: "Proximity" },
    { id: "fingerprint", n: "Fingerprint reader" },
    { id: "camera-rear", n: "Rear cameras", key: true },
    { id: "camera-front",n: "Front camera" },
    { id: "flash",       n: "Flash and torch" }
  ]}
];
