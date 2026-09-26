#!/usr/bin/env python3
"""Flash the reviewed sparse Linux root to cheetah userdata; never touch boot/GPT.

Defaults to read-only preflight. Requires the bootloader and the local output
directory from build-pixel-root-image.py. Does not reboot or switch slots.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SIZE = 245977141248


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--image-dir', type=Path, required=True)
    ap.add_argument('--replace-android-data', action='store_true')
    args = ap.parse_args()
    serial = os.environ.get('PHONE_SERIAL', '')
    if not serial:
        serial = (ROOT / 'out/device.serial').read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', serial):
        ap.error('Invalid local target serial')
    image = args.image_dir / 'root.sparse.img'
    manifest = json.loads((args.image_dir / 'manifest.json').read_text())
    with image.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
        source.seek(0)
        header = struct.unpack('<I4H4I', source.read(28))
    if digest != manifest['sparse_sha256'] or manifest['expanded_bytes'] != SIZE:
        ap.error('Sparse image checksum or expanded size differs from the reviewed manifest')
    if header[0] != 0xed26ff3a or header[1] != 1 or header[5] * header[6] != SIZE:
        ap.error('Sparse header does not match the userdata geometry')
    if manifest['chunk_bytes']['0xcac3'] < SIZE * 0.9:
        ap.error('Image does not skip unused space')

    def getvar(name):
        result = subprocess.run(['fastboot', '-s', serial, 'getvar', name],
                                check=True, text=True, capture_output=True, timeout=20)
        match = re.search(r'^' + re.escape(name) + r':\s*(\S+)', result.stdout + result.stderr, re.M)
        if not match:
            raise RuntimeError('Cannot read bootloader variable ' + name)
        return match[1]

    for name, expected in [('product', 'cheetah'), ('unlocked', 'yes'),
                           ('current-slot', 'a'), ('slot-successful:a', 'yes')]:
        if getvar(name) != expected:
            raise RuntimeError('Bootloader preflight mismatch: ' + name)
    if int(getvar('partition-size:userdata'), 0) != SIZE:
        raise RuntimeError('Bootloader userdata size differs from the reviewed layout')
    limit = min(128 * 1024 * 1024, int(getvar('max-download-size'), 0))
    if limit < 4 * 1024 * 1024:
        raise RuntimeError('Unexpected bootloader download limit')
    print('Verified cheetah slot A, unlocked bootloader, userdata size and sparse image hash.', flush=True)
    if not args.replace_android_data:
        print('Read-only preflight complete; no partition was written.')
        return
    with (args.image_dir / 'flash-userdata.log').open('w') as log:
        subprocess.run(['fastboot', '-s', serial, '-S', str(limit), 'flash', 'userdata', str(image)],
                       check=True, stdout=log, stderr=subprocess.STDOUT)
    print('Linux userdata image flashed. Bootloader remains active; persistent boot validation is next.')


if __name__ == '__main__':
    main()
