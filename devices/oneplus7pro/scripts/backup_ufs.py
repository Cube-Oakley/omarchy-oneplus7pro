#!/usr/bin/env python3
"""Full UFS LUN backup of a Magisk-rooted OnePlus 7 Pro.

Each LUN is imaged in 8 GiB chunks: Magisk `dd` writes a chunk to /sdcard,
then `adb pull` copies it (binary-safe). The backup is resumable: a partial
LUN image is continued from its current size.

This is a live dump of a mounted userdata filesystem. Firmware LUNs are
static; userdata may be slightly inconsistent if apps write during the copy.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path

LUNS = {
    "sdb": 8_388_608,
    "sdc": 8_388_608,
    "sdd": 33_554_432,
    "sdf": 33_554_432,
    "sde": 4_294_967_296,
    "sda": 251_532_410_880,  # last: largest
}

CHUNK = 8 * 1024 * 1024 * 1024  # 8 GiB
BS = 1_048_576  # 1 MiB
REMOTE_CHUNK = "/sdcard/omarchy-backup-chunk.img"
SERIAL = os.environ.get("ADB_SERIAL") or os.environ.get("PHONE_SERIAL")
if not SERIAL:
    raise SystemExit("Set ADB_SERIAL or PHONE_SERIAL to the target phone serial.")


def adb(*args: str, check: bool = True, **kw) -> subprocess.CompletedProcess:
    cmd = ["adb", "-s", SERIAL, *args]
    return subprocess.run(cmd, check=check, **kw)


def adb_out(*args: str) -> str:
    return adb(*args, stdout=subprocess.PIPE, text=True).stdout


def stay_awake() -> None:
    adb("shell", "settings", "put", "global", "stay_on_while_plugged_in", "7", check=False)
    adb("shell", "svc", "power", "stayon", "true", check=False)
    adb("shell", "input", "keyevent", "KEYCODE_WAKEUP", check=False)


def wait_adb(timeout: int = 120) -> None:
    t0 = time.time()
    while time.time() - t0 < timeout:
        p = subprocess.run(
            ["adb", "-s", SERIAL, "get-state"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if p.stdout.strip() == "device":
            return
        subprocess.run(["adb", "start-server"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2)
    raise RuntimeError(f"adb device {SERIAL} not online after {timeout}s")


def remote_rm() -> None:
    adb("shell", "su", "-c", f"rm -f {REMOTE_CHUNK}", check=False)
    adb("shell", "rm", "-f", REMOTE_CHUNK, check=False)


def dd_chunk(lun: str, skip_blocks: int, count_blocks: int) -> int:
    """Write count_blocks MiB from lun at skip_blocks to REMOTE_CHUNK. Return bytes written."""
    remote_rm()
    cmd = (
        f"dd if=/dev/block/{lun} of={REMOTE_CHUNK} bs={BS} "
        f"skip={skip_blocks} count={count_blocks}"
    )
    # Magisk su; dd status goes to adb shell stdout (CRLF) — we only care about exit.
    p = adb("shell", "su", "-c", cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace") if isinstance(p.stdout, bytes) else (p.stdout or "")
    if p.returncode != 0:
        raise RuntimeError(f"dd failed rc={p.returncode}: {out[-500:]}")
    # size via stat
    sz = adb_out("shell", "stat", "-c", "%s", REMOTE_CHUNK).strip()
    try:
        return int(sz)
    except ValueError as e:
        raise RuntimeError(f"stat failed ({sz!r}): {out[-500:]}") from e


def pull_chunk(host_tmp: Path) -> int:
    if host_tmp.exists():
        host_tmp.unlink()
    adb("pull", REMOTE_CHUNK, str(host_tmp))
    return host_tmp.stat().st_size


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(8 * 1024 * 1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def dump_lun(lun: str, expected: int, dest: Path, log) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".chunk")

    have = dest.stat().st_size if dest.exists() else 0
    if have > expected:
        raise RuntimeError(f"{lun}: existing image is {have} bytes, expected {expected}")
    if have == expected:
        log(f"SKIP {lun}: already complete ({expected} bytes)")
        return
    if have % BS != 0:
        raise RuntimeError(f"{lun}: partial image {have} is not 1MiB-aligned; delete and restart this LUN")

    log(f"LUN {lun}: {have}/{expected} bytes ({have/expected*100:.1f}%)")
    mode = "ab" if have else "wb"
    with dest.open(mode) as out:
        offset = have
        while offset < expected:
            stay_awake()
            wait_adb()
            remaining = expected - offset
            this = min(CHUNK, remaining)
            if this % BS != 0:
                raise RuntimeError(f"{lun}: chunk {this} not 1MiB-aligned")
            skip = offset // BS
            count = this // BS
            t0 = time.time()
            log(f"  dd {lun} skip={skip} count={count} ({this/1024**3:.2f} GiB) ...")
            written = dd_chunk(lun, skip, count)
            if written != this:
                raise RuntimeError(f"{lun}: dd wrote {written}, expected {this}")
            pulled = pull_chunk(tmp)
            if pulled != this:
                raise RuntimeError(f"{lun}: pull got {pulled}, expected {this}")
            with tmp.open("rb") as inf:
                while True:
                    b = inf.read(8 * 1024 * 1024)
                    if not b:
                        break
                    out.write(b)
            out.flush()
            os.fsync(out.fileno())
            tmp.unlink(missing_ok=True)
            remote_rm()
            offset += this
            dt = time.time() - t0
            rate = this / dt / 1024 / 1024 if dt > 0 else 0
            log(
                f"  ok {offset}/{expected} ({offset/expected*100:.1f}%) "
                f"{rate:.1f} MiB/s chunk, {dt:.0f}s"
            )

    got = dest.stat().st_size
    if got != expected:
        raise RuntimeError(f"{lun}: final size {got} != {expected}")
    log(f"  hashing {lun} ...")
    digest = sha256_file(dest)
    log(f"  SHA256 {lun} {digest}")
    (dest.with_suffix(dest.suffix + ".sha256")).write_text(f"{digest}  {dest.name}\n")


def main() -> int:
    backup = Path(os.environ.get("BACKUP_DIR", os.path.expanduser("~/Downloads/oneplus7pro-backup-20260913")))
    luns_dir = backup / "luns"
    luns_dir.mkdir(parents=True, exist_ok=True)
    log_path = backup / "logs" / "backup_ufs.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)

    def log(msg: str) -> None:
        line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
        print(line, flush=True)
        with log_path.open("a") as f:
            f.write(line + "\n")

    log(f"backup dir {backup}")
    wait_adb()
    stay_awake()
    state = adb_out("get-state").strip()
    log(f"adb state={state} serial={SERIAL}")

    # sanity: LUN sizes on device
    for lun, expected in LUNS.items():
        raw = adb_out("shell", "su", "-c", f"blockdev --getsize64 /dev/block/{lun}").strip()
        raw = raw.replace("\r", "")
        try:
            got = int(raw)
        except ValueError as e:
            raise RuntimeError(f"blockdev {lun}: {raw!r}") from e
        if got != expected:
            raise RuntimeError(f"{lun} size changed: device={got} expected={expected}")
        log(f"size ok {lun}={got}")

    try:
        for lun, expected in LUNS.items():
            dump_lun(lun, expected, luns_dir / f"{lun}.img", log)
    except Exception as e:
        log(f"FAILED: {e}")
        return 1

    log("DONE: all LUNs imaged")
    # summary
    total = 0
    for lun in LUNS:
        p = luns_dir / f"{lun}.img"
        total += p.stat().st_size
        sha = (p.with_suffix(".img.sha256")).read_text().strip() if p.with_suffix(".img.sha256").exists() else "?"
        log(f"  {lun}.img {p.stat().st_size}  {sha}")
    log(f"total {total} bytes ({total/1024**3:.2f} GiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
