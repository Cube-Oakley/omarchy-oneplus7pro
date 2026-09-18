#!/usr/bin/env python3
"""Restore UFS LUNs from a backup taken by backup_ufs.py.

DANGEROUS. This overwrites raw flash. It is interactive and requires
FASTBOOT or a rooted adb shell. Default is dry-run.

Never flash sdf (EFS/IMEI) or persist from a different phone.
Never flash xbl/abl unless you are unbricking with a known-good image.

Typical recovery:
  1. boot the phone to fastboot (Vol Up + Vol Down + Power)
  2. restore boot_a / dtbo_a / vbmeta_a from extracted partitions
  3. only restore whole LUNs (sda/sde/sdf) as a last resort
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

LUNS = ("sdb", "sdc", "sdd", "sdf", "sde", "sda")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(8 * 1024 * 1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--backup-dir", type=Path, required=True)
    p.add_argument("--lun", action="append", choices=LUNS, help="LUNs to restore (repeatable)")
    p.add_argument("--really", action="store_true", help="actually write. default is verify-only")
    args = p.parse_args()
    luns_dir = args.backup_dir / "luns"
    targets = args.lun or list(LUNS)
    rc = 0
    for lun in targets:
        img = luns_dir / f"{lun}.img"
        sha_p = luns_dir / f"{lun}.img.sha256"
        if not img.exists():
            print(f"MISSING {img}")
            rc = 1
            continue
        print(f"verify {img} ({img.stat().st_size} bytes) ...")
        digest = sha256_file(img)
        if sha_p.exists():
            expected = sha_p.read_text().split()[0]
            if digest != expected:
                print(f"  HASH MISMATCH {lun}: got {digest} expected {expected}")
                rc = 1
                continue
            print(f"  sha256 ok {digest}")
        else:
            print(f"  sha256 {digest} (no recorded checksum)")
        if args.really:
            print(f"  REFUSING to auto-flash {lun}: restore is device-destructive.")
            print(f"  Manual: adb shell su -c 'dd if={img} of=/dev/block/{lun} bs=1048576'")
            print("  or fastboot flash the extracted named partitions instead.")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
