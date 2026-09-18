#!/usr/bin/env python3
"""Bounded probe of the documented guacamole gauge only; no bus scan or NVM writes."""
import ctypes as C
import json
import os
from pathlib import Path
import time

matches = [p for p in Path('/sys/bus/i2c/devices').glob('i2c-*')
           if '/ac0000.geniqup/a80000.i2c/' in str(p.resolve())]
if len(matches) != 1:
    raise SystemExit('Expected one guacamole I2C8 adapter')
bus = matches[0].name.split('-')[1]
if Path(f'/sys/bus/i2c/devices/{bus}-0055').exists():
    raise SystemExit('Gauge already instantiated; use its driver instead')


class Msg(C.Structure):
    _fields_ = [('addr', C.c_uint16), ('flags', C.c_uint16),
                ('len', C.c_uint16), ('buf', C.POINTER(C.c_ubyte))]


class Transfer(C.Structure):
    _fields_ = [('msgs', C.POINTER(Msg)), ('nmsgs', C.c_uint32)]


libc = C.CDLL(None, use_errno=True)
fd = os.open(f'/dev/i2c-{bus}', os.O_RDWR)


def transfer(write, read=0):
    out = (C.c_ubyte * len(write))(*write)
    incoming = (C.c_ubyte * read)()
    messages = [Msg(0x55, 0, len(write), out)]
    if read:
        messages.append(Msg(0x55, 1, read, incoming))
    array = (Msg * len(messages))(*messages)
    result = libc.ioctl(fd, 0x0707, C.byref(Transfer(array, len(messages))))
    if result < 0:
        err = C.get_errno()
        raise OSError(err, os.strerror(err))
    if result != len(messages):
        raise OSError('Incomplete I2C transfer')
    return int.from_bytes(bytes(incoming), 'little')


def query(command):
    # Only sealed-access identity queries, never reset/unseal/config commands.
    assert command in (1, 2)
    transfer(bytes([0, command, 0]))
    time.sleep(0.01)
    return transfer(b'\0', 2)


try:
    device = query(1)
    firmware = query(2)
    print(json.dumps({'bus': bus, 'address': '0x55',
                      'device_type': hex(device), 'firmware': hex(firmware)}), flush=True)
    if device != 0x0541:
        raise SystemExit('Variant needs investigation; no measurement decode attempted')
    registers = {'temperature_dK': 0x06, 'voltage_mV': 0x08, 'flags': 0x0a,
                 'remaining_mAh': 0x10, 'full_mAh': 0x12, 'current_raw': 0x14,
                 'cycles': 0x2a, 'capacity_percent': 0x2c}
    values = {name: transfer(bytes([register]), 2) for name, register in registers.items()}
    values['temperature_C'] = round(values['temperature_dK'] / 10 - 273.15, 2)
    raw = values['current_raw']
    values['current_mA'] = raw if raw < 32768 else raw - 65536
    print(json.dumps(values), flush=True)
finally:
    os.close(fd)
