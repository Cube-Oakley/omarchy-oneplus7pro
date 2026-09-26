#!/usr/bin/env python3
"""Ten-minute read-only timing trace; never changes networking or power policy."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import time


def emit(event, **values):
    print(json.dumps(dict(event=event, wall=time.time(),
                         boot=time.clock_gettime(time.CLOCK_BOOTTIME),
                         mono=time.monotonic(), **values)), flush=True)


def supplies():
    values = {}
    root = Path('/sys/class/power_supply')
    for name, attrs in [('pm8150b-charger', ('online', 'status')),
                        ('bq27541-0', ('status', 'capacity', 'current_now'))]:
        for attr in attrs:
            try:
                values[name + '/' + attr] = (root / name / attr).read_text().strip()
            except OSError:
                values[name + '/' + attr] = None
    return values


def main():
    commands = {
        'network': ['stdbuf', '-oL', 'nmcli', 'monitor'],
        'power': ['stdbuf', '-oL', 'udevadm', 'monitor', '--kernel',
                  '--subsystem-match=power_supply'],
        'kernel': ['stdbuf', '-oL', 'dmesg', '--follow-new'],
    }
    children = []
    selector = selectors.DefaultSelector()
    buffers = {}
    try:
        for name, command in commands.items():
            child = subprocess.Popen(command, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT,
                                     env=dict(os.environ, LC_ALL='C', SYSTEMD_IN_CHROOT='0'))
            children.append(child)
            selector.register(child.stdout, selectors.EVENT_READ, name)
            buffers[name] = b''
        deadline = time.clock_gettime(time.CLOCK_BOOTTIME) + 600
        next_sample = 0
        previous = None
        emit('started', expires_in_seconds=600, boot_id=Path(
            '/proc/sys/kernel/random/boot_id').read_text().strip())
        while time.clock_gettime(time.CLOCK_BOOTTIME) < deadline:
            for key, _ in selector.select(timeout=.5):
                name = key.data
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    emit('monitor_exit', source=name)
                    continue
                buffers[name] += chunk
                while b'\n' in buffers[name]:
                    line, buffers[name] = buffers[name].split(b'\n', 1)
                    line = line.decode(errors='replace')
                    if name != 'kernel' or any(word in line for word in (
                            'PM:', 'wlan0:', 'ath10k', 'Charging ', 'watchdog')):
                        emit('event', source=name, line=line)
            if time.monotonic() >= next_sample:
                current = supplies()
                if current != previous:
                    emit('supplies', values=current)
                    previous = current
                next_sample = time.monotonic() + 1
        emit('finished')
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
        for child in children:
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        selector.close()


if __name__ == '__main__':
    main()
