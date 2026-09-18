#!/usr/bin/env python3
"""Portable PipeWire volume control; board output limits belong below this layer."""
import json
import re
import subprocess
import sys

SINK = '@DEFAULT_AUDIO_SINK@'


def wpctl(*args):
    return subprocess.check_output(['wpctl', *args], text=True, stderr=subprocess.PIPE, timeout=3)


def main(args):
    action = args[0] if args else 'status'
    if action in ('up', 'down'):
        wpctl('set-volume', '-l', '1.0', SINK, '5%+' if action == 'up' else '5%-')
    elif action == 'mute':
        wpctl('set-mute', SINK, 'toggle')
    elif action == 'set' and len(args) == 2:
        if not args[1].isdigit() or not 0 <= int(args[1]) <= 100:
            raise ValueError('Volume must be between 0 and 100')
        wpctl('set-volume', '-l', '1.0', SINK, args[1] + '%')
    elif action != 'status':
        raise ValueError('Usage: volume.py status|up|down|mute|set PERCENT')
    result = wpctl('get-volume', SINK)
    match = re.search(r'^Volume:\s+([0-9]+(?:\.[0-9]+)?)', result)
    if not match:
        raise ValueError('No audio output')
    return {'available': True, 'percent': round(float(match[1]) * 100), 'muted': '[MUTED]' in result}


if __name__ == '__main__':
    try:
        print(json.dumps(main(sys.argv[1:])))
    except (OSError, ValueError, subprocess.SubprocessError):
        print(json.dumps({'available': False, 'percent': 0, 'muted': False}))
        sys.exit(1)
