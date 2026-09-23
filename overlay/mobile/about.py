#!/usr/bin/env python3
"""Portable device identity for Settings → About. No serials, USB addresses or IMEI."""
import json
import os
from pathlib import Path
import re
import sys

STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'omarchy-mobile'


def os_name(text):
    pretty = None
    name = None
    for line in text.splitlines():
        if line.startswith('PRETTY_NAME='):
            pretty = line.split('=', 1)[1].strip().strip('"')
        elif line.startswith('NAME='):
            name = line.split('=', 1)[1].strip().strip('"')
    return pretty or name or 'Linux'


def slot_from_cmdline(text):
    match = re.search(r'(?:androidboot\.)?slot(?:_suffix)?[=_](_?[ab])\b', text)
    if not match:
        return ''
    return match.group(1).lstrip('_')


def latest_backup(root):
    backups = root / 'backups'
    if not backups.is_dir():
        return '', 0
    names = sorted(path.name for path in backups.iterdir()
                   if path.is_dir() and re.fullmatch(r'\d{8}-\d{6}', path.name))
    if not names:
        return '', 0
    return str((backups / names[-1]).resolve()), len(names)


def snapshot(proc=Path('/proc'), etc=Path('/etc'), state=STATE, uname=None):
    kernel = uname or os.uname().release
    try:
        hostname = (proc / 'sys/kernel/hostname').read_text().strip()
    except OSError:
        hostname = os.uname().nodename
    try:
        slot = slot_from_cmdline((proc / 'cmdline').read_text().replace('\0', ' '))
    except OSError:
        slot = ''
    try:
        distro = os_name((etc / 'os-release').read_text())
    except OSError:
        distro = 'Linux'
    model = ''
    try:
        model = (Path('/sys/firmware/devicetree/base/model')).read_text().strip('\0').strip()
    except OSError:
        pass
    backup, count = latest_backup(state)
    return {
        'available': True,
        'hostname': hostname,
        'os': distro,
        'kernel': kernel,
        'slot': slot,
        'model': model,
        'backup': backup,
        'backups': count,
    }


def report(data):
    lines = [
        f"Host: {data.get('hostname') or '—'}",
        f"OS: {data.get('os') or '—'}",
        f"Kernel: {data.get('kernel') or '—'}",
        f"Slot: {data.get('slot') or '—'}",
        f"Model: {data.get('model') or '—'}",
        f"Latest backup: {data.get('backup') or '—'}",
    ]
    return '\n'.join(lines)


def main(argv=None, proc=Path('/proc'), etc=Path('/etc'), state=STATE, uname=None):
    argv = sys.argv[1:] if argv is None else argv
    data = snapshot(proc=proc, etc=etc, state=state, uname=uname)
    if argv[:1] == ['report']:
        return {'available': True, 'text': report(data)}
    return data


if __name__ == '__main__':
    print(json.dumps(main()))
