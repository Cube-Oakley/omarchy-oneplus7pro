#!/usr/bin/env python3
"""Check firmware bounds, memory preservation and the staged module closure."""
from pathlib import Path
import struct
import subprocess
import os

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('RADIO_OUTPUT', ROOT / 'out/wifi-desktop-test'))
NAME = os.environ.get('RADIO_TEST_NAME', 'native4')
assert NAME in ('native4', 'native5')
DTB = OUT / f'{NAME}.dtb'
BASE = ROOT / 'out/checkpoints/20260917-native3-verified/embedded.dtb'

def fdt(dtb, option, node, *prop):
    return subprocess.check_output(['fdtget', option, str(dtb), node, *prop], text=True).strip()

def symbol(dtb, label):
    return fdt(dtb, '-ts', '/__symbols__', label)

def regs(dtb, path):
    cells = [int(x, 16) for x in fdt(dtb, '-tx', path, 'reg').split()]
    assert len(cells) % 4 == 0
    return [(cells[i] << 32 | cells[i+1], cells[i+2] << 32 | cells[i+3]) for i in range(0, len(cells), 4)]

def reservations(dtb):
    regions = []
    for child in fdt(dtb, '-l', '/reserved-memory').splitlines():
        path = '/reserved-memory/' + child
        props = fdt(dtb, '-p', path).splitlines()
        if 'status' in props and fdt(dtb, '-ts', path, 'status') == 'disabled':
            continue
        if 'reg' in props:
            regions.extend((a, a+n) for a,n in regs(dtb, path))
    return regions

def union(regions):
    result = []
    for start, end in sorted(regions):
        if result and start <= result[-1][1]:
            result[-1] = (result[-1][0], max(result[-1][1], end))
        else:
            result.append((start, end))
    return result

guards = [(0xf2900000, 0xf2901000), (0xf2b01000, 0xf2b02000)]
assert union(reservations(BASE) + guards) == union(reservations(DTB)), 'Unexpected RAM ownership change'
regions = sorted(reservations(DTB))
for first, second in zip(regions, regions[1:]):
    assert first[1] <= second[0], ('Overlapping reservations', first, second)
for label in ('gpu_mem', 'ipa_fw_mem', 'ipa_gsi_mem', 'wlan_mem', 'rmtfs_mem'):
    assert regs(BASE, symbol(BASE, label)) == regs(DTB, symbol(DTB, label)), label
for label in ('venus_mem', 'slpi_mem', 'remoteproc_slpi', 'remoteproc_adsp', 'remoteproc_cdsp'):
    assert fdt(DTB, '-ts', symbol(DTB, label), 'status') == 'disabled', label

mdt = ROOT / '.work/guacamole-radio-firmware/image/modem.mdt'
data = mdt.read_bytes()
assert data[:6] == b'\x7fELF\x01\x01'
phoff = struct.unpack_from('<I', data, 28)[0]
size, count = struct.unpack_from('<HH', data, 42)
start, length = regs(DTB, symbol(DTB, 'mpss_mem'))[0]
for i in range(count):
    kind, offset, virt, phys, filesz, memsz, flags, alignment = struct.unpack_from('<8I', data, phoff + i*size)
    if filesz:
        assert mdt.with_suffix(f'.b{i:02d}').stat().st_size == filesz, i
    if kind == 1 and memsz and (flags >> 24 & 7) != 2:
        assert start <= phys and phys + memsz <= start + length, ('Modem segment outside reservation', i)

modules = list((OUT / 'modules').glob('*.ko'))
names = {p.stem.replace('-', '_') for p in modules}
for path in modules:
    version = subprocess.check_output(['modinfo', '-F', 'vermagic', str(path)], text=True)
    assert f'-sm8150-codex-{NAME}-' in version, path
    deps = subprocess.check_output(['modinfo', '-F', 'depends', str(path)], text=True).strip().split(',')
    assert all(not dep or dep in names for dep in deps), (path, deps)
print('PASS: all modem ELF segments fit, reservations do not overlap, original reserved RAM')
print('      preserved plus guard pages, GPU/IPA/WLAN unchanged, matching module dependency closure')
