#!/usr/bin/env python3
"""Slice named partitions out of LUN images using metadata/partition-map.tsv."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

DEFAULT_NAMES = (
    "boot_a",
    "boot_b",
    "dtbo_a",
    "dtbo_b",
    "vbmeta_a",
    "vbmeta_b",
    "persist",
    "modem_a",
    "dsp_a",
    "abl_a",
    "xbl_a",
    "modemst1",
    "modemst2",
    "fsg",
)


def load_map(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text().splitlines()[1:]:
        if not line.strip():
            continue
        lun, part, name, start_512, size_512, start_b, size_b = line.split("\t")
        rows.append(
            {
                "lun": lun,
                "part": part,
                "name": name,
                "start": int(start_b),
                "size": int(size_b),
            }
        )
    return rows


def extract(img: Path, dest: Path, start: int, size: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with img.open("rb") as inf, dest.open("wb") as out:
        inf.seek(start)
        left = size
        while left:
            chunk = inf.read(min(left, 8 * 1024 * 1024))
            if not chunk:
                raise EOFError(f"{img} ended at {inf.tell()}, wanted {size} from {start}")
            out.write(chunk)
            left -= len(chunk)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--backup-dir", type=Path, required=True)
    p.add_argument("--name", action="append", dest="names")
    args = p.parse_args()
    mapping = load_map(args.backup_dir / "metadata" / "partition-map.tsv")
    wanted = set(args.names or DEFAULT_NAMES)
    by_name = {r["name"]: r for r in mapping}
    outdir = args.backup_dir / "partitions"
    rc = 0
    for name in wanted:
        row = by_name.get(name)
        if not row:
            print(f"unknown {name}", file=sys.stderr)
            rc = 1
            continue
        img = args.backup_dir / "luns" / f"{row['lun']}.img"
        if not img.exists() or img.stat().st_size < row["start"] + row["size"]:
            print(f"skip {name}: {img.name} does not yet cover it")
            continue
        dest = outdir / f"{name}.img"
        print(f"{name}: {img.name} +{row['start']} {row['size']} -> {dest}")
        extract(img, dest, row["start"], row["size"])
    return rc


if __name__ == "__main__":
    sys.exit(main())
