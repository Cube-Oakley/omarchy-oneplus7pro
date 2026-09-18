#!/usr/bin/env python3
"""Supervised unplugged screen-off versus s2idle comparison; no persistent policy."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

BATTERY = Path('/sys/class/power_supply/bq27541-0')
ONLINE = Path('/sys/class/power_supply/pm8150b-charger/online')
RUNTIME = Path('/run/user/0')
DISPLAY = '/root/.local/bin/omarchy-mobile-display'


def read(path):
    return Path(path).read_text().strip()


def emit(event, **values):
    print(json.dumps(dict(event=event, utc=time.time(), **values)), flush=True)


def sample():
    values = {name: int(read(BATTERY / name)) for name in
              ('charge_now', 'current_now', 'voltage_now', 'capacity', 'temp')}
    values.update(online=int(read(ONLINE)), boot=time.clock_gettime(time.CLOCK_BOOTTIME),
                  mono=time.monotonic())
    return values


def validate(values):
    if values['online'] != 0:
        raise RuntimeError('Cable reconnected; comparison cancelled')
    if values['capacity'] < 20 or not 150 <= values['temp'] <= 380:
        raise RuntimeError('Battery outside measurement range')


def summarize(start, end):
    elapsed = end['boot'] - start['boot']
    if elapsed <= 0 or start['online'] or end['online']:
        raise ValueError('Invalid unplugged measurement interval')
    # charge_now is microamp-hours. Includes transition/recovery cost, not an
    # instantaneous sleeping current. One 1 mAh gauge step is 12 mA over 5 min.
    used = start['charge_now'] - end['charge_now']
    if used < 0:
        raise ValueError('Gauge charge increased; interval is not a valid drain estimate')
    return dict(seconds=elapsed, charge_used_uAh=used,
                interval_average_mA=used * 3.6 / elapsed,
                suspended_seconds=max(0, elapsed - (end['mono'] - start['mono'])),
                approximate_1mAh_resolution_mA=3600 / elapsed)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=20)


def display_on():
    monitors = json.loads(run('hyprctl', '-i', '0', '-j', 'monitors').stdout)
    if not monitors:
        raise RuntimeError('Compositor has no monitor')
    return any(monitor['dpmsStatus'] for monitor in monitors)


def wait_unplug():
    if read(ONLINE) != '1':
        raise RuntimeError('Arm while plugged in')
    emit('armed', expires_in_seconds=600)
    deadline = time.monotonic() + 600
    since = None
    while time.monotonic() < deadline:
        if read(ONLINE) == '0':
            since = since or time.monotonic()
            if time.monotonic() - since >= 10:
                return
        else:
            since = None
        time.sleep(1)
    raise RuntimeError('Expired without unplugging')


def idle(seconds, phase):
    start = sample()
    validate(start)
    stats = read('/sys/kernel/debug/suspend_stats')
    emit(phase + '-start', sample=start)
    end_at = time.monotonic() + seconds
    next_sample = time.monotonic() + 30
    while time.monotonic() < end_at:
        # Power can restore DPMS during this phase, cancelling the trial.
        if read(ONLINE) != '0' or display_on():
            raise RuntimeError('Idle interrupted by cable or display wake')
        if read('/sys/kernel/debug/suspend_stats') != stats:
            raise RuntimeError('Unexpected suspend during idle baseline')
        if time.monotonic() >= next_sample:
            values = sample()
            validate(values)
            emit(phase + '-sample', sample=values)
            next_sample += 30
        time.sleep(2)
    end = sample()
    validate(end)
    emit(phase + '-end', sample=end, summary=summarize(start, end))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=300)
    args = parser.parse_args()
    if not 120 <= args.seconds <= 600:
        parser.error('--seconds must be 120 to 600')
    os.environ.update(XDG_RUNTIME_DIR=str(RUNTIME), WAYLAND_DISPLAY='wayland-1')
    with open('/run/guacamole-idle-measure.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        wait_unplug()
        run('/usr/local/sbin/guacamole-suspend', '--check')
        try:
            run(DISPLAY, 'off')
            idle(60, 'settle')
            idle(args.seconds, 'screen-off-idle')
            with (RUNTIME / 'omarchy-mobile-power.lock').open('w') as power_lock:
                fcntl.flock(power_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                start = sample()
                validate(start)
                if display_on():
                    raise RuntimeError('User woke display before suspend phase')
                emit('suspend-start', sample=start)
                try:
                    # Suspend duration is controlled by the hardware RTC.
                    result = subprocess.run(['/usr/local/sbin/guacamole-suspend',
                                             '--wake-after', str(args.seconds)])
                    end = sample()
                    validate(end)
                    summary = summarize(start, end)
                    emit('suspend-end', sample=end, summary=summary,
                         exit_code=result.returncode,
                         full_interval=result.returncode == 0 and
                         summary['suspended_seconds'] >= args.seconds * .9)
                    if result.returncode:
                        raise RuntimeError('Suspend failed; inspect PM counters')
                finally:
                    # Ignore any queued wake release after this direct trial.
                    (RUNTIME / 'omarchy-mobile-power.json').write_text(
                        json.dumps({'ignore_until': time.monotonic() + 2}))
            emit('finished', note='Screen restored; reconnect USB to collect results')
        finally:
            run(DISPLAY, 'on')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        emit('aborted', reason=str(error))
        raise SystemExit(1)
