# Keyboard focus transition fix

Patch wvkbd 0.20 at upstream commit
`6b41504a0cb58fd1163fa44692398fbd61f8905f` (jjsullivan5196/wvkbd).
This is shared Wayland keyboard behavior, with no OnePlus-specific code.

The unmodified `--auto` handler immediately destroys the keyboard layer on
input-method deactivate. Hyprland/Kitty focus changes send deactivate/done,
then activate/done about 3–4 ms later. The keyboard releases its 280-pixel
exclusive zone, then recreates it, making every tiled window jump.

The patch applies pending visibility at the protocol's `done` boundary and
waits 120 ms before automatic hiding. Activation cancels the pending hide;
the existing layer stays mapped when moving directly between text inputs.
Explicit SIGUSR1/SIGUSR2/SIGRTMIN controls remain immediate and cancel pending
hiding. There is no periodic wakeup when a hide is not pending. This does not
add text-input support to applications/compositors that fail to send events.

Build on the target with Wayland, xkbcommon and pangocairo development files:

```sh
# In a clean checkout of the pinned commit:
patch --batch -p1 < /path/to/focus-grace.patch
patch --batch -p1 < /path/to/show-reentry.patch
make -j4 wvkbd-mobintl
```

Back up the installed executable before installing the result. This project's
phone uses `/usr/local/bin/wvkbd-mobintl`; the original is saved at
`/root/backups/keyboard-focus-20260917/wvkbd-mobintl`. Replace via a temporary
file and rename, then restart only the keyboard through its existing helper.
The launch helper and automatic/manual policy do not need config changes.

Validation and binary checkpoints are recorded in
`docs/keyboard-focus-fix-20260917.md`. Reapply/revalidate the patch when upgrading
wvkbd; it is not yet an upstream change or an automatically rebuilt package.

## Nested show guard

`show-reentry.patch` applies after the focus patch. Sizing in `show()` performs
Wayland roundtrips that can dispatch another input-method activation before
the new layer pointer exists. Guarding construction prevents that nested call
from creating an orphaned keyboard. This preserves the earlier focus grace.

Run `python tests/check_wvkbd_show.py /path/to/patched/main.c` from the project
root for a deterministic nested-show check of the actual C function. The old
function fails; guarded code creates one layer and still permits reopening.
Live visibility/focus results and updated binary recovery information are in
`docs/touch-drawers-20260917.md` under the follow-up section.
