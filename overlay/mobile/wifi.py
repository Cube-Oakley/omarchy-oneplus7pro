#!/usr/bin/env python3
"""Portable NetworkManager status and explicit user-requested Wi-Fi actions."""
import json
import os
import re
import subprocess
import sys


def nmcli(*args, password=None, wait=3):
    return subprocess.run(['nmcli', '--wait', str(wait), '-t', *args],
                          input=None if password is None else password + '\n',
                          check=True, capture_output=True, text=True, timeout=wait + 5,
                          env=dict(os.environ, LC_ALL='C')).stdout


def split_fields(line):
    fields, word, escaped = [], '', False
    for ch in line:
        if escaped:
            word += ch
            escaped = False
        elif ch == '\\': escaped = True
        elif ch == ':': fields.append(word); word = ''
        else: word += ch
    fields.append(word)
    return fields


def interfaces():
    return [r[0] for r in (split_fields(l) for l in nmcli('-f', 'DEVICE,TYPE', 'device').splitlines())
            if len(r) == 2 and r[1] == 'wifi']


def detail(interface):
    text = nmcli('-f', 'GENERAL,IP4,IP6', 'device', 'show', interface)
    result = {}
    for line in text.splitlines():
        row = split_fields(line)
        if len(row) >= 2: result[row[0]] = ':'.join(row[1:])
    return result


def networks(interface):
    rows = []
    for line in nmcli('-f', 'IN-USE,BSSID,SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list',
                      'ifname', interface, '--rescan', 'no').splitlines():
        r = split_fields(line)
        if len(r) != 5 or not r[2]: continue
        rows.append(dict(active=r[0] == '*', bssid=r[1], ssid=r[2],
                         signal=int(r[3]), security=r[4]))
    # Multiple APs for one SSID remain NetworkManager's choice after connection.
    unique = {}
    for row in sorted(rows, key=lambda r: (r['active'], r['signal']), reverse=True):
        unique.setdefault((row['ssid'], row['security']), row)
    return list(unique.values())


def status():
    devices = interfaces()
    if not devices: return {'available': False}
    states = [(i, detail(i)) for i in devices]
    interface, info = next(((i, d) for i, d in states if d.get('GENERAL.STATE', '').startswith('100')),
                           states[0])
    connected = info.get('GENERAL.STATE', '').startswith('100')
    active = next((r for r in networks(interface) if r['active']), {}) if connected else {}
    values = lambda prefix: [v for k,v in info.items() if k.startswith(prefix) and v]
    return dict(available=True, interface=interface, connected=connected,
                connection=info.get('GENERAL.CONNECTION', ''), ssid=active.get('ssid', ''),
                signal=active.get('signal'), ipv4=values('IP4.ADDRESS'), ipv6=values('IP6.ADDRESS'),
                gateway=info.get('IP4.GATEWAY', ''), dns=values('IP4.DNS') + values('IP6.DNS'))


def action(name, request):
    interface = request.get('interface', '')
    if interface not in interfaces(): raise ValueError('Wi-Fi interface unavailable')
    if name in ('scan', 'list'):
        if name == 'scan': nmcli('device', 'wifi', 'rescan', 'ifname', interface, wait=10)
        return dict(ok=True, networks=networks(interface))
    if name == 'disconnect':
        nmcli('device', 'disconnect', interface, wait=10)
        return {'ok': True}
    if name == 'connect':
        bssid = request.get('bssid', '')
        if not re.fullmatch(r'(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}', bssid):
            raise ValueError('Choose a nearby network again')
        password = request.get('password', '')
        if not isinstance(password, str) or any(c in password for c in '\r\n\0'):
            raise ValueError('Password must be a single line')
        # --ask reads stdin: credentials never appear in argv, shell text or logs.
        nmcli('--ask', 'device', 'wifi', 'connect', bssid, 'ifname', interface,
              password=password, wait=35)
        return {'ok': True}
    raise ValueError('Unknown network action')


if __name__ == '__main__':
    try:
        result = status() if len(sys.argv) == 1 else action(sys.argv[1], json.load(sys.stdin))
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {'available': False} if len(sys.argv) == 1 else {
            'ok': False, 'error': 'Network request failed. Check the password or try scanning again.'}
    print(json.dumps(result))
