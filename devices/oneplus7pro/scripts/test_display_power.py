#!/usr/bin/env python3
"""One bounded Hyprland display off/on test, with independent recovery."""
import argparse
import glob
import json
import os
from pathlib import Path
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--recover", action="store_true")
args = parser.parse_args()
os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
    sockets = glob.glob(os.environ["XDG_RUNTIME_DIR"] + "/hypr/*/.socket.sock")
    if len(sockets) != 1:
        raise SystemExit("Expected exactly one compositor socket")
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = Path(sockets[0]).parent.name


def request(*arguments):
    result = subprocess.run(["hyprctl", *arguments], capture_output=True,
                            text=True, timeout=8, check=True)
    return result.stdout


def power(action):
    print(action, request("eval", 'hl.dispatch(hl.dsp.dpms({ action = "'
                          + action + '" }))'), flush=True)


def state(expected):
    monitors = json.loads(request("monitors", "all", "-j"))
    print(json.dumps(monitors), flush=True)
    assert len(monitors) == 1, "Expected one phone display"
    assert monitors[0]["dpmsStatus"] is expected, "Unexpected DPMS state"


if args.recover:
    time.sleep(20)
    power("enable")
    raise SystemExit(0)

state(True)
power("enable")  # Verify recovery syntax before any disable request.
subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--recover"],
                 stdin=subprocess.DEVNULL, start_new_session=True)
try:
    power("disable")
    time.sleep(3)
    state(False)
finally:
    power("enable")
time.sleep(3)
state(True)
print("PASS: display off/on round trip; independent recovery remains armed", flush=True)
