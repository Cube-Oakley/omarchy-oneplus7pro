#!/usr/bin/env python3
"""Passively record Linux input events; no grab and no injected events."""
import argparse
import os
import select
import struct
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("device")
parser.add_argument("--seconds", type=float, default=600)
args = parser.parse_args()
event = struct.Struct("@llHHi")
fd = os.open(args.device, os.O_RDONLY | os.O_NONBLOCK)
deadline = time.monotonic() + args.seconds
print(f"Listening to {args.device} for {args.seconds:g}s (passive)", flush=True)
try:
    while (remaining := deadline - time.monotonic()) > 0:
        if not select.select([fd], [], [], remaining)[0]:
            break
        data = os.read(fd, event.size * 64)
        if not data:
            break
        for sec, usec, kind, code, value in event.iter_unpack(data):
            print(f"{sec}.{usec:06d} type={kind} code={code} value={value}", flush=True)
finally:
    os.close(fd)
print("Recorder finished", flush=True)
