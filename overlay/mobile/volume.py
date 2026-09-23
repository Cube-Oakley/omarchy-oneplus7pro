#!/usr/bin/env python3
"""Portable PipeWire volume control with Android-style volume groups.

Each group is a WirePlumber role loopback sink (wireplumber/30-mobile-volume-groups.conf).
Without those loopbacks, media falls back to the default sink and the other groups
report unavailable. Board output limits belong below this layer. "output" names the
default sink the groups play into, such as the speakers or Bluetooth headphones.

Media volume is per output, as on Android. Bluetooth headphones have their own
(absolute) volume, which their buttons change, so while they are the output the
media group means their volume and the media loopback is held at 100%; the
speaker level is remembered and comes back when they leave.

Usage: volume.py status | up|down|mute [GROUP] | set PERCENT [GROUP]
GROUP is media, ring, call or alarm. up/down/mute default to the group WirePlumber
says the volume keys control; set defaults to media. Top-level percent and muted
describe media, for older callers.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

GROUPS = {
    'media': 'input.loopback.sink.role.multimedia',
    'ring': 'input.loopback.sink.role.notification',
    'call': 'input.loopback.sink.role.communication',
    'alarm': 'input.loopback.sink.role.alarm',
}
DEFAULT_SINK = '@DEFAULT_AUDIO_SINK@'
CONTROL_KEY = 'current.role-based.volume.control'
UNAVAILABLE = {'available': False, 'percent': 0, 'muted': False}
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'omarchy-mobile/volume.json'
USAGE = 'Usage: volume.py status | up|down|mute [GROUP] | set PERCENT [GROUP]'


def wpctl(*args):
    return subprocess.check_output(['wpctl', *args], text=True, stderr=subprocess.PIPE, timeout=3)


def pw_dump():
    try:
        return json.loads(subprocess.check_output(['pw-dump'], text=True, stderr=subprocess.PIPE, timeout=5))
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def targets(objects):
    """wpctl target for each available group, and the group the keys control."""
    ids = {}
    for obj in objects:
        props = obj.get('info', {}).get('props', {})
        if obj.get('type') == 'PipeWire:Interface:Node' and props.get('media.class') == 'Audio/Sink':
            for group, name in GROUPS.items():
                if props.get('node.name') == name:
                    ids[group] = str(obj['id'])
    keys = 'media'
    for obj in objects:
        for entry in obj.get('metadata') or []:
            if entry.get('key') != CONTROL_KEY:
                continue
            value = entry.get('value')
            name = value.get('name') if isinstance(value, dict) else None
            keys = next((g for g, n in GROUPS.items() if n == name and g in ids), keys)
    ids.setdefault('media', DEFAULT_SINK)
    return ids, keys


def output(objects):
    """The default sink: what the volume groups currently play into."""
    name = None
    for obj in objects:
        for entry in obj.get('metadata') or []:
            if entry.get('key') == 'default.audio.sink' and isinstance(entry.get('value'), dict):
                name = entry['value'].get('name')
    for obj in objects:
        props = obj.get('info', {}).get('props', {})
        if name and obj.get('type') == 'PipeWire:Interface:Node' and props.get('node.name') == name:
            return {'name': name, 'id': str(obj['id']),
                    'description': props.get('node.description') or props.get('node.nick') or name,
                    'bluetooth': props.get('device.api') == 'bluez5' or name.startswith('bluez_output.')}
    return {'name': name or '', 'id': '', 'description': '', 'bluetooth': False}


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix('.tmp')
    tmp.write_text(json.dumps(state))
    tmp.replace(STATE)


def follow_output(ids, out):
    """Hold the media loopback at 100% while headphones play; restore it after."""
    if ids.get('media', DEFAULT_SINK) == DEFAULT_SINK:
        return
    state = load_state()
    was_bluetooth = state.get('bluetooth', False)
    if out['bluetooth'] == was_bluetooth:
        return
    if out['bluetooth']:
        state['speakerMedia'] = level(ids['media'])['percent']
        wpctl('set-volume', '-l', '1.0', ids['media'], '100%')
    elif 'speakerMedia' in state:
        wpctl('set-volume', '-l', '1.0', ids['media'], f"{state['speakerMedia']}%")
    state['bluetooth'] = out['bluetooth']
    save_state(state)


def level(target):
    result = wpctl('get-volume', target)
    match = re.search(r'^Volume:\s+([0-9]+(?:\.[0-9]+)?)', result)
    if not match:
        raise ValueError('No audio output')
    return {'available': True, 'percent': round(float(match[1]) * 100), 'muted': '[MUTED]' in result}


def parse(args, keys):
    action = args[0] if args else 'status'
    if action == 'status' and len(args) <= 1:
        return action, None, None
    if action in ('up', 'down', 'mute') and len(args) <= 2:
        return action, args[1] if len(args) == 2 else keys, None
    if action == 'set' and len(args) in (2, 3):
        if not args[1].isdigit() or not 0 <= int(args[1]) <= 100:
            raise ValueError('Volume must be between 0 and 100')
        return action, args[2] if len(args) == 3 else 'media', args[1]
    raise ValueError(USAGE)


def main(args):
    objects = pw_dump()
    ids, keys = targets(objects)
    out = output(objects)
    follow_output(ids, out)
    if out['bluetooth'] and out['id']:
        ids = {**ids, 'media': out['id']}
    action, group, percent = parse(args, keys)
    if group is not None:
        if group not in GROUPS:
            raise ValueError(f'Unknown volume group {group}')
        if group not in ids:
            raise ValueError(f'Volume group {group} is not available')
        target = ids[group]
        if action in ('up', 'down'):
            wpctl('set-volume', '-l', '1.0', target, '5%+' if action == 'up' else '5%-')
        elif action == 'mute':
            wpctl('set-mute', target, 'toggle')
        else:
            wpctl('set-volume', '-l', '1.0', target, percent + '%')
        if action == 'up' or (action == 'set' and int(percent) > 0):
            # Raising or dragging a volume means it should be heard, as on Android.
            wpctl('set-mute', target, '0')
    groups = {}
    for name in GROUPS:
        try:
            groups[name] = level(ids[name]) if name in ids else dict(UNAVAILABLE)
        except (OSError, ValueError, subprocess.SubprocessError):
            groups[name] = dict(UNAVAILABLE)
    if not groups['media']['available']:
        raise ValueError('No audio output')
    return {**groups['media'], 'keys': keys, 'changed': group, 'groups': groups, 'output': out}


if __name__ == '__main__':
    try:
        print(json.dumps(main(sys.argv[1:])))
    except (OSError, ValueError, subprocess.SubprocessError):
        print(json.dumps({**UNAVAILABLE, 'keys': 'media', 'changed': None, 'groups': {}, 'output': {}}))
        sys.exit(1)
