#!/usr/bin/env python3
"""Read-only inventory of Qualcomm software MCFG profiles (mcfg_sw.mbn).

Layout observed in these files (not from vendor documentation):
- 32-bit ELF; the LOAD segment starts with b"MCFG": u16 format, u16 type
  (1 = software), u32 item count, u16 carrier index, u16 spare, then a first
  item whose u32 value (bytes 20..24) is the configuration version.
- Near the end, b"MCFG_TRL", 5 bytes (00 02 00 00 01), then TLVs: u8 type, u16 length, value.
  1 = version, 3 = name, 4 = IIN list, 5 = version, 6 = MCC-MNC list, 7 = u32,
  8 = 32-byte digest, 9 = end. Lists: u8 flag, u8 count, then 4-byte entries
  (IIN as u32; PLMN as u16 MCC, u16 MNC).
Anything that does not fit is reported, not guessed.
"""
import hashlib
import struct
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])            # .../modem_pr/mcfg/configs
OUT = Path(sys.argv[2])             # manifest TSV
SW = ROOT / 'mcfg_sw'


def short(full):
    """Map a full mbn_sw.txt path to the 8-character truncated extraction path."""
    parts = full.split('/')
    return '/'.join(p.lower()[:8] if p != 'mcfg_sw.mbn' else p for p in parts)


def segment(data):
    """Size and SHA-1 of the ELF LOAD segment that holds the MCFG blob."""
    phoff, = struct.unpack_from('<I', data, 28)
    phentsize, phnum = struct.unpack_from('<HH', data, 42)
    for k in range(phnum):
        ptype, off, _, _, filesz = struct.unpack_from('<5I', data, phoff + k * phentsize)
        if ptype == 1 and data[off:off + 4] == b'MCFG':
            seg = data[off:off + filesz]
            return {'seg_size': str(filesz), 'seg_sha1': hashlib.sha1(seg).hexdigest()}
    return {'seg_size': '', 'seg_sha1': ''}


def parse(data):
    out = {'header_version': '', 'carrier_index': '', 'items': '', 'name': '', 'trl_version': '',
           'trl_version2': '', 'iins': '', 'plmns': '', 'type7': '', 'digest': '', 'notes': []}
    i = data.find(b'MCFG')
    if i < 0 or data[i:i + 8] == b'MCFG_TRL':
        out['notes'].append('no MCFG header')
    else:
        fmt, ctype, items, cidx = struct.unpack_from('<HHIH', data, i + 4)
        out['items'] = str(items)
        out['carrier_index'] = str(cidx)
        if ctype != 1:
            out['notes'].append(f'config type {ctype}')
        item_id, item_len = struct.unpack_from('<HH', data, i + 16)
        if item_len == 4:
            out['header_version'] = f'0x{struct.unpack_from("<I", data, i + 20)[0]:08x}'
        else:
            out['notes'].append(f'first item {item_id:#x} len {item_len}')
    t = data.rfind(b'MCFG_TRL')
    if t < 0:
        out['notes'].append('no MCFG_TRL')
        return out
    prefix = data[t + 8:t + 13]
    if prefix != bytes.fromhex('0002000001'):
        out['notes'].append(f'trailer prefix {prefix.hex()}')
    p = t + 13
    while p + 3 <= len(data):
        typ, length = data[p], struct.unpack_from('<H', data, p + 1)[0]
        val = data[p + 3:p + 3 + length]
        if typ == 9 or len(val) != length:
            break
        if typ == 1 and length == 4:
            out['trl_version'] = f'0x{struct.unpack("<I", val)[0]:08x}'
        elif typ == 5 and length == 4:
            out['trl_version2'] = f'0x{struct.unpack("<I", val)[0]:08x}'
        elif typ == 3:
            out['name'] = val.decode('ascii', 'replace').rstrip('\0')
        elif typ == 4 and length >= 2 and length == 2 + 4 * val[1]:
            out['iins'] = ','.join(str(x) for x in struct.unpack_from(f'<{val[1]}I', val, 2))
        elif typ == 6 and length >= 2 and length == 2 + 4 * val[1]:
            pairs = struct.unpack_from(f'<{2 * val[1]}H', val, 2)
            out['plmns'] = ','.join(f'{pairs[k]}-{pairs[k + 1]:03d}' for k in range(0, len(pairs), 2))
        elif typ == 7 and length == 4:
            out['type7'] = str(struct.unpack('<I', val)[0])
        elif typ == 8:
            out['digest'] = val.hex()
        else:
            out['notes'].append(f'tlv{typ}={val.hex()}')
        p += 3 + length
    return out


full_paths = [l.strip() for l in (SW / 'mbn_sw.txt').read_text().splitlines() if l.strip()]
oem = {l.strip() for l in (SW / 'oem_sw.txt').read_text().splitlines() if l.strip()}
dig = (SW / 'mbn_sw.dig').read_bytes()
print('mbn_sw.txt lines:', len(full_paths), 'oem_sw.txt lines:', len(oem))
print('mbn_sw.dig == sha256(mbn_sw.txt):', dig == hashlib.sha256((SW / 'mbn_sw.txt').read_bytes()).digest())

by_short = {}
for full in full_paths:
    by_short.setdefault(short(full.removeprefix('mcfg_sw/')), []).append(full)
files = sorted(p.relative_to(SW).as_posix() for p in SW.rglob('mcfg_sw.mbn'))
print('files found:', len(files))

cols = ['short_path', 'full_path', 'oem_list', 'size', 'sha256', 'sha1', 'seg_size', 'seg_sha1', 'name', 'carrier_index', 'items',
        'header_version', 'trl_version', 'trl_version2', 'type7', 'iins', 'plmns', 'digest', 'notes']
rows = []
unmapped, ambiguous = [], []
for rel in files:
    data = (SW / rel).read_bytes()
    info = parse(data)
    fulls = by_short.get(rel, [])
    if not fulls:
        unmapped.append(rel)
    elif len(fulls) > 1:
        ambiguous.append((rel, fulls))
    info['notes'] = ';'.join(info['notes'])
    rows.append({'short_path': rel, 'full_path': '|'.join(fulls),
                 'oem_list': 'yes' if f'mcfg_sw/{rel}' in oem else '',
                 'size': str(len(data)), 'sha256': hashlib.sha256(data).hexdigest(),
                 'sha1': hashlib.sha1(data).hexdigest(), **segment(data), **info})
listed_missing = [f for f in full_paths if short(f.removeprefix('mcfg_sw/')) not in set(files)]
OUT.parent.mkdir(parents=True, exist_ok=True)
with OUT.open('w') as fh:
    fh.write('\t'.join(cols) + '\n')
    for r in rows:
        fh.write('\t'.join(r[c] for c in cols) + '\n')
print('rows written:', len(rows))
print('unmapped files:', unmapped)
print('ambiguous short paths:', ambiguous)
print('listed but not extracted:', listed_missing)
print('parse notes:', sorted({r['notes'] for r in rows if r['notes']}))
print('no name:', [r['short_path'] for r in rows if not r['name']])
print('header!=trailer version:', sum(1 for r in rows if r['header_version'] and r['trl_version'] and r['header_version'] != r['trl_version']))
