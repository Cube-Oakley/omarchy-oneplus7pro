# Pixel 7 Pro development adapter

These files connect the shared Omarchy mobile overlay to the verified Pixel
RAM-only Hyprland session. They are source-development artifacts, not host desktop
configuration. Install them only inside the target Arch root.

- `mobile.json`: display scale, keyboard dimensions and common shortcut settings.
  The display driver's preferred mode is used; no OnePlus 90 Hz assumption.
- `desktop-prepare.sh`: sources the shared generated mobile config into
  `/root/pixel-hyprland.lua` after checking a validated Pixel RAM kernel. No register,
  partition, clock, charging, suspend or radio operations.
- `quickshell-bootstrap.qml`: optional entry point that inherits the caller's
  Wayland environment. The tested host-driven entry is
  `scripts/pixel-mobile-start.sh`, which discovers the live compositor instance.
- `kernel/`: pinned mainline base, complete bring-up patches and configurations.

Shared shell source remains owned by the common mobile layer. The current Pixel
test consumes a hash-pinned snapshot of the OnePlus working tree without changing
it. Do not copy OnePlus hardware control adapters here. The future monorepo should
provide this overlay once and select the relevant device adapter during assembly.

| Capability | Current state |
|---|---|
| Native CPU/userspace | Verified, Arch Linux ARM in RAM, development PID1 |
| Internal display | Native DMA scanout; clean 60/120 Hz with integrated memory bandwidth floor |
| Hyprland/mobile shell | Mali-G710 rendering; fullscreen animation verified at 119.6–120.2 fps |
| USB serial/Ethernet/SSH | Verified |
| Development keyboard | Verified USB-fed uinput; on-screen keyboard renders |
| Physical touch | Temporary GPIO SPI input; v18 packet readiness fix under validation, hardware SPI pending |
| GPU, full panel/power control | GPU rendering works; full display power/PHY ownership remains unfinished |
| CPU/thermal | Bounded cpufreq, schedutil and seven thermal zones verified |
| Battery/charging | Not brought up |
| Wi-Fi, Bluetooth, cellular, audio, camera | Not brought up |
| Persistent storage/native install | Not brought up; no partitions flashed |
| Wired external display | Not a requirement for this device |

See [the working checkpoint](../docs/hyprland-mobile-20260925.md),
[current status](../docs/status.md), and
[physical touch checkpoint](../docs/touch-bringup-20260925.md).
