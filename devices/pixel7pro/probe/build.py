#!/usr/bin/env python3
"""Build locally only. Does not communicate with or flash a phone."""
import hashlib
from pathlib import Path
import re
import shutil
import struct
import subprocess

root = Path(__file__).resolve().parent.parent
src = root / "probe"
out = root / "out/restart-20260924/fb-probe-v2"
out.mkdir(parents=True, exist_ok=True)
(out / "source").mkdir(exist_ok=True)
for name in ["start.S", "display.c", "link.ld", "build.py"]:
    shutil.copyfile(src / name, out / "source" / name)
font_source = root / "mainline/linux/lib/fonts/font_8x16.c"
font = bytes(int(x, 16) for x in re.findall(r"^\s*(0x[0-9a-fA-F]{2}),", font_source.read_text(), re.M))
assert len(font) == 4096
(out / "font.h").write_text("/* SPDX-License-Identifier: GPL-2.0; Linux lib/fonts/font_8x16.c */\nstatic const unsigned char font[4096] = {\n" + ",".join(str(x) for x in font) + "\n};\n")
subprocess.run(["aarch64-linux-gnu-gcc", "-Wall", "-Wextra", "-Werror", "-Os",
    "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-pie", "-no-pie",
    "-fno-stack-protector", "-mgeneral-regs-only", "-mstrict-align",
    "-nostdlib", "-Wl,--build-id=none", "-Wl,-T," + str(src / "link.ld"),
    "-I" + str(out), str(src / "start.S"), str(src / "display.c"),
    "-o", str(out / "probe.elf")], check=True)
subprocess.run(["aarch64-linux-gnu-objcopy", "-O", "binary", str(out / "probe.elf"), str(out / "Image")], check=True)
image = (out / "Image").read_bytes()
assert image[56:60] == b"ARM\x64"
size = struct.unpack_from("<Q", image, 16)[0]
assert len(image) <= size < 1024 * 1024
(out / "Image").write_bytes(image.ljust(size, b"\0"))
subprocess.run(["lz4", "-f", "-l", str(out / "Image"), str(out / "Image.lz4")], check=True)
subprocess.run(["mkbootimg", "--header_version", "4", "--kernel", str(out / "Image.lz4"),
    "--cmdline", "pixel_fb_probe=v2", "--output", str(out / "boot-probe.img")], check=True)
# This Pixel's vbmeta chains to boot's own AVB metadata. A bare mkbootimg
# wrapper lacks the OS-version properties boot_from_images needs. Preserve the
# matching factory metadata and footer; the payload hash intentionally differs
# and is usable only on this unlocked development device.
stock = (root / "out/factory-images/boot.img").read_bytes()
assert hashlib.sha256(stock).hexdigest() == "6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10"
assert stock[-64:-60] == b"AVBf"
original_size, vbmeta_offset, vbmeta_size = struct.unpack_from(">QQQ", stock, len(stock) - 52)
assert original_size == vbmeta_offset == 25006080
assert vbmeta_size == 2368
minimal = (out / "boot-probe.img").read_bytes()
assert len(minimal) < original_size
envelope = minimal.ljust(original_size, b"\0") + stock[original_size:]
(out / "boot-probe-avb-envelope.img").write_bytes(envelope)
with (out / "probe.asm").open("w") as f:
    subprocess.run(["aarch64-linux-gnu-objdump", "-d", str(out / "probe.elf")], stdout=f, check=True)
lines = []
for name in ["Image", "Image.lz4", "boot-probe.img", "boot-probe-avb-envelope.img"]:
    lines.append(hashlib.sha256((out / name).read_bytes()).hexdigest() + "  " + name)
(out / "SHA256SUMS").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
print("Built locally only; no device commands issued.")
