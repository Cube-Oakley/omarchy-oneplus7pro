#!/usr/bin/env python3
"""Sahara RESET for Qualcomm 05c6:900e crashdump (no extra deps)."""
from __future__ import annotations

import ctypes
import ctypes.util
import struct
import sys
import time

VID, PID = 0x05C6, 0x900E
EP_IN, EP_OUT = 0x81, 0x01

lib = ctypes.CDLL(ctypes.util.find_library("usb-1.0"))
lib.libusb_init.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
lib.libusb_open_device_with_vid_pid.restype = ctypes.c_void_p
lib.libusb_open_device_with_vid_pid.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_uint16]
lib.libusb_claim_interface.argtypes = [ctypes.c_void_p, ctypes.c_int]
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


def xfer(dev, ep, data=None, buflen=512, timeout=2000):
    n = ctypes.c_int(0)
    if data is None:
        buf = ctypes.create_string_buffer(buflen)
        rc = lib.libusb_bulk_transfer(dev, ep, buf, buflen, ctypes.byref(n), timeout)
        return rc, buf.raw[: n.value]
    buf = ctypes.create_string_buffer(bytes(data))
    rc = lib.libusb_bulk_transfer(dev, ep, buf, len(data), ctypes.byref(n), timeout)
    return rc, n.value


def hello_resp(mode=0):
    # cmd=2, len=48, version=2, compatible=1, status=0, mode, reserved[6]
    return struct.pack("<IIIIII6I", 2, 48, 2, 1, 0, mode, 0, 0, 0, 0, 0, 0)[:48]


def reset_pkt():
    return struct.pack("<II", 7, 8)


def main() -> int:
    ctx = ctypes.c_void_p()
    if lib.libusb_init(ctypes.byref(ctx)) != 0:
        print("libusb_init failed")
        return 1
    dev = lib.libusb_open_device_with_vid_pid(ctx, VID, PID)
    if not dev:
        print("900e not open")
        lib.libusb_exit(ctx)
        return 1
    rc = lib.libusb_claim_interface(dev, 0)
    print("claim", rc)
    # Read HELLO (device speaks first)
    rrc, payload = xfer(dev, EP_IN, timeout=1500)
    print("read rc", rrc, "len", len(payload), "hex", payload[:48].hex())
    if rrc == 0 and len(payload) >= 8:
        cmd, length = struct.unpack_from("<II", payload, 0)
        print("cmd", cmd, "length", length)
        if cmd == 1:
            rrc2, nw = xfer(dev, EP_OUT, hello_resp(0))
            print("hello_resp rc", rrc2, "wrote", nw)
            time.sleep(0.05)
    rrc3, nw = xfer(dev, EP_OUT, reset_pkt())
    print("reset rc", rrc3, "wrote", nw)
    lib.libusb_release_interface(dev, 0)
    lib.libusb_close(dev)
    lib.libusb_exit(ctx)
    return 0 if rrc3 == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
