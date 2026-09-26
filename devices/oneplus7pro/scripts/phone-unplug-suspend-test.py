#!/usr/bin/env python3
"""One supervised unplug/sleep/wake trial; expires after ten minutes waiting."""
from pathlib import Path
import subprocess
import time


def snapshot(label):
    print(label, time.time(), flush=True)
    for name in (
        '/proc/sys/kernel/random/boot_id',
        '/sys/class/power_supply/bq27541-0/uevent',
        '/sys/class/power_supply/pm8150b-charger/uevent',
        '/sys/kernel/debug/suspend_stats',
        '/sys/kernel/debug/wakeup_sources',
    ):
        print(name, Path(name).read_text(), flush=True)


def main():
    online = Path('/sys/class/power_supply/pm8150b-charger/online')
    if online.read_text().strip() != '1':
        raise SystemExit('Start this trial while plugged in.')
    print('ARMED: waiting up to 10 minutes for 10 seconds continuously unplugged', flush=True)
    deadline = time.monotonic() + 600
    unplugged = None
    while time.monotonic() < deadline:
        if online.read_text().strip() == '0':
            if unplugged is None:
                unplugged = time.monotonic()
            if time.monotonic() - unplugged >= 10:
                break
        else:
            unplugged = None
        time.sleep(1)
    else:
        raise SystemExit('Expired without sleeping; nothing remains armed.')
    snapshot('BEFORE')
    print('ENTERING: power button wakes; RTC fallback in 90 seconds', flush=True)
    result = subprocess.run(['/usr/local/sbin/guacamole-suspend', '--wake-after', '90'])
    snapshot('AFTER')
    print('SUSPEND_COMMAND_EXIT', result.returncode, flush=True)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
