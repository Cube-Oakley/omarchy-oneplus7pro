# Settings Sound, Battery and About — September 19

Userspace only. Shade quick toggles are unchanged.

- **Sound** uses `omarchy-mobile-volume` (status, mute, set 0–100). Same helper as
  the OSD and volume keys. No output-device picker.
- **Battery** uses `omarchy-mobile-battery`. Metrics only. Charging policy is not
  changed from Settings.
- **About** uses `omarchy-mobile-about`: hostname, OS, kernel, slot from cmdline
  if present, optional DT model, latest installer backup. **Copy device report**
  records that text through the clipboard helper. No serials or USB addresses.

## Recovery

Installer backup under `~/.local/state/omarchy-mobile/backups/`. Restore
Quickshell, the kit QML and `omarchy-mobile-about`, then reopen Settings.
