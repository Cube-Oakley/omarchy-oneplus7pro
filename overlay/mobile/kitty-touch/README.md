# Kitty touch adapter (experimental)

Kitty 0.48.2 does not subscribe to Wayland `wl_touch`. The optional patch adds
single-finger vertical scrolling directly to its Wayland backend, using its
existing high-resolution/momentum scroll path. Taps become clicks; motion
exceeding 8 logical pixels becomes a scroll if predominantly vertical.
A second contact cancels the gesture, avoiding accidental clicks. Native
mouse input is unchanged. This is shared mobile code, with no input-device,
OnePlus, framebuffer or privilege assumptions in the listener.

Source: <https://github.com/kovidgoyal/kitty/tree/v0.48.2> (GPL-3.0).
The patch is only enabled when `KITTY_MOBILE_TOUCH=1`, which the mobile shell
exports to launched applications. Only new Kitty processes load the backend.
The user confirmed natural scrolling on the phone on 2026-09-17.

## Reproduce on the target architecture

Use the exact v0.48.2 source and matching installed Kitty version:

```sh
cd kitty-0.48.2
patch -p1 < /path/to/overlay/mobile/kitty-touch/wayland-touch.patch
cp /path/to/overlay/mobile/kitty-touch/build-wayland.py .
python3 build-wayland.py
```

This builds only `kitty/glfw-wayland.so` with the upstream build system.
Dependencies are a C compiler, Python and the Wayland backend's pkg-config
libraries (Wayland client/cursor/scanner, xkbcommon, DBus and GL/EGL headers).
The native build on this phone required no further package installations.

On this Arch Linux ARM installation the installed backend is
`/usr/lib/kitty/kitty/glfw-wayland.so`. Back it up, stage the newly built library
under a different filename in that directory, then rename it into place.
Never overwrite the inode of a shared library used by running processes.
The shell installer deliberately does **not** replace a package library or
apply this patch automatically to an arbitrary Kitty version.

Phone backups:
- Unpatched package library: `/root/backups/pre-gestures-20260917/glfw-wayland.so`
- Scroll-only touch backend: `/root/backups/kitty-touch-scroll-20260919/glfw-wayland.so`

Restore using the same stage-and-rename approach, then reopen terminals.
A Kitty package upgrade replaces the patched backend. Long term this should
be an upstream contribution or a maintained, versioned package build; do not
hold back Kitty upgrades just to retain the patch.

Long-press (~400 ms) without a scroll starts a mouse selection: a still
release double-clicks to select a word; a hold-then-drag extends the
selection. `copy_on_select clipboard` puts that text on the Wayland clipboard,
which the mobile clipboard helper already records. Multi-finger gestures are
not implemented. The patch forwards scrolling through Kitty's usual path, so
applications that capture scrolling decide their own behavior. Terminal
scrollback was tested; full-screen TUI scrolling is not yet verified.

Live `glfw-wayland.so` was rebuilt on the phone 2026-09-19 from v0.48.2 with
this patch. Only **new** Kitty processes load it (`KITTY_MOBILE_TOUCH=1`).
