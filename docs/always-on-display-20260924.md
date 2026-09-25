# Always-on display — September 24, 2026

With Settings → Display → Always-on display on (`alwaysOn` in `prefs.json`,
off by default), the power button shows a dim clock instead of switching the
panel off: the CRT close plays, then the time, date, battery and the apps
with notifications fade in on black at 15% brightness. The power button or
a double tap wakes the phone: the clock fades out and the CRT opens. Face
down or in a pocket the panel goes fully off under it, and the clock comes
back when the phone is picked up or taken out. User-checked, animations
included.

## The panel

The stock panel description (`18821/dsi-panel-samsung_oneplus_dsc.dtsi`,
both variants and both refresh rates) has empty AOD and LP1 command sets:
OxygenOS drove this panel's always-on display in its normal mode, dim. So
this is shell work, with no kernel change. A command-mode OLED suits it: black
pixels are off, and the panel keeps showing its last frame, so the clock
redraws once a minute (`SystemClock` at minute precision), when everything
also moves a few pixels against burn-in, within ±24 × ±40 px.

## How it fits together

- `power-button.py`: a press while the always-on display shows wakes the
  phone; with the preference on, a press on a lit screen asks for `ambient`
  instead of `off`, and never suspends. Its tests now stub the display
  helper the CRT change started launching directly; they had been failing
  since.
- `display-power.sh` (`omarchy-mobile-display`): `ambient` plays the CRT
  close, then asks the shell (`ipc call mobile ambient true`) and sets
  `$XDG_RUNTIME_DIR/omarchy-mobile-ambient`; `on` with that flag clears it,
  fades the clock out onto the CRT's parked black and plays the CRT open.
  `off` still means off, so other callers (the suspend test) are unchanged.
  `ambient-sleep` and `ambient-wake` switch DPMS under the clock.
- `MobileStatus.ambient`: entering sets the brightness to 15 without
  remembering it and pauses the automatic brightness follower; leaving
  restores the remembered level. Toasts and the rotate button wait.
- `AmbientDisplay.qml`: the overlay (Overlay layer, above the shade), which
  takes every touch; a double tap runs `omarchy-mobile-display on`.
- `ambient.py` (`omarchy-mobile-ambient watch`), run by the overlay while it
  shows: the tilt and light through iio-sensor-proxy. Face down for 2 s puts
  the panel to sleep until the phone is no longer face down. Dark (under
  3 lux) for 1.5 s while not lying flat asks the proximity sensor; near puts
  the panel to sleep until proximity reads far or the light is back above
  10 lux. Proximity is claimed only then, since its infrared emitter shows
  through the panel as a dot; a phone flat on a table in the dark keeps its
  clock. Tested by `tests/test_ambient.py`.

The trial from the host: the CRT close took 0.6 s, the level went from 58%
to 15%, the watcher claimed the accelerometer and light but not proximity (a
lit room), sleep and wake switched DPMS, and waking restored the brightness,
cleared both flags and played the CRT open.

## Next

- The clock's brightness is fixed; following the room (dimmer at night)
  would use the light sensor the watcher already reads.
- A lock screen, when there is one, belongs between the clock and the
  desktop.
