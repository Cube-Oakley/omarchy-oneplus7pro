#!/usr/bin/env python3
"""Replace guacamole (18821) FDTs in the Lineage boot DTB pack with a mainline DTB."""
from __future__ import annotations

import argparse
import struct
import subprocess
import tempfile
from pathlib import Path


def iter_fdts(blob: bytes) -> list[tuple[int, bytes]]:
    out: list[tuple[int, bytes]] = []
    off = 0
    while off + 8 <= len(blob):
        nxt = blob.find(b"\xd0\x0d\xfe\xed", off)
        if nxt < 0:
            break
        off = nxt
        tot = int.from_bytes(blob[off + 4 : off + 8], "big")
        if tot < 8 or off + tot > len(blob):
            break
        out.append((off, blob[off : off + tot]))
        off += tot
        if off % 4:
            off += 4 - (off % 4)
    return out


def fdtget(path: Path, prop: str) -> str | None:
    r = subprocess.run(["fdtget", str(path), "/", prop], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--pack", required=True)
    p.add_argument("--mainline", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()
    pack = Path(args.pack).read_bytes()
    mainline = Path(args.mainline).read_bytes()
    entries = iter_fdts(pack)
    if not entries:
        raise SystemExit("no FDTs in pack")
    pieces: list[bytes] = []
    replaced = 0
    with tempfile.TemporaryDirectory() as td:
        td_p = Path(td)
        ml_p = td_p / "ml.dtb"
        ml_p.write_bytes(mainline)
        for i, (_off, fdt) in enumerate(entries):
            src = td_p / f"e{i}.dtb"
            src.write_bytes(fdt)
            dtsi = fdtget(src, "oplus,dtsi_no")
            if dtsi == "18821":
                dst = td_p / f"r{i}.dtb"
                dst.write_bytes(mainline)
                msm = subprocess.run(
                    ["fdtget", "-tx", str(src), "/", "qcom,msm-id"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.split()
                cells = [str(int(x, 16)) for x in msm]
                subprocess.run(
                    ["fdtput", "-tx", str(dst), "/", "qcom,msm-id", *msm],
                    check=True,
                )
                pieces.append(dst.read_bytes())
                replaced += 1
                print(f"replace {i:02d} dtsi={dtsi} msm-id={msm} cells={cells} {len(fdt)}->{dst.stat().st_size}")
            else:
                pieces.append(fdt)
                print(f"keep    {i:02d} dtsi={dtsi} size={len(fdt)}")
    out = b"".join(pieces)
    Path(args.out).write_bytes(out)
    print(f"wrote {args.out} entries={len(entries)} replaced={replaced} size={len(out)}")


if __name__ == "__main__":
    main()
