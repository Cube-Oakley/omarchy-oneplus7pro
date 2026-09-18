# Power-button suspend policy — 2026-09-17

Installed on the existing native5 #184 boot without flashing or restarting the
desktop. The user confirmed two physical unplugged Power sleep/wake cycles.
Both completed with zero PM failures and successful input/network recovery.

## Behavior and separation

`overlay/mobile/power-button.py` handles shared press/release pairing and DPMS.
The two bindings in `hypr-mobile.lua` launch helpers outside the compositor
event loop, using the documented [Hyprland bind flags](https://wiki.hypr.land/Configuring/Basics/Binds/).
They replace the previous release-only display toggle; an explicit unbind
prevents duplicate old bindings.

When the display is already blank, a tap restores it. Otherwise the optional
`~/.config/omarchy-mobile/suspend --check` adapter decides readiness. A refusal
(including plugged-in power, low battery or unavailable wake source) blanks the
display and logs the reason, without suspending. Missing adapters also retain
display control. On this phone `devices/oneplus7pro/power-suspend.sh` delegates
to `/usr/local/sbin/guacamole-suspend`, which rechecks hardware prerequisites
immediately before sleeping. Runtime errors attempt to leave the screen on.

A nonblocking lock spans the entire suspend/resume invocation. A wake press
during that interval cannot arm another release. After resume, a two-second
grace also ignores queued events. A late release from a long-held wake button
has no matching press and is ignored. Normal events require a new press/release
pair. Long-press menus, screen locking and automatic idle are not implemented.

## Validation and completed test mode

- Nine policy tests pass: plugged/unplugged, display wake, absent adapter,
  unpaired release, overlapping wake events, delayed wake release, error
  restoration and optional fallback alarm. Existing five suspend tests pass.
- Phone reload/configerrors passed; exactly one press and one release binding
  appear for XF86PowerOff, both allowed under input inhibition.
- Live helper calls while plugged in blanked and restored DPMS. Charging
  continued; suspend counters did not change. An extra unpaired release did
  nothing. Evidence: `out/power-button-policy/`.
- The two button-triggered trials slept **10.3245** and **7.0976 seconds**.
  Both suspend commands exited 0; kernel success is now 3 (including the earlier
  explicit trial), and all PM failure counters remain zero. Neither trial
  lasted long enough for its 90-second backup alarm to fire. No extra sleep
  invocation followed wake. The user confirmed everything behaved as expected.
- Hyprland rediscovers s6sy761 and pm8941_pwrkey; configuration errors are empty.
  test-network is connected and HTTPS through wlan0 returns 200. USB SSH reconnected.
- Charging resumed: an initial gauge sample reported zero current, then a
  subsequent sample reported Charging at +79 mA near 4.199 V, 85%, 28.5 C.
  Charger status also reached Full at the conservative 4.20 V ceiling; this is
  not proof of full vendor-rated battery capacity or complete taper validation.
- Removed `/run/user/0/omarchy-mobile-power-test-alarm` after verification.
  No RTC alarm remains armed. Normal Power sleep now has no timed fallback;
  the physical power button wakes it. `pm_async` is restored to 1.

Evidence: `out/power-button-policy/{physical-cycles,final-health}.log`.
Checkpoint: `out/checkpoints/20260917-power-button-verified/`. The new userspace
files persist on disk but their post-reboot activation still needs a routine
reboot check. The underlying native5 boot has already passed automatic startup.
Next measure longer unplugged idle drain and investigate the ath10k key-removal
delay. Short functional tests do not establish battery life. Automatic idle and
true shutdown remain unfinished.

## Recovery

Phone backup: `/root/power-button-policy/before/hypr-mobile.lua`.
Restore it to `/root/.local/share/omarchy-mobile/hypr-mobile.lua`, reload
Hyprland and check configerrors to return to display-only Power behavior.
No reboot is needed. The new helpers can remain unused. Screen-on recovery:
`XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 /root/.local/bin/omarchy-mobile-display on`.
The kernel/image rollback remains native4 through `flash_suspend_desktop.sh rollback`.
