#!/usr/bin/env python3
"""Wrap a raw ARM64 Image for this unlocked Pixel's RAM boot; never flash.

Retains matching factory AVB metadata/OS properties, with an intentionally
stale payload digest. Based on the successful standalone display-probe package.
"""
import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FACTORY_SHA = "6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kernel", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--cmdline", required=True)
    a = ap.parse_args()
    if not a.cmdline or "\0" in a.cmdline or len(a.cmdline.encode()) >= 1536:
        ap.error("need a nonempty NUL-free command line shorter than 1536 bytes")
    raw = a.kernel.read_bytes()
    if raw[56:60] != b"ARM\x64":
        ap.error("kernel must be an uncompressed ARM64 Image")
    stock = (ROOT / "out/factory-images/boot.img").read_bytes()
    if hashlib.sha256(stock).hexdigest() != FACTORY_SHA:
        ap.error("matching factory boot image failed pinned checksum")
    original, offset, size = struct.unpack_from(">QQQ", stock, len(stock) - 52)
    if stock[-64:-60] != b"AVBf" or (original, offset, size) != (25006080, 25006080, 2368):
        ap.error("unexpected factory AVB layout")
    a.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=a.output.parent) as d:
        p = Path(d)
        subprocess.run(["lz4", "-f", "-l", "-9", str(a.kernel), str(p / "Image.lz4")], check=True)
        subprocess.run(["mkbootimg", "--header_version", "4", "--kernel", str(p / "Image.lz4"),
                        "--cmdline", a.cmdline, "--output", str(p / "boot.img")], check=True)
        minimal = (p / "boot.img").read_bytes()
    if len(minimal) > original:
        ap.error("payload exceeds verified factory AVB boundary; do not truncate")
    result = minimal.ljust(original, b"\0") + stock[original:]
    with a.output.open("xb") as f:
        f.write(result)
    print(f"{hashlib.sha256(result).hexdigest()}  {a.output}")
    print(f"Kernel wrapper: {len(minimal)} bytes. Final image: {len(result)} bytes.")
    print("Created locally only. No device commands issued.")


if __name__ == "__main__":
    main()
