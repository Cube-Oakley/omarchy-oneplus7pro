#!/usr/bin/env python3
"""Bluetooth for the mobile shell, through BlueZ (bluetoothd on the system bus).

Usage: bluetooth.py [status] | power on|off | scan [SECONDS]
       | pair|connect|disconnect|forget ADDRESS
Prints one JSON object: the status, plus ok and message for actions. Status
reads BlueZ's whole object tree in one D-Bus call. Actions use bluetoothctl.
Pairing registers a NoInputNoOutput agent, so headphones, speakers, mice and
controllers pair; devices that need a PIN or passkey (most keyboards) do not yet.
A board without a running controller can name a start command in device.json
("bluetoothStart"); "power on" runs it first.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ADDRESS = re.compile(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$')
DEVICE_CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omarchy-mobile/device.json'
USAGE = 'Usage: bluetooth.py [status] | power on|off | scan [SECONDS] | pair|connect|disconnect|forget ADDRESS'


def value(props, key, default=None):
    """Unwrap busctl's {"type": ..., "data": ...} variant."""
    entry = props.get(key)
    return entry.get('data', default) if isinstance(entry, dict) else default


def start_command():
    try:
        command = json.loads(DEVICE_CONFIG.read_text()).get('bluetoothStart')
    except (OSError, ValueError, AttributeError):
        return None
    return command if isinstance(command, str) and os.access(command, os.X_OK) else None


def unavailable(reason):
    return {'available': False, 'reason': reason, 'startable': start_command() is not None,
            'name': '', 'address': '', 'powered': None, 'discovering': False, 'devices': []}


def snapshot(objects):
    """Status from GetManagedObjects' a{oa{sa{sv}}} data (busctl --json=short)."""
    adapters = sorted(path for path, ifaces in objects.items() if 'org.bluez.Adapter1' in ifaces)
    if not adapters:
        return unavailable('No Bluetooth controller.')
    adapter_path = adapters[0]
    adapter = objects[adapter_path]['org.bluez.Adapter1']
    devices = []
    for path, ifaces in objects.items():
        props = ifaces.get('org.bluez.Device1')
        if props is None or not path.startswith(adapter_path + '/'):
            continue
        address = value(props, 'Address', '')
        name = value(props, 'Name')
        battery = value(ifaces.get('org.bluez.Battery1', {}), 'Percentage')
        devices.append({
            'address': address,
            'name': value(props, 'Alias') or name or address,
            # BlueZ aliases a nameless device to its address; the UI hides those.
            'named': bool(name),
            'paired': bool(value(props, 'Paired', False)),
            'trusted': bool(value(props, 'Trusted', False)),
            'connected': bool(value(props, 'Connected', False)),
            'icon': value(props, 'Icon', ''),
            'rssi': value(props, 'RSSI'),
            'battery': battery,
        })
    devices.sort(key=lambda d: (not d['connected'], not d['paired'],
                                -(d['rssi'] if d['rssi'] is not None else -999), d['name'].lower()))
    return {
        'available': True,
        'reason': '',
        'startable': False,
        'name': value(adapter, 'Alias') or value(adapter, 'Name', ''),
        'address': value(adapter, 'Address', ''),
        'powered': bool(value(adapter, 'Powered', False)),
        'discovering': bool(value(adapter, 'Discovering', False)),
        'devices': devices,
    }


def read_status():
    if not shutil.which('busctl'):
        return unavailable('busctl is not installed.')
    result = subprocess.run(['busctl', '--system', '--json=short', 'call', 'org.bluez', '/',
                             'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects'],
                            capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        return unavailable('Bluetooth is not running.')
    return snapshot(json.loads(result.stdout)['data'][0])


def ctl(*args, timeout=10):
    """Run bluetoothctl; returns (ok, last meaningful output line)."""
    result = subprocess.run(['bluetoothctl', *args], capture_output=True, text=True, timeout=timeout + 10)
    lines = [re.sub(r'\x1b\[[0-9;]*m', '', line).strip() for line in (result.stdout + result.stderr).splitlines()]
    lines = [line for line in lines if line and not line.startswith(('[CHG]', '[NEW]', '[DEL]', 'Agent'))]
    return result.returncode == 0, lines[-1] if lines else ''


def reason(line, name):
    """A readable failure for bluetoothctl's last line."""
    if not line or line.startswith('Attempting') or re.search(r'page-timeout|Host is down|not available', line, re.I):
        return f"Couldn't reach {name}. Make sure it is on and nearby."
    return line


def device(status, address):
    return next((d for d in status['devices'] if d['address'] == address), None)


def power(on):
    status = read_status()
    if not status['available'] and on:
        command = start_command()
        if not command:
            return status, False, status['reason']
        subprocess.run([command], capture_output=True, text=True, timeout=90)
        for _ in range(40):
            status = read_status()
            if status['available']:
                break
            time.sleep(0.5)
        if not status['available']:
            return status, False, 'Bluetooth did not start.'
    ok, line = ctl('power', 'on' if on else 'off')
    return read_status(), ok, '' if ok else line


def pair(address):
    if device(read_status(), address) is None:
        # BlueZ forgets unpaired devices shortly after a scan ends; find it again.
        ctl('--timeout', '8', 'scan', 'on', timeout=8)
    ok, line = ctl('--agent', 'NoInputNoOutput', '--timeout', '25', 'pair', address, timeout=25)
    found = device(read_status(), address)
    if not found or not found['paired']:
        return read_status(), False, line or 'Pairing failed.'
    ctl('trust', address)
    ok, line = ctl('--timeout', '15', 'connect', address, timeout=15)
    status = read_status()
    found = device(status, address)
    if found and found['connected']:
        return status, True, f"Connected to {found['name']}."
    return status, False, 'Paired. ' + reason(line, found['name'] if found else 'the device')


def act(args):
    action = args[0] if args else 'status'
    if action == 'status' and len(args) <= 1:
        return read_status(), True, ''
    if action == 'power' and len(args) == 2 and args[1] in ('on', 'off'):
        return power(args[1] == 'on')
    if action == 'scan' and len(args) <= 2:
        seconds = int(args[1]) if len(args) == 2 and args[1].isdigit() else 12
        seconds = max(3, min(seconds, 30))
        ok, line = ctl('--timeout', str(seconds), 'scan', 'on', timeout=seconds)
        return read_status(), ok, '' if ok else line
    if action in ('pair', 'connect', 'disconnect', 'forget') and len(args) == 2:
        address = args[1].upper()
        if not ADDRESS.match(address):
            raise ValueError('Invalid Bluetooth address')
        if action == 'pair':
            return pair(address)
        command = {'connect': 'connect', 'disconnect': 'disconnect', 'forget': 'remove'}[action]
        ok, line = ctl('--timeout', '15', command, address, timeout=15)
        status = read_status()
        found = device(status, address)
        if action == 'connect':
            ok = bool(found and found['connected'])
        elif action == 'disconnect':
            ok = not (found and found['connected'])
        else:
            ok = found is None or not found['paired']
        if ok:
            return status, True, ''
        return status, False, reason(line, found['name'] if found else 'the device') if action == 'connect' \
            else line or f'Could not {action}.'
    raise ValueError(USAGE)


def main(args):
    try:
        status, ok, message = act(args)
        print(json.dumps({**status, 'ok': ok, 'message': message}))
        return 0 if ok else 1
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError) as error:
        # A failed action must not make a working controller look unavailable.
        try:
            status = read_status()
        except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
            status = unavailable(str(error))
        print(json.dumps({**status, 'ok': False, 'message': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
