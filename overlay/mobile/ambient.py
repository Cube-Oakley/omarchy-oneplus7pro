#!/usr/bin/env python3
"""The always-on display's real off: while it shows, the panel goes fully off
face down or in a pocket, and the clock comes back when the phone is picked
up or taken out (omarchy-mobile-display ambient-sleep / ambient-wake).

  watch    follow the tilt and light through iio-sensor-proxy, and proximity
           only when it is dark and the phone is not lying flat (its infrared
           emitter shows through the panel as a dot), until killed
"""
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time

DISPLAY = str(Path.home() / '.local/bin/omarchy-mobile-display')
LINE = re.compile(r'(?:Tilt changed: |tilt: )([a-z-]+)|(?:Light changed: |value: )([0-9.]+)|'
                  r'(?:Proximity value changed: |near: )([01])')


class Pocket:
    """When the always-on display should sleep and wake. Pure: fed readings
    and times, returns 'sleep', 'wake' or None."""
    FACE_DOWN = 2.0   # seconds face down before the panel goes off
    DARK = 1.5        # seconds dark before proximity is asked
    DARK_LUX = 3.0
    LIT_LUX = 10.0

    def __init__(self):
        self.tilt = 'undefined'
        self.lux = None
        self.near = None
        self.asleep = None          # None, or the reason: 'face-down' or 'pocket'
        self.face_down_since = None
        self.dark_since = None

    def reading(self, tilt=None, lux=None, near=None, now=0.0):
        if tilt is not None:
            self.tilt = tilt
            self.face_down_since = (self.face_down_since or now) if tilt == 'face-down' else None
        if lux is not None:
            self.lux = lux
            self.dark_since = (self.dark_since or now) if lux < self.DARK_LUX else None
        if near is not None:
            self.near = near

    def wants_proximity(self, now):
        if self.asleep == 'pocket':
            return True
        flat = self.tilt in ('face-up', 'face-down')
        return not flat and self.dark_since is not None and now - self.dark_since >= self.DARK

    def step(self, now):
        if self.asleep is None:
            if self.face_down_since is not None and now - self.face_down_since >= self.FACE_DOWN:
                self.asleep = 'face-down'
                return 'sleep'
            if self.near and self.wants_proximity(now):
                self.asleep = 'pocket'
                return 'sleep'
            return None
        if self.asleep == 'face-down' and self.tilt != 'face-down':
            return self.wake()
        if self.asleep == 'pocket' and (self.near is False or (self.lux or 0) > self.LIT_LUX):
            return self.wake()
        return None

    def wake(self):
        self.asleep = None
        self.near = None
        return 'wake'


def die_with_parent():
    import ctypes
    ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


def sensor_ready(has):
    try:
        out = subprocess.run(['busctl', '--system', 'get-property', 'net.hadess.SensorProxy',
                              '/net/hadess/SensorProxy', 'net.hadess.SensorProxy', has],
                             capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return out.strip() == 'b true'


def monitor(*sensors):
    return subprocess.Popen(['stdbuf', '-oL', 'monitor-sensor', *sensors], stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)


def watch():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while not (sensor_ready('HasAccelerometer') and sensor_ready('HasAmbientLight')):
        time.sleep(3)
    pocket, motion, proximity = Pocket(), monitor('--accel', '--light'), None
    pending = {}
    try:
        while motion.poll() is None:
            now = time.monotonic()
            want = pocket.wants_proximity(now)
            if want and proximity is None and sensor_ready('HasProximity'):
                proximity = monitor('--proximity')
            elif not want and proximity is not None:
                proximity.terminate()
                proximity, pocket.near = None, None
            pipes = [motion.stdout] + ([proximity.stdout] if proximity else [])
            for pipe in select.select(pipes, [], [], 0.5)[0]:
                data = os.read(pipe.fileno(), 4096)
                if not data:
                    return  # the sensor service went away: the shell starts this again
                if b'vanished' in data:
                    return
                *lines, pending[pipe] = (pending.get(pipe, b'') + data).split(b'\n')
                for line in lines:
                    match = LINE.search(line.decode(errors='replace'))
                    if match:
                        tilt, lux, near = match.groups()
                        pocket.reading(tilt=tilt, lux=float(lux) if lux else None,
                                       near=(near == '1') if near else None, now=time.monotonic())
            action = pocket.step(time.monotonic())
            if action:
                subprocess.run([DISPLAY, 'ambient-' + action], timeout=15)
                print(action, pocket.asleep or '', flush=True)
    finally:
        motion.terminate()
        if proximity:
            proximity.terminate()


def main(args):
    if args == ['watch']:
        watch()
        return
    sys.exit(__doc__.strip().split('\n\n', 1)[1])


if __name__ == '__main__':
    main(sys.argv[1:])
