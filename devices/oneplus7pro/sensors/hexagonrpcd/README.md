# hexagonrpcd patches

Unmodified from the OnePlus 7T Pro port's `aports/main/hexagonrpcd`
(hotdog-linux-bringup by Robin Snyders, GPL-2.0), for hexagonrpc 0.4.0
(linux-msm/hexagonrpc, GPL-3.0-or-later):

- `0001-serve-writable-files.patch`: `fwrite`, create and read-write opens,
  the persist registry mapped to the served `sensors/` directory, and unknown
  methods no longer fatal.
- `0002-implement-fremove.patch`: `fremove`.
- `0003-raise-listener-input-limit.patch`: 64 KiB listener input buffer (the
  registry writes exceed 256 bytes).
- `0004-support-extended-frename.patch`: the extended method dispatch and
  `frename`, which the DSP uses to move temporary registry files into place.

`scripts/phone-build-hexagonrpcd.sh` builds them on the phone.
