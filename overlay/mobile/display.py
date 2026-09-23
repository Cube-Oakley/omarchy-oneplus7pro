#!/usr/bin/env python3
"""What Settings can say about the screen. Brightness is reported, not changed."""
import json
import os
from pathlib import Path
import subprocess
import sys


def backlight():
    root = Path('/sys/class/backlight')
    if not root.is_dir():
        return None
    for device in sorted(root.iterdir()):
        try:
            current = int((device / 'brightness').read_text())
            maximum = int((device / 'max_brightness').read_text())
        except (OSError, ValueError):
            continue
        if maximum <= 0:
            continue
        return {'device': device.name, 'brightness': current, 'max': maximum, 'percent': round(current * 100 / maximum)}
    return None


def monitors():
    if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        return []
    try:
        raw = subprocess.check_output(['hyprctl', '-j', 'monitors'], text=True, timeout=3)
        data = json.loads(raw)
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    found = []
    for monitor in data if isinstance(data, list) else []:
        found.append({
            'name': monitor.get('name') or '',
            'width': monitor.get('width'),
            'height': monitor.get('height'),
            'refresh': monitor.get('refreshRate'),
            'scale': monitor.get('scale'),
        })
    return found


def snapshot():
    light = backlight()
    return {
        'ok': True,
        'monitors': monitors(),
        'brightness': light is not None,
        'backlight': light,
    }


def main():
    print(json.dumps(snapshot()))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
