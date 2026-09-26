# Keyboard focus flashing — 2026-09-17

During native DSI testing the user reported a subtle whole-screen flash when
tapping between two windows, possibly caused by the keyboard disappearing
briefly. Wayland protocol logging confirmed the keyboard destroyed its layer
on deactivate, then recreated it when the next Kitty activated 3–4 ms later.
The 280-pixel exclusive zone was released/reclaimed on every focus change.
This is distinct from the deliberate modetest pattern alternation.

Shared fix: `overlay/mobile/wvkbd-focus/focus-grace.patch`, on wvkbd 0.20
commit `6b41504a0cb58fd1163fa44692398fbd61f8905f`. It applies input-method
visibility at `done` and delays automatic hiding 120 ms. Returning to a text
input cancels the timer without unmapping the layer. Explicit show/hide/toggle
signals remain immediate. The installed launcher still uses `--auto --hidden`.

The original executable is preserved on the phone at
`/root/backups/keyboard-focus-20260917/wvkbd-mobintl`. The patched build is
isolated in `/root/src/wvkbd-focus-fix`; the original source is unchanged.
Host evidence/build logs: `out/keyboard-focus-test/`.

## Validation

- Before: eight focus transitions repeatedly destroy/recreate keyboard layers.
- Patched focus cycle: the keyboard layer stays mapped and monitor bottom
  reservation stays 304 (280 keyboard + 24 gesture region).
- Empty-workspace automatic-hide test was inconclusive: Hyprland sent no
  input-method deactivation. Use a non-text client that sends actual events.
- The first patched build failed the non-text automatic-hide test because its
  deadline-expiry call was missing. Corrected before final validation; the
  failed test and intermediate logs are retained rather than reported as passes.
- Final controlled eight-transition focus test passes: stable bottom reservation
  304 and no Wayland object destruction within the measured focus interval.
  The test explicitly shows the keyboard before starting; an earlier log also
  included manual hiding before the cycle and was not a clean comparison.
- Final non-text-client test passes: automatic hide leaves reservation 24;
  returning to Kitty restores 304; manual hide works; manual show cancels a
  pending automatic hide and remains visible after the deadline.
- Diagnostic logging is off. After native2 reboot, the user confirmed the
  result looks good in response to the gesture/focus-flash check.
- Final executable SHA256:
  `50a9a232d7b528e8520325b6fa5a13f2bd88c65ccb1f3d1c828c9516192711e1`.
- Host checkpoint: `out/checkpoints/20260917-keyboard-focus/`.

Native2 #179 reboot verification: the same patched executable starts hidden
automatically and registers its virtual keyboard; no helper was manually run
to launch it. The user subsequently accepted the result after the physical
gesture/focus-switch check ("yeah that looks good to me").

No kernel/config changes are needed for this fix. Native DSI currently runs
at 60 Hz; this does not enable 90 Hz or implement the planned drawer animations.


Follow-up: a user-reported stacked/stuck keyboard exposed a nested-show hazard
in sizing roundtrips. `show-reentry.patch` now applies after the focus patch;
the installed binary hash is
`96326263279e1bf2451ea8d4ce840a946df140d3348ec04f5cfe8b00c9dce5c8`.
The new deterministic regression and live 20-cycle visibility/eight-transition
focus checks pass. See [drawer-session follow-up and rollback](touch-drawers-20260917.md).
The historical `50a9...` binary/checkpoint above remains a rollback artifact.
