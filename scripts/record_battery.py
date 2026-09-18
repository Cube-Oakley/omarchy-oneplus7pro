#!/usr/bin/env python3
"""Bounded standard power_supply sampling across a USB disconnect/reconnect."""
import argparse
import json
from pathlib import Path
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--seconds', type=float, default=300)
args = parser.parse_args()
deadline = time.monotonic() + args.seconds
while time.monotonic() < deadline:
    sample = {'time': time.time(), 'supplies': {}}
    for supply in Path('/sys/class/power_supply').iterdir():
        try:
            values = dict(line.split('=', 1) for line in (supply / 'uevent').read_text().splitlines())
            sample['supplies'][supply.name] = values
        except OSError as error:
            sample['supplies'][supply.name] = {'error': str(error)}
    print(json.dumps(sample), flush=True)
    time.sleep(5)
