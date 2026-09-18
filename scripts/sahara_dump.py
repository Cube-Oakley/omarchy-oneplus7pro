#!/usr/bin/env python3
"""Dump Qualcomm 05c6:900e Sahara MEMORY_DEBUG table (and optional regions)."""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import struct
import sys
import time
from pathlib import Path

VID, PID = 0x05C6, 0x900E
EP_IN, EP_OUT = 0x81, 0x01
SAHARA_HELLO_REQ = 1
SAHARA_HELLO_RSP = 2
SAHARA_MEMORY_DEBUG = 9
SAHARA_MEMORY_READ = 0xA
SAHARA_64BIT_MEMORY_DEBUG = 0x10
SAHARA_64BIT_MEMORY_READ = 0x11
SAHARA_MODE_MEMORY_DEBUG = 2

lib = ctypes.CDLL(ctypes.util.find_library("usb-1.0"))
lib.libusb_init.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
lib.libusb_open_device_with_vid_pid.restype = ctypes.c_void_p
lib.libusb_open_device_with_vid_pid.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint16,
    ctypes.c_uint16,
]
lib.libusb_claim_interface.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.libusb_set_auto_detach_kernel_driver.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.libusb_bulk_transfer.argtypes = [
    ctypes.c_void_p,
    ctypes.c_ubyte,
    ctypes.c_void_p,
    ctypes.c_int,
    ctypes.POINTER(ctypes.c_int),
    ctypes.c_uint,
]
lib.libusb_release_interface.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.libusb_close.argtypes = [ctypes.c_void_p]
lib.libusb_exit.argtypes = [ctypes.c_void_p]


def xfer(dev, ep, data=None, buflen=0x10000, timeout=4000):
    n = ctypes.c_int(0)
    if data is None:
        buf = ctypes.create_string_buffer(buflen)
        rc = lib.libusb_bulk_transfer(dev, ep, buf, buflen, ctypes.byref(n), timeout)
        return rc, buf.raw[: n.value]
    buf = ctypes.create_string_buffer(bytes(data))
    rc = lib.libusb_bulk_transfer(dev, ep, buf, len(data), ctypes.byref(n), timeout)
    return rc, n.value


def read_mem(dev, addr, length, bit64):
    data = b""
    pos = 0
    while pos < length:
        chunk = min(0x80000, length - pos)
        if bit64:
            req = struct.pack("<IIQQ", SAHARA_64BIT_MEMORY_READ, 24, addr + pos, chunk)
        else:
            req = struct.pack("<IIII", SAHARA_MEMORY_READ, 16, addr + pos, chunk)
        rc, _ = xfer(dev, EP_OUT, req, timeout=4000)
        if rc != 0:
            raise RuntimeError(f"read req rc={rc} at {addr + pos:#x}")
        got = 0
        while got < chunk:
            rc, part = xfer(dev, EP_IN, buflen=min(0x10000, chunk - got), timeout=8000)
            if rc != 0 or not part:
                raise RuntimeError(f"read data rc={rc} n={len(part)} at {addr + pos:#x}")
            data += part
            got += len(part)
            pos += len(part)
    return data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/grok-goal-d067b137fc5d/implementer/sahara")
    ap.add_argument("--dump-all", action="store_true")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    ctx = ctypes.c_void_p()
    if lib.libusb_init(ctypes.byref(ctx)) != 0:
        print("libusb_init failed")
        return 1
    dev = lib.libusb_open_device_with_vid_pid(ctx, VID, PID)
    if not dev:
        print("900e not open")
        lib.libusb_exit(ctx)
        return 1
    lib.libusb_set_auto_detach_kernel_driver(dev, 1)
    rc = lib.libusb_claim_interface(dev, 0)
    print("claim", rc)
    rrc, payload = xfer(dev, EP_IN, timeout=2000)
    print("hello rc", rrc, "len", len(payload), "hex", payload[:48].hex())
    if rrc != 0 or len(payload) < 24:
        return 2
    cmd, length = struct.unpack_from("<II", payload, 0)
    if cmd != SAHARA_HELLO_REQ:
        print("unexpected cmd", cmd)
        return 3
    ver, vmin, maxcmd, mode = struct.unpack_from("<IIII", payload, 8)
    print(f"ver={ver} vmin={vmin} maxcmd={maxcmd} mode={mode}")
    hello_resp = struct.pack(
        "<IIIIIIIIIIII",
        SAHARA_HELLO_RSP,
        0x30,
        ver,
        1,
        0,
        SAHARA_MODE_MEMORY_DEBUG,
        1,
        2,
        3,
        4,
        5,
        6,
    )
    rrc, nw = xfer(dev, EP_OUT, hello_resp)
    print("hello_resp rc", rrc, "wrote", nw)
    rrc, dbg = xfer(dev, EP_IN, timeout=4000)
    print("debug rc", rrc, "len", len(dbg), "hex", dbg[:64].hex())
    if rrc != 0 or len(dbg) < 16:
        return 4
    c2, l2 = struct.unpack_from("<II", dbg, 0)
    if c2 == SAHARA_64BIT_MEMORY_DEBUG:
        addr, tlen = struct.unpack_from("<QQ", dbg, 8)
        bit64 = True
    elif c2 == SAHARA_MEMORY_DEBUG:
        addr, tlen = struct.unpack_from("<II", dbg, 8)
        bit64 = False
    else:
        print("unexpected debug cmd", c2)
        return 5
    print(f"memtable addr={addr:#x} len={tlen:#x} bit64={bit64}")
    table = read_mem(dev, addr, tlen, bit64)
    (out / "memtable.bin").write_bytes(table)
    entsize = 64 if bit64 else 52
    parts = []
    for i in range(len(table) // entsize):
        e = table[i * entsize : (i + 1) * entsize]
        if bit64:
            sp, base, ln = struct.unpack_from("<QQQ", e, 0)
            desc = e[24:44].split(b"\x00")[0].decode("ascii", "replace")
            fn = e[44:64].split(b"\x00")[0].decode("ascii", "replace")
        else:
            sp, base, ln = struct.unpack_from("<III", e, 0)
            desc = e[12:32].split(b"\x00")[0].decode("ascii", "replace")
            fn = e[32:52].split(b"\x00")[0].decode("ascii", "replace")
        print(f"  {fn:20} {desc:24} base={base:#x} len={ln:#x}")
        parts.append((fn or f"region{i}", desc, base, ln))
    interesting = ("KMSG", "device_info", "ramoops", "console", "dmesg", "pstore")
    dumped = 0
    for fn, desc, base, ln in parts:
        want = args.dump_all or any(s.lower() in (fn + desc).lower() for s in interesting)
        if not want or ln == 0 or ln > 64 * 1024 * 1024:
            continue
        safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in fn) or "region"
        path = out / f"{safe}.bin"
        print(f"dumping {fn} -> {path} ({ln} bytes)")
        path.write_bytes(read_mem(dev, base, ln, bit64))
        dumped += 1
    print(f"dumped {dumped} regions to {out}")
    lib.libusb_release_interface(dev, 0)
    lib.libusb_close(dev)
    lib.libusb_exit(ctx)
    return 0


if __name__ == "__main__":
    sys.exit(main())
