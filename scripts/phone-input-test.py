#!/usr/bin/env python3
"""Runs on the phone: reads the alert slider and plays bounded vibrations.

  slider           print the slider's position now
  watch SECONDS    print each slider change for that long
  pulse PERCENT MS vibrate once, 1 to 100 percent for 10 to 1000 ms

Uses only the kernel's input interfaces (EVIOCGABS, EVIOCSFF), as feedbackd
does. Vibrations are capped here as well as by the effect's own length.
"""
import fcntl
import os
import select
import struct
import sys
import time

ABS_SND_PROFILE = 0x22
EV_ABS, EV_FF = 0x03, 0x15
FF_RUMBLE = 0x50
PROFILES = {0: 'Silent', 1: 'Vibrate', 2: 'Ring'}


def ioc(direction, number, size):
    return (direction << 30) | (size << 16) | (ord('E') << 8) | number


def device(name):
    with open('/proc/bus/input/devices') as f:
        for line in f.read().split('\n\n'):
            if f'Name="{name}"' in line:
                for part in line.replace('=', ' ').split():
                    if part.startswith('event'):
                        return '/dev/input/' + part
    sys.exit(f'no input device named {name}')


def slider_value(fd):
    info = bytearray(24)
    fcntl.ioctl(fd, ioc(2, 0x40 + ABS_SND_PROFILE, 24), info)
    return struct.unpack('6i', info)[0]


def main(argv):
    action = argv[1] if len(argv) > 1 else ''
    if action == 'slider':
        fd = os.open(device('Alert slider'), os.O_RDONLY)
        value = slider_value(fd)
        print(f'slider: {PROFILES.get(value, value)}')
    elif action == 'watch':
        fd = os.open(device('Alert slider'), os.O_RDONLY | os.O_NONBLOCK)
        print(f'slider: {PROFILES.get(slider_value(fd), "?")}', flush=True)
        end = time.monotonic() + float(argv[2])
        while (left := end - time.monotonic()) > 0:
            if not select.select([fd], [], [], left)[0]:
                continue
            data = os.read(fd, 24 * 64)
            for i in range(0, len(data), 24):
                _, _, kind, code, value = struct.unpack('qqHHi', data[i:i + 24])
                if kind == EV_ABS and code == ABS_SND_PROFILE:
                    print(f'slider: {PROFILES.get(value, value)}', flush=True)
    elif action == 'pulse':
        percent = min(max(int(argv[2]), 1), 100)
        length = min(max(int(argv[3]), 10), 1000)
        fd = os.open(device('Awinic AW8697 haptics'), os.O_RDWR)
        # struct ff_effect (48 bytes on arm64): type, id, direction, trigger,
        # replay (length, delay), then the rumble magnitudes at offset 16.
        magnitude = 0xffff * percent // 100
        effect = bytearray(struct.pack('HhHHHHH2x', FF_RUMBLE, -1, 0, 0, 0, length, 0)
                           + struct.pack('HH', magnitude, 0) + bytes(28))
        fcntl.ioctl(fd, ioc(1, 0x80, 48), effect)
        effect_id = struct.unpack_from('h', effect, 2)[0]
        try:
            os.write(fd, struct.pack('qqHHi', 0, 0, EV_FF, effect_id, 1))
            time.sleep(length / 1000 + 0.1)
        finally:
            os.write(fd, struct.pack('qqHHi', 0, 0, EV_FF, effect_id, 0))
            fcntl.ioctl(fd, ioc(1, 0x81, 4), effect_id)
            os.close(fd)
        print(f'pulse: {percent}% for {length} ms')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
