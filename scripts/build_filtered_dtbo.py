#!/usr/bin/env python3
"""Build an ABL-valid dtbo: 10 Lineage identities, only fragments that apply."""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import tempfile
from pathlib import Path


def extract_fragments(text: str) -> list[str]:
    frags: list[str] = []
    i = 0
    while True:
        m = re.search(r"fragment@\d+\s*\{", text[i:])
        if not m:
            break
        start = i + m.start()
        j = text.find("{", start)
        depth = 0
        k = j
        while k < len(text):
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
                if depth == 0:
                    end = k + 1
                    if end < len(text) and text[end] == ";":
                        end += 1
                    frags.append(text[start:end])
                    i = end
                    break
            k += 1
        else:
            break
    return frags


def root_identity(dts: str) -> str:
    """Keep /plugin/ root properties; drop fragments."""
    lines = []
    for line in dts.splitlines(True):
        if "fragment@" in line:
            break
        lines.append(line)
    text = "".join(lines).rstrip()
    if not text.endswith("};"):
        text += "\n};"
    return text + "\n"


def filter_one(base: Path, overlay_dtb: Path, work: Path) -> tuple[Path, int, int]:
    dts = subprocess.check_output(["dtc", "-I", "dtb", "-O", "dts", str(overlay_dtb)], text=True)
    ident = root_identity(dts)
    # ident is a complete dts with closing };  — insert fragments before last };
    idx = ident.rfind("};")
    header, tail = ident[:idx], ident[idx:]
    frags = extract_fragments(dts)
    kept: list[str] = []
    for n, frag in enumerate(frags):
        trial = header + "\n".join(kept + [frag]) + "\n" + tail
        dts_p = work / "trial.dts"
        dtb_p = work / "trial.dtbo"
        dts_p.write_text(trial)
        c = subprocess.run(
            ["dtc", "-@", "-I", "dts", "-O", "dtb", "-o", str(dtb_p), str(dts_p)],
            capture_output=True,
            text=True,
        )
        if c.returncode != 0:
            continue
        o = subprocess.run(
            ["fdtoverlay", "-i", str(base), "-o", str(work / "merged.dtb"), str(dtb_p)],
            capture_output=True,
            text=True,
        )
        if o.returncode == 0:
            kept.append(frag)
    final = header + "\n".join(kept) + "\n" + tail
    out_dts = work / "filtered.dts"
    out_dtbo = work / "filtered.dtbo"
    out_dts.write_text(final)
    subprocess.check_call(
        ["dtc", "-@", "-I", "dts", "-O", "dtb", "-o", str(out_dtbo), str(out_dts)],
        stderr=subprocess.DEVNULL,
    )
    return out_dtbo, len(kept), len(frags)


def split_dtbo(img: Path, dest: Path) -> list[Path]:
    d = img.read_bytes()
    magic, total, hdr, ent_sz, count, off, page, ver = struct.unpack_from(">8I", d, 0)
    if magic != 0xD7B7AB1E:
        raise SystemExit(f"bad dtbo magic {magic:#x}")
    dest.mkdir(parents=True, exist_ok=True)
    outs = []
    for i in range(count):
        base = off + i * ent_sz
        dt_size, dt_off = struct.unpack_from(">2I", d, base)
        p = dest / f"entry{i}.dtbo"
        p.write_bytes(d[dt_off : dt_off + dt_size])
        outs.append(p)
    return outs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--lineage-dtbo", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    base = Path(args.base)
    lineage = Path(args.lineage_dtbo)
    out = Path(args.out)
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        entries = split_dtbo(lineage, td / "in")
        filtered = []
        for i, ent in enumerate(entries):
            work = td / f"w{i}"
            work.mkdir()
            p, kept, total = filter_one(base, ent, work)
            dest = td / f"out{i}.dtbo"
            dest.write_bytes(p.read_bytes())
            filtered.append(dest)
            print(f"entry{i}: KEEP {kept}/{total} size={dest.stat().st_size}")
        subprocess.check_call(
            ["mkdtboimg", "create", str(out), "--page_size=4096", *[str(p) for p in filtered]]
        )
    part = 25165824
    data = out.read_bytes()
    if len(data) > part:
        raise SystemExit(f"dtbo {len(data)} exceeds {part}")
    out.write_bytes(data + b"\x00" * (part - len(data)))
    d = out.read_bytes()
    magic, total, hdr, ent_sz, count, *_ = struct.unpack_from(">8I", d, 0)
    print(f"wrote {out} payload={total} count={count} padded={part}")


if __name__ == "__main__":
    main()
