#!/usr/bin/env python3
"""Bounded Pixel RAM diagnostic: observe and W1C only DSIM underrun pending.

No timing, DMA, clocks or power programming. Counts observed pending episodes,
not exact interrupts (multiple underruns may coalesce between polling reads).
"""
import mmap
import os
from pathlib import Path
import struct
import time

assert Path('/sys/firmware/devicetree/base/compatible').read_bytes().split(b'\0')[0] == b'google,GS201 CHEETAH'
assert Path('/sys/bus/platform/drivers/pixel-scanout/pixel-scanout').exists()
assert Path('/sys/module/pixel_scanout/parameters/panel120').read_text().strip() == 'Y'
assert 'dsi_underruns' not in Path('/sys/kernel/debug/dri/0/pixel_scanout').read_text(), \
    'The driver owns underrun accounting; read its debugfs counters instead.'
reg = Path('/sys/firmware/devicetree/base/drmdsim@0x1C2C0000/reg').read_bytes()
assert struct.unpack('>III', reg[:12]) == (0, 0x1c2c0000, 0x300)
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
pmu = mmap.mmap(fd, 4096, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ, offset=0x18062000)
assert struct.unpack_from('<I', pmu, 0x204)[0] & 1
assert struct.unpack_from('<I', pmu, 0x284)[0] & 1
with mmap.mmap(fd, 4096, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ | mmap.PROT_WRITE, offset=0x1c2c0000) as dsi:
    def read(offset):
        return struct.unpack_from('<I', dsi, offset)[0]
    assert read(0) == 0x02060000 and read(0x4c) == 0x04887cff
    mask = 1 << 19
    print(f'initial_irq={read(0x50):08x} timer={read(0x88):08x} underrun_limit={read(0x34)}', flush=True)
    struct.pack_into('<I', dsi, 0x50, mask)
    count = 0
    start = time.monotonic()
    for second in range(10):
        while time.monotonic() - start < second + 1:
            if read(0x50) & mask:
                count += 1
                struct.pack_into('<I', dsi, 0x50, mask)
            time.sleep(0.001)
        print(f'elapsed={time.monotonic()-start:.3f} underrun_observations={count}', flush=True)
    print(f'final_irq={read(0x50):08x}', flush=True)
pmu.close()
os.close(fd)
