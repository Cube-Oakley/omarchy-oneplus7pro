#!/usr/bin/env python3
"""Observe a bounded Pixel RAM-boot serial test; only open 0525:a4a7 ACM ports."""
import argparse
import datetime
import os
from pathlib import Path
import select
import termios
import time
import tty

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--seconds', type=int, default=210)
a = ap.parse_args()
deadline = time.monotonic() + a.seconds
fd = None
last = None
last_error = None


def report(s):
    print(datetime.datetime.now(datetime.timezone.utc).isoformat(), s, flush=True)


while time.monotonic() < deadline:
    devices = []
    for p in Path('/sys/bus/usb/devices').glob('*'):
        try:
            vid = (p / 'idVendor').read_text().strip()
            pid = (p / 'idProduct').read_text().strip()
            if vid in ('18d1', '0525'):
                devices.append((p.name, vid, pid))
        except OSError:
            pass
    if devices != last:
        report(f'USB {devices}')
        last = devices
    if fd is None:
        for p in Path('/sys/class/tty').glob('ttyACM*'):
            for parent in (p / 'device').resolve().parents:
                try:
                    if ((parent / 'idVendor').read_text().strip(),
                        (parent / 'idProduct').read_text().strip()) != ('0525', 'a4a7'):
                        continue
                except OSError:
                    continue
                try:
                    fd = os.open('/dev/' + p.name, os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY)
                    tty.setraw(fd, termios.TCSANOW)
                    os.write(fd, b'PIXEL_HOST_ROUNDTRIP_20260925\n')
                    report(f'Opened {p.name}; sent roundtrip marker')
                except OSError as e:
                    if str(e) != last_error:
                        report(str(e))
                        last_error = str(e)
                    if fd is not None:
                        os.close(fd)
                    fd = None
                break
            if fd is not None:
                break
    if fd is not None:
        try:
            if select.select([fd], [], [], 0.5)[0]:
                data = os.read(fd, 4096)
                if not data:
                    raise OSError('Serial disconnected')
                report(repr(data))
        except OSError as e:
            report(str(e))
            os.close(fd)
            fd = None
    else:
        time.sleep(0.5)
if fd is not None:
    os.close(fd)
report('Observer complete')
