#!/usr/bin/env python3
"""Match resident PDC configs (from a read-only probe log) to the MCFG library."""
import csv
import re
import sys
from pathlib import Path

LOG, MANIFEST, SW = map(Path, sys.argv[1:4])
rows = list(csv.DictReader(MANIFEST.open(), delimiter='\t'))
blobs = {r['short_path']: (SW / r['short_path']).read_bytes() for r in rows}
residents = []
for line in LOG.read_text().splitlines():
    m = re.match(r'config (\d+) id=([0-9a-f]+)(?: version=(0x[0-9a-f]+) size=(\d+) description=(.*))?:?', line)
    if m:
        residents.append({'n': int(m[1]), 'id': m[2], 'version': m[3] or '', 'size': m[4] or '',
                          'desc': (m[5] or '').strip(), 'raw': line})
active = re.search(r'active=([0-9a-f]+)', LOG.read_text())[1]
print(f'residents: {len(residents)}; active: {active}')
out = []
for r in residents:
    ident = r['id']
    by_file = [x['short_path'] for x in rows if x['sha1'] == ident]
    by_seg = [x['short_path'] for x in rows if x['seg_sha1'] == ident]
    raw = bytes.fromhex(ident) if len(ident) % 2 == 0 else b''
    embedded = [p for p, b in blobs.items() if raw and (raw in b or ident.encode() in b)] if len(raw) >= 4 else []
    by_name = [x for x in rows if r['desc'] and x['name'].lower() == r['desc'].lower()]
    name_notes = []
    for x in by_name:
        v = 'version=' + ('match' if r['version'] in (x['trl_version'], x['header_version']) else
                          f"differs(lib {x['trl_version']})")
        size = r['size']
        sz = 'size=' + ('file' if size == x['size'] else 'segment' if size == x['seg_size'] else
                        f"differs(lib file {x['size']}, seg {x['seg_size']})")
        name_notes.append(f"{x['short_path']} [{v}, {sz}]")
    # A resident with no exact name match: try version alone, which is unique per config.
    by_version = [x['short_path'] for x in rows if r['version'] and r['version'] in (x['trl_version'], x['header_version'])]
    out.append({**r, 'active': ident == active, 'by_file': by_file, 'by_seg': by_seg, 'embedded': embedded,
                'by_name': name_notes, 'by_version': by_version})
    print(f"#{r['n']:>2} {ident} {r['desc'] or '(no info)':30} {r['version']:10} size={r['size']:>6}"
          f"{' ACTIVE' if ident == active else ''}")
    print(f"     id=file-sha1:{by_file or '-'} id=seg-sha1:{by_seg or '-'} id-embedded:{embedded or '-'}")
    print(f"     name:{name_notes or '-'}")
    if not name_notes:
        print(f"     same-version files:{by_version or '-'}")
