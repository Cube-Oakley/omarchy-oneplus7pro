#!/usr/bin/env python3
"""Explicit native5 suspend command. No automatic idle or power-key policy."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time


def read(path):
    return Path(path).read_text().strip()


def run(*args):
    subprocess.run(args, check=True, timeout=30)


def failures():
    return {line.split(":")[0]: int(line.split(":")[1])
            for line in read('/sys/kernel/debug/suspend_stats').splitlines()
            if line.startswith('failed_') or line.startswith('fail:')}


def prerequisites():
    if '-sm8150-codex-native5-' not in os.uname().release:
        raise RuntimeError('This command requires the native5 resume fixes.')
    if read('/sys/power/mem_sleep') != '[s2idle]':
        raise RuntimeError('Unexpected sleep mode.')
    if read('/sys/class/rtc/rtc0/device/power/wakeup') != 'enabled':
        raise RuntimeError('RTC wake is unavailable.')
    key = '/sys/bus/platform/devices/c440000.spmi:pmic@0:pon@800:pwrkey/power/wakeup'
    if read(key) != 'enabled':
        raise RuntimeError('Power-button wake is unavailable.')
    if read('/sys/class/power_supply/pm8150b-charger/online') != '0':
        raise RuntimeError('Unplug before sleeping: charging pauses during suspend.')
    if int(read('/sys/class/power_supply/bq27541-0/capacity')) < 10:
        raise RuntimeError('Charge the battery before this bring-up sleep test.')
    if read('/sys/class/rtc/rtc0/wakealarm'):
        raise RuntimeError('An RTC alarm is already scheduled.')


def restore(old_async, alarm_armed, display):
    errors = []
    try:
        Path('/sys/power/pm_async').write_text(old_async + '\n')
    except OSError as error:
        errors.append(str(error))
    commands = []
    if alarm_armed:
        commands.append(['rtcwake', '--device', '/dev/rtc0', '--mode', 'disable'])
    # Always attempt display restoration, even if RTC or input cleanup fails.
    commands.extend([
        ['env', 'SYSTEMD_IN_CHROOT=0', 'udevadm', 'trigger', '--action=add', '--subsystem-match=input'],
        ['env', 'SYSTEMD_IN_CHROOT=0', 'udevadm', 'settle', '--timeout=10'],
        [display, 'on'],
    ])
    for command in commands:
        try:
            run(*command)
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError('Resume cleanup needs attention: ' + '; '.join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check readiness without sleeping')
    parser.add_argument('--wake-after', type=int, help='Optional RTC fallback, 10 to 600 seconds')
    args = parser.parse_args()
    if args.wake_after is not None and not 10 <= args.wake_after <= 600:
        parser.error('--wake-after must be between 10 and 600 seconds')
    with open('/run/guacamole-suspend.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        prerequisites()
        if args.check:
            print('Ready for explicit s2idle; Power wakes the phone.')
            return
        os.environ['XDG_RUNTIME_DIR'] = '/run/user/0'
        os.environ['WAYLAND_DISPLAY'] = 'wayland-1'
        display = '/root/.local/bin/omarchy-mobile-display'
        before = failures()
        old_async = read('/sys/power/pm_async')
        alarm_armed = False
        started = None
        try:
            Path('/sys/power/pm_async').write_text('0\n')
            run(display, 'off')
            os.sync()
            prerequisites()
            if args.wake_after:
                run('rtcwake', '--device', '/dev/rtc0', '--mode', 'no',
                    '--seconds', str(args.wake_after), '--utc')
                alarm_armed = True
            # Abort if a wake event races the transition, using the kernel's
            # wakeup-count handshake rather than ignoring pending input.
            count = read('/sys/power/wakeup_count')
            Path('/sys/power/wakeup_count').write_text(count + '\n')
            started = (time.clock_gettime(time.CLOCK_BOOTTIME), time.monotonic())
            Path('/sys/power/state').write_text('mem\n')
        finally:
            restore(old_async, alarm_armed, display)
        after = failures()
        record = {'time': time.time(), 'before': before, 'after': after}
        if started:
            record['suspended_seconds'] = ((time.clock_gettime(time.CLOCK_BOOTTIME) - started[0])
                                           - (time.monotonic() - started[1]))
        log = Path('/root/.local/state/omarchy-mobile/suspend.log')
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('a') as stream:
            stream.write(json.dumps(record) + '\n')
        if after != before:
            raise RuntimeError('A device failed to resume; inspect the suspend log before retrying.')
        print('Awake. Input rediscovery completed.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
