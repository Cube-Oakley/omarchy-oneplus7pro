#!/usr/bin/env python3
"""One explicit RTC-backed s2idle test; does not install an automatic policy."""
import os
import argparse
from pathlib import Path
import subprocess
import time


def run(*args, check=True):
    return subprocess.run(args, check=check, timeout=60)


def snapshot(label):
    print(label, "boottime", time.clock_gettime(time.CLOCK_BOOTTIME), flush=True)
    for name in ("/sys/kernel/debug/suspend_stats", "/sys/kernel/debug/wakeup_sources",
                 "/sys/class/power_supply/bq27541-0/status",
                 "/sys/class/power_supply/bq27541-0/current_now",
                 "/sys/class/power_supply/pm8150b-charger/status"):
        print(name, Path(name).read_text(), flush=True)


def failures():
    return {line.split(":")[0]: int(line.split(":")[1])
            for line in Path("/sys/kernel/debug/suspend_stats").read_text().splitlines()
            if line.startswith("failed_") or line.startswith("fail:")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=20)
    args = parser.parse_args()
    assert 10 <= args.seconds <= 120
    assert Path("/sys/power/mem_sleep").read_text().strip() == "[s2idle]"
    assert Path("/sys/class/rtc/rtc0/device/power/wakeup").read_text().strip() == "enabled"
    assert not Path("/sys/class/rtc/rtc0/wakealarm").read_text().strip(), "An alarm is already armed"
    os.environ["XDG_RUNTIME_DIR"] = "/run/user/0"
    os.environ["WAYLAND_DISPLAY"] = "wayland-1"
    display = "/root/.local/bin/omarchy-mobile-display"
    run(display, "on")
    snapshot("BEFORE")
    before_failures = failures()
    async_path = Path("/sys/power/pm_async")
    old_async = async_path.read_text()
    try:
        # Serial callbacks make a failed stage easier to identify.
        async_path.write_text("0\n")
        run(display, "off")
        time.sleep(1)
        os.sync()
        print(f"ENTERING_S2IDLE; RTC alarm in {args.seconds} seconds", flush=True)
        boot_start = time.clock_gettime(time.CLOCK_BOOTTIME)
        mono_start = time.monotonic()
        result = run("rtcwake", "--device", "/dev/rtc0", "--mode", "mem",
                     "--seconds", str(args.seconds), "--utc", check=False)
        slept = (time.clock_gettime(time.CLOCK_BOOTTIME) - boot_start) - (time.monotonic() - mono_start)
        print("RETURNED", result.returncode, "suspended_seconds", slept, flush=True)
    finally:
        async_path.write_text(old_async)
        run("rtcwake", "--device", "/dev/rtc0", "--mode", "disable", check=False)
        # The current chroot/seatd session needs physical inputs announced again
        # after the VT suspend/resume cycle; this preserves existing windows.
        run("env", "SYSTEMD_IN_CHROOT=0", "udevadm", "trigger", "--action=add",
            "--subsystem-match=input", check=False)
        run("env", "SYSTEMD_IN_CHROOT=0", "udevadm", "settle", "--timeout=10", check=False)
        run(display, "on", check=False)
    time.sleep(3)
    snapshot("AFTER")
    run("nmcli", "-t", "-f", "DEVICE,STATE,CONNECTION", "device", check=False)
    run("dmesg", check=False)
    assert result.returncode == 0 and slept > 5, "No sustained suspend observed; inspect logs"
    assert failures() == before_failures, "A device failed suspend/resume; inspect logs"


if __name__ == "__main__":
    main()
