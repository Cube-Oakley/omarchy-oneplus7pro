#!/usr/bin/env python3
"""Local clipboard history. The store is the sync surface; the UI is not.

Record shape is stable for a later pairing daemon: id, created, origin, mime,
text, pinned. Origin is "local" until a peer writes its own device id.
This helper never logs clipboard contents.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'omarchy-mobile/clipboard.json'
MAX_ITEMS = 50
MAX_TEXT = 64 * 1024


def load(path=STATE):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        data = {}
    items = data.get('items') if isinstance(data, dict) else None
    if not isinstance(items, list):
        items = []
    return {'version': 1, 'items': [row for row in items if isinstance(row, dict) and row.get('id')]}


def save(data, path=STATE):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    payload = {'version': 1, 'items': data['items']}
    temp.write_text(json.dumps(payload))
    temp.replace(path)


def public_item(item):
    text = item.get('text') or ''
    preview = text.replace('\n', ' ').strip()
    if len(preview) > 80:
        preview = preview[:79] + '…'
    return {
        'id': item['id'],
        'created': item.get('created'),
        'origin': item.get('origin') or 'local',
        'mime': item.get('mime') or ['text/plain'],
        'text': text,
        'preview': preview or 'Empty clip',
        'pinned': bool(item.get('pinned')),
    }


def public(data, current=None):
    return {
        'available': True,
        'count': len(data['items']),
        'current': current,
        'items': [public_item(item) for item in data['items']],
    }


def find(data, item_id):
    return next((item for item in data['items'] if item.get('id') == item_id), None)


def record_text(data, text, origin='local', mime=None, now=None):
    if not isinstance(text, str):
        raise ValueError('Clipboard text required')
    if any(c in text for c in '\0'):
        raise ValueError('Clipboard text cannot contain NUL')
    text = text[:MAX_TEXT]
    if not text.strip():
        return data, None
    now = time.time() if now is None else now
    origin = origin if isinstance(origin, str) and re.fullmatch(r'[A-Za-z0-9._:-]{1,64}', origin) else 'local'
    types = mime if isinstance(mime, list) and mime else ['text/plain']
    existing = next((item for item in data['items'] if item.get('text') == text), None)
    if existing:
        existing['created'] = now
        existing['origin'] = origin
        item = existing
    else:
        item = {
            'id': uuid.uuid4().hex,
            'created': now,
            'origin': origin,
            'mime': types,
            'text': text,
            'pinned': False,
        }
    ordered = [item] + [row for row in data['items'] if row is not item]
    pinned = sum(1 for row in ordered if row.get('pinned'))
    room = max(0, MAX_ITEMS - pinned)
    kept, unpinned = [], 0
    for row in ordered:
        if row.get('pinned'):
            kept.append(row)
        elif unpinned < room:
            kept.append(row)
            unpinned += 1
    data['items'] = kept[:MAX_ITEMS]
    return data, item


def wl_copy(text):
    subprocess.run(['wl-copy', '--type', 'text/plain'], input=text, check=True, timeout=3, text=True)


def wl_paste():
    result = subprocess.run(['wl-paste', '--no-newline', '--type', 'text'], capture_output=True, text=True, timeout=3)
    if result.returncode != 0:
        raise ValueError('Clipboard is empty')
    return result.stdout


def send_paste():
    subprocess.run(['hyprctl', 'dispatch', 'sendshortcut', 'CTRL,V,'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)


def action(name, request, path=STATE, copier=wl_copy, paster=wl_paste, paste_key=send_paste):
    data = load(path)
    if name in ('status', 'history', None, ''):
        current = None
        try:
            current = paster()
        except (OSError, ValueError, subprocess.SubprocessError):
            current = None
        result = public(data, current)
        if name == 'history':
            return result
        return result
    if name == 'record':
        data, item = record_text(data, request.get('text', ''), origin=request.get('origin', 'local'),
                                 mime=request.get('mime'))
        save(data, path)
        return {'ok': True, 'id': item['id'] if item else None, **public(data)}
    if name == 'ingest':
        text = paster()
        data, item = record_text(data, text)
        save(data, path)
        return {'ok': True, 'id': item['id'] if item else None, 'count': len(data['items'])}
    if name == 'clear':
        data['items'] = [row for row in data['items'] if row.get('pinned')]
        save(data, path)
        return {'ok': True, **public(data)}
    item = find(data, request.get('id', ''))
    if not item:
        raise ValueError('Choose a clipboard item again')
    if name == 'copy':
        copier(item['text'])
        return {'ok': True, **public(data, item['text'])}
    if name == 'paste':
        copier(item['text'])
        paste_key()
        return {'ok': True, **public(data, item['text'])}
    if name == 'pin':
        item['pinned'] = not item.get('pinned')
        save(data, path)
        return {'ok': True, **public(data)}
    if name == 'delete':
        data['items'] = [row for row in data['items'] if row is not item]
        save(data, path)
        return {'ok': True, **public(data)}
    raise ValueError('Unknown clipboard action')


def read_request(name, argv, stdin):
    request = {}
    if len(argv) == 2 and name in ('copy', 'paste', 'pin', 'delete'):
        request = {'id': argv[1]}
    stream = stdin
    if stream is None and name in ('record', 'copy', 'paste', 'pin', 'delete') and not sys.stdin.isatty():
        stream = sys.stdin
    if stream is None:
        return request
    try:
        incoming = json.load(stream)
    except json.JSONDecodeError as error:
        raise ValueError('Clipboard request was not JSON') from error
    if not isinstance(incoming, dict):
        raise ValueError('Clipboard request was not JSON')
    request.update(incoming)
    return request


def main(argv=None, stdin=None, path=STATE):
    argv = sys.argv[1:] if argv is None else argv
    name = argv[0] if argv else 'status'
    return action(name, read_request(name, argv, stdin), path=path)


if __name__ == '__main__':
    try:
        result = main()
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {'available': False, 'ok': False, 'error': 'Clipboard request failed'}
    print(json.dumps(result))
