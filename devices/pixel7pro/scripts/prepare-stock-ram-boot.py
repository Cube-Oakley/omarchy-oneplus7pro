#!/usr/bin/env python3
"""Prepare this unit's matching stock kernel with an explicit clean command line.

Does not communicate with a phone. Cloudripper 15.1 fills an empty v4 command
line from the existing boot partition, even for `fastboot boot`. This image
avoids that copy. Its AVB digest is no longer valid; use only on an unlocked
matching cheetah. Kernel, ramdisk, and every byte outside cmdline are unchanged.
"""

import argparse
import hashlib
from pathlib import Path
import struct


FACTORY_SHA256 = "6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10"
RESULT_SHA256 = "07a6c1a1cee1eaaa35df8004f5246e73ef9807a1e24e3be706b602774e3b09e6"
ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "out/factory-images/boot.img")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    original = args.source.read_bytes()
    if hashlib.sha256(original).hexdigest() != FACTORY_SHA256:
        parser.error("source is not the verified AP4A.250205.002 cheetah factory boot.img")
    if original[:8] != b"ANDROID!" or struct.unpack_from("<I", original, 40)[0] != 4:
        parser.error("expected Android boot header version 4")
    if any(original[44:1580]):
        parser.error("expected empty factory command-line field")

    result = bytearray(original)
    cmdline = b"loglevel=4"
    result[44:1580] = cmdline.ljust(1536, b"\0")
    digest = hashlib.sha256(result).hexdigest()
    if digest != RESULT_SHA256:
        parser.error("unexpected output digest")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("xb") as f:
        f.write(result)
    print(f"{digest}  {args.output}")
    print("Prepared locally only; no phone commands issued.")


if __name__ == "__main__":
    main()
