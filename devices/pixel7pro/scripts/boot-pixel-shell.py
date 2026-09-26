#!/usr/bin/env python3
"""Boot the verified Pixel shell in RAM. Never flash or switch slots."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent


def phone_serial():
    """Target identity is private local state, never a checked-in handset serial."""
    serial = os.environ.get('PHONE_SERIAL', '')
    path = ROOT / 'out/device.serial'
    if not serial and path.is_file():
        serial = (path.read_text().split() or [''])[0]
    if not re.fullmatch(r'[A-Za-z0-9_-]+', serial):
        raise SystemExit('Set PHONE_SERIAL or put the target serial in ignored out/device.serial.')
    return serial


SERIAL = phone_serial()
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--image', type=Path, default=ROOT / 'out/checkpoints/20260925-shell-v9/boot-pixel-shell.img')
ap.add_argument('--sha256', default='88671219ba0d6835a7c6eee283948e38ec02f59522b44e6d760ddfb643493e05')
a = ap.parse_args()
if hashlib.sha256(a.image.read_bytes()).hexdigest() != a.sha256:
    raise SystemExit('Image checksum mismatch; phone was not touched')


def run(args, timeout=20):
    r = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=timeout)
    if r.returncode:
        raise RuntimeError(r.stdout.strip())
    return r.stdout.strip()


def fastboot_present():
    return any(line.split()[:1] == [SERIAL] for line in run(['fastboot', 'devices']).splitlines())


def getvar(name):
    result = run(['fastboot', '-s', SERIAL, 'getvar', name])
    match = re.search(r'^' + re.escape(name) + r':\s*(\S+)', result, re.M)
    if not match:
        raise RuntimeError('Cannot read fastboot variable: ' + result)
    return match[1]


if not fastboot_present():
    if run(['adb', '-s', SERIAL, 'get-state']) != 'device':
        raise SystemExit('Pixel must be in Android with ADB or in its bootloader')
    if run(['adb', '-s', SERIAL, 'shell', 'getprop', 'ro.product.device']) != 'cheetah':
        raise SystemExit('ADB product mismatch')
    run(['adb', '-s', SERIAL, 'reboot', 'bootloader'])
    deadline = time.monotonic() + 60
    while not fastboot_present():
        if time.monotonic() >= deadline:
            raise SystemExit('Bootloader did not appear within 60 seconds')
        time.sleep(0.5)
for name, expected in [('product', 'cheetah'), ('current-slot', 'a'),
                       ('unlocked', 'yes'), ('nos-production', 'yes'),
                       ('slot-successful:a', 'yes')]:
    actual = getvar(name)
    print(f'{name}: {actual}', flush=True)
    if actual != expected:
        raise SystemExit(f'Refusing RAM boot: expected {name}={expected}')
print(run(['fastboot', '-s', SERIAL, 'boot', str(a.image)], timeout=60))
print('RAM boot sent. Connect: python scripts/pixel-shell.py')
print('The image\'s configured test timeout applies; reboot returns to Android sooner.')
