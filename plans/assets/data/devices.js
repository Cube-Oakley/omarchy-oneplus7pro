/* ==========================================================================
   Devices — one entry per supported handset, in display order.
   Each entry needs a matching assets/data/device-<id>.js that sets HW.<id>.
   `short` labels the per-device chips on shared rows.
   `reference: true` marks the device the shared software is developed on:
   software and integration rows without an explicit per-device status count
   as verified there and as "not tried yet" everywhere else.
   ========================================================================== */
DEVICES = [
  {
    id: "oneplus7pro",
    name: "OnePlus 7 Pro",
    short: "OnePlus",
    codename: "guacamole",
    soc: "Snapdragon 855 · Adreno 640",
    reference: true,
    stage: "Daily bring-up",
    summary: "Boots Arch Linux ARM from internal storage into the full touch shell on the GPU. Wi-Fi, "
           + "audio, Bluetooth, sensors and all three rear cameras work; cellular waits on a SIM and deep "
           + "sleep is unfinished.",
    meta: ["kernel #194 · slot B", "updated 2026-09-24"],
    readme: "devices/oneplus7pro/README.md",
    status: "devices/oneplus7pro/docs/status.md"
  },
  {
    id: "pixel7pro",
    name: "Pixel 7 Pro",
    short: "Pixel",
    codename: "cheetah",
    soc: "Google Tensor G2 (GS201) · Mali-G710",
    stage: "Early bring-up",
    summary: "Mainline Linux boots from RAM over fastboot and runs the shared mobile shell under Hyprland "
           + "on the Mali GPU at 120 Hz. Storage, battery, radios and audio are not brought up yet; "
           + "Android stays the normal boot.",
    meta: ["mainline 7.3-rc2 · RAM boot", "updated 2026-09-25"],
    readme: "devices/pixel7pro/README.md",
    status: "devices/pixel7pro/docs/status.md"
  }
];
