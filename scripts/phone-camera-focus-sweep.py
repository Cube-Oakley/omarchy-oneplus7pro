#!/usr/bin/env python3
"""Runs on the phone after phone-camera-test.sh sensor: steps the main camera's
focus actuator through its range, captures a raw IMX586 frame at each
position and scores centre sharpness (variance of a green-pixel Laplacian),
then leaves the lens at the sharpest position and saves one frame there.
The lens node stays open throughout: the driver drops focus writes while the
actuator is runtime-suspended, and suspending it lets the lens fall back to
rest.

Usage: phone-camera-focus-sweep.py [STEP] [OUT.raw]
"""
import os
import subprocess as sp
import sys

W, H, STRIDE = 4000, 3000, 5008
SIZE = STRIDE * H
FMT = 'SRGGB10_1X10/4000x3000'
CROP = 512  # green pixels per side, taken from the frame centre, every other one


def run(*args):
    return sp.run(args, check=True, capture_output=True, text=True).stdout.strip()


def media(*args):
    return run('media-ctl', '-d', '/dev/media0', *args)


def configure():
    media('-l', '"msm_csiphy1":1->"msm_csid0":0[1]')
    media('-l', '"msm_csid0":1->"msm_vfe0_rdi0":0[1]')
    media('-V', f'"imx586 4-001a":0[fmt:{FMT}]')
    for entity in ('msm_csiphy1', 'msm_csid0'):
        for pad in (0, 1):
            media('-V', f'"{entity}":{pad}[fmt:{FMT}]')
    media('-V', f'"msm_vfe0_rdi0":0[fmt:{FMT}]')
    video = media('-e', 'msm_vfe0_video0')
    run('v4l2-ctl', '-d', video, '--set-fmt-video=width=4000,height=3000,pixelformat=pRAA')
    return video, media('-e', 'lc898217xc 4-0072')


def capture(video, path, count=3):
    run('timeout', '25', 'v4l2-ctl', '-d', video, '--stream-mmap', f'--stream-count={count}',
        f'--stream-to={path}')


def sharpness(path, frames=3):
    """Laplacian variance of the high 8 bits of green pixels in a centre crop."""
    rows = []
    with open(path, 'rb') as f:
        # Even rows hold R,Gr: Gr pixels are the odd columns.
        top = (H // 2 - CROP) & ~1
        left = (W // 2 - CROP) & ~3
        for y in range(top, top + 2 * CROP, 4):
            f.seek((frames - 1) * SIZE + y * STRIDE + left * 5 // 4)
            raw = f.read(2 * CROP * 5 // 4)
            high = [raw[i] for i in range(len(raw)) if i % 5 != 4]
            rows.append(high[1::4])
    lap = []
    for y in range(1, len(rows) - 1):
        for x in range(1, len(rows[y]) - 1):
            lap.append(4 * rows[y][x] - rows[y - 1][x] - rows[y + 1][x] - rows[y][x - 1] - rows[y][x + 1])
    mean = sum(lap) / len(lap)
    level = sum(sum(r) for r in rows) / (len(rows) * len(rows[0]))
    return sum((v - mean) ** 2 for v in lap) / len(lap), level


def main(argv):
    step = int(argv[1]) if len(argv) > 1 else 50
    out = argv[2] if len(argv) > 2 else '/tmp/imx586-focused.raw'
    video, lens = configure()
    hold = os.open(lens, os.O_RDWR)  # keeps the actuator powered and in use
    scores = []
    for position in list(range(0, 401, step)) + ([400] if 400 % step else []):
        run('v4l2-ctl', '-d', lens, f'--set-ctrl=focus_absolute={position}')
        capture(video, '/tmp/focus.raw')
        score, level = sharpness('/tmp/focus.raw')
        scores.append((score, position))
        print(f'focus {position:3d}: sharpness {score:8.1f}  centre level {level:5.1f}', flush=True)
    best = max(scores)[1]
    run('v4l2-ctl', '-d', lens, f'--set-ctrl=focus_absolute={best}')
    capture(video, out, count=2)
    os.close(hold)
    print(f'best focus {best}; frame saved to {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
