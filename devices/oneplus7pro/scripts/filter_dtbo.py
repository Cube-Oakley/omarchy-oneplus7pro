#!/usr/bin/env python3
"""Keep overlay fragments that fdtoverlay can apply to a base DTB."""
from __future__ import annotations

import argparse
import re
import subprocess
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


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True)
    p.add_argument("--overlay", required=True)
    p.add_argument("--out-dir", required=True)
    args = p.parse_args()
    dts = subprocess.check_output(["dtc", "-I", "dtb", "-O", "dts", args.overlay], text=True)
    frags = extract_fragments(dts)
    header = """/dts-v1/;
/plugin/;

/ {
	model = "Qualcomm Technologies, Inc. SM8150 MTP 18821";
	compatible = "qcom,sm8150-mtp", "qcom,sm8150", "qcom,mtp";
	qcom,board-id = <0x08 0x00>;
	oplus,dtsi_no = <0x4985>;
	oplus,pcb_range = <0x00 0x37>;
"""
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    kept: list[str] = []
    for n, frag in enumerate(frags):
        trial = header + "\n".join(kept + [frag]) + "\n};\n"
        dts_p = out / "trial.dts"
        dtb_p = out / "trial.dtbo"
        dts_p.write_text(trial)
        c = subprocess.run(
            ["dtc", "-@", "-I", "dts", "-O", "dtb", "-o", str(dtb_p), str(dts_p)],
            capture_output=True,
            text=True,
        )
        if c.returncode != 0:
            print(f"{n:3d} DTC-FAIL")
            continue
        o = subprocess.run(
            ["fdtoverlay", "-i", args.base, "-o", "/tmp/ovl-try.dtb", str(dtb_p)],
            capture_output=True,
            text=True,
        )
        tgt = re.search(r"target(?:-path)?\s*=\s*([^;]+);", frag)
        t = (tgt.group(1).strip() if tgt else "?")[:50]
        if o.returncode == 0:
            kept.append(frag)
            print(f"{n:3d} KEEP {t}")
        else:
            print(f"{n:3d} skip {t}")
    print(f"KEPT {len(kept)} / {len(frags)}")
    final = header + "\n".join(kept) + "\n};\n"
    (out / "filtered.dts").write_text(final)
    subprocess.check_call(
        ["dtc", "-@", "-I", "dts", "-O", "dtb", "-o", str(out / "filtered.dtbo"), str(out / "filtered.dts")],
        stderr=subprocess.DEVNULL,
    )


if __name__ == "__main__":
    main()
