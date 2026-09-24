#!/usr/bin/env python3
"""Extract named partitions from an A/B OTA zip, local or remote.

Reads the zip's central directory, then payload.bin's manifest, then only the
data of the wanted partitions' operations; a remote zip is read with HTTP
range requests, so it is never downloaded whole.
Full (non-delta) payloads only: REPLACE, REPLACE_BZ, REPLACE_XZ and ZERO.
Every operation's SHA-256 and each partition's final hash are checked.

Usage: fetch_ota_partitions.py URL|ZIP OUTDIR PARTITION [PARTITION ...]
       fetch_ota_partitions.py URL|ZIP --list
"""
import bz2
import hashlib
import lzma
import os
import struct
import sys
import urllib.request

UA = {"User-Agent": "omarchy-oneplus7pro fetch_ota_partitions"}


def fetch(url, start, length):
    if not url.startswith(("http://", "https://")):
        with open(url, "rb") as f:
            f.seek(start)
            data = f.read(length)
        if len(data) != length:
            sys.exit("short read at %d" % start)
        return data
    req = urllib.request.Request(url, headers={**UA, "Range": "bytes=%d-%d" % (start, start + length - 1)})
    with urllib.request.urlopen(req, timeout=300) as r:
        if r.status != 206:
            sys.exit("server ignored the range request (HTTP %d)" % r.status)
        data = r.read()
    if len(data) != length:
        sys.exit("short read at %d: %d of %d" % (start, len(data), length))
    return data


def total_size(url):
    if not url.startswith(("http://", "https://")):
        return os.path.getsize(url)
    req = urllib.request.Request(url, headers={**UA, "Range": "bytes=0-0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return int(r.headers["Content-Range"].split("/")[1])


def payload_offset(url):
    """Offset of payload.bin's data in the zip (it is stored, not deflated)."""
    size = total_size(url)
    tail = fetch(url, max(0, size - 65536), min(size, 65536))
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        sys.exit("no end of central directory")
    cd_size, cd_off = struct.unpack_from("<II", tail, eocd + 12)
    if cd_off == 0xFFFFFFFF:  # zip64
        loc = tail.rfind(b"PK\x06\x07")
        z64 = struct.unpack_from("<Q", tail, loc + 8)[0]
        rec = fetch(url, z64, 56)
        cd_size, cd_off = struct.unpack_from("<QQ", rec, 40)
    cd = fetch(url, cd_off, cd_size)
    i = 0
    while i < len(cd) and cd[i:i + 4] == b"PK\x01\x02":
        method, = struct.unpack_from("<H", cd, i + 10)
        csize, usize = struct.unpack_from("<II", cd, i + 20)
        nlen, xlen, clen = struct.unpack_from("<HHH", cd, i + 28)
        local, = struct.unpack_from("<I", cd, i + 42)
        name = cd[i + 46:i + 46 + nlen].decode()
        extra = cd[i + 46 + nlen:i + 46 + nlen + xlen]
        if name == "payload.bin":
            j = 0
            while j + 4 <= len(extra):  # zip64 extra field
                tag, ln = struct.unpack_from("<HH", extra, j)
                if tag == 1:
                    vals = list(struct.unpack_from("<%dQ" % (ln // 8), extra, j + 4))
                    if usize == 0xFFFFFFFF:
                        usize = vals.pop(0)
                    if csize == 0xFFFFFFFF:
                        csize = vals.pop(0)
                    if local == 0xFFFFFFFF:
                        local = vals.pop(0)
                j += 4 + ln
            if method != 0:
                sys.exit("payload.bin is compressed in the zip")
            hdr = fetch(url, local, 30)
            n2, x2 = struct.unpack_from("<HH", hdr, 26)
            return local + 30 + n2 + x2
        i += 46 + nlen + xlen + clen
    sys.exit("no payload.bin in the zip")


def varint(b, i):
    shift = res = 0
    while True:
        c = b[i]
        i += 1
        res |= (c & 0x7F) << shift
        if not c & 0x80:
            return res, i
        shift += 7


def pb(b):
    out, i = {}, 0
    while i < len(b):
        key, i = varint(b, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            v, i = varint(b, i)
        elif wire == 1:
            v, i = struct.unpack_from("<Q", b, i)[0], i + 8
        elif wire == 2:
            ln, i = varint(b, i)
            v, i = b[i:i + ln], i + ln
        elif wire == 5:
            v, i = struct.unpack_from("<I", b, i)[0], i + 4
        else:
            raise ValueError("wire type %d" % wire)
        out.setdefault(num, []).append(v)
    return out


def main():
    url = sys.argv[1]
    listing = sys.argv[2:] == ["--list"]
    outdir, wanted = (None, set()) if listing else (sys.argv[2], set(sys.argv[3:]))
    base = payload_offset(url)
    head = fetch(url, base, 24)
    magic, version, manifest_size = head[:4], *struct.unpack_from(">QQ", head, 4)
    if magic != b"CrAU" or version != 2:
        sys.exit("not a version 2 payload")
    sig_size, = struct.unpack(">I", fetch(url, base + 20, 4))
    manifest = pb(fetch(url, base + 24, manifest_size))
    block = manifest.get(3, [4096])[0]
    blobs = base + 24 + manifest_size + sig_size
    found = set()
    if not listing:
        os.makedirs(outdir, exist_ok=True)
    for part in manifest.get(13, []):
        p = pb(part)
        name = p[1][0].decode()
        if listing:
            print("%-24s %12d" % (name, pb(p[7][0])[1][0]))
            continue
        if name not in wanted:
            continue
        found.add(name)
        info = pb(p[7][0])
        size, digest = info[1][0], info[2][0]
        path = os.path.join(outdir, name + ".img")
        with open(path + ".part", "wb") as out:
            out.truncate(size)
            for n, raw in enumerate(p.get(8, [])):
                op = pb(raw)
                kind = op[1][0]
                exts = [pb(e) for e in op.get(6, [])]
                if kind == 6:  # ZERO
                    data = b""
                else:
                    off, ln = op.get(2, [0])[0], op.get(3, [0])[0]
                    data = fetch(url, blobs + off, ln)
                    if 8 in op and hashlib.sha256(data).digest() != op[8][0]:
                        sys.exit("%s op %d: hash mismatch" % (name, n))
                    if kind == 1:
                        data = bz2.decompress(data)
                    elif kind == 8:
                        data = lzma.decompress(data)
                    elif kind != 0:
                        sys.exit("%s op %d: type %d is not a full-payload operation" % (name, n, kind))
                pos = 0
                for e in exts:
                    start, count = e.get(1, [0])[0], e.get(2, [0])[0]
                    ln = count * block
                    out.seek(start * block)
                    out.write(data[pos:pos + ln] if kind != 6 else bytes(ln))
                    pos += ln
        h = hashlib.sha256()
        with open(path + ".part", "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        if h.digest() != digest:
            sys.exit("%s: partition hash mismatch" % name)
        os.replace(path + ".part", path)
        print("%s.img %d bytes, sha256 %s" % (name, size, h.hexdigest()), flush=True)
    missing = wanted - found
    if missing:
        sys.exit("not in payload: " + " ".join(sorted(missing)))


if __name__ == "__main__":
    main()
