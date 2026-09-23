#!/usr/bin/env python3
"""Disk space for the Settings storage panel. Read only."""
import json
from pathlib import Path
import shutil
import sys


def usage(path):
    path = Path(path)
    numbers = shutil.disk_usage(path)
    return {
        'path': str(path),
        'total': numbers.total,
        'used': numbers.used,
        'free': numbers.free,
    }


def snapshot(home=None):
    home = Path(home or Path.home())
    root = usage('/')
    root['label'] = 'Phone'
    volumes = [root]
    home_usage = usage(home)
    if home_usage['total'] != root['total']:
        home_usage['label'] = 'Home'
        volumes.append(home_usage)
    return {'ok': True, 'volumes': volumes}


def main():
    try:
        print(json.dumps(snapshot()))
        return 0
    except OSError as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
