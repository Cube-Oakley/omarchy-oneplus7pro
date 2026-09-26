#!/usr/bin/env python3
"""Runs on the phone: restarts the mobile shell with the running shell's exact
environment, and stops the old shell's helper processes (nmcli, dbus-monitor
and udevadm monitors), which would otherwise be left running.

A hot reload keeps the previous copy's timers and probes running inside the
shell, so measure and hand over a freshly started shell.

Usage from the host: bash scripts/phone-ssh.sh 'python3 -' < scripts/phone-shell-restart.py
"""
import os
import signal
import subprocess
import sys
import time

PATTERN = '^quickshell -n -d -p /root/.config/quickshell/omarchy-mobile/shell.qml'


def shell_pids():
    return [int(pid) for pid in subprocess.run(['pgrep', '-f', PATTERN], capture_output=True,
                                               text=True).stdout.split()]


def main():
    pids = shell_pids()
    if len(pids) != 1:
        sys.exit(f'expected one running shell, found {pids}')
    pid = pids[0]
    env = dict(item.split('=', 1) for item in open(f'/proc/{pid}/environ').read().split('\0') if '=' in item)
    children = [int(child) for child in subprocess.run(['pgrep', '-P', str(pid)], capture_output=True,
                                                       text=True).stdout.split()]
    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        if not os.path.exists(f'/proc/{pid}'):
            break
        time.sleep(0.1)
    else:
        sys.exit('shell did not exit')
    for child in children:
        try:
            os.kill(child, signal.SIGTERM)
        except ProcessLookupError:
            pass
    subprocess.run(['setsid', 'quickshell', '-n', '-d', '-p', '/root/.config/quickshell/omarchy-mobile/shell.qml'],
                   env=env, cwd=env.get('HOME', '/root'), stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    time.sleep(4)
    print(f'old {pid} ({len(children)} helpers stopped), new {shell_pids()}')


if __name__ == '__main__':
    main()
