#!/usr/bin/env python3
"""Load the temporary alarm driver while preserving the NTP-corrected wall clock."""
from pathlib import Path
import subprocess
import time


def main():
    assert "-sm8150-codex-native4-" in subprocess.check_output(["uname", "-r"], text=True)
    assert not list(Path("/sys/class/rtc").glob("rtc*")), "RTC already registered"
    base = Path("/root/suspend-test")
    wall, mono = time.time(), time.monotonic()
    try:
        for module in ("rtc-pm8xxx", "rtc_overlay", "rtc_parent"):
            if not (Path("/sys/module") / module.replace("-", "_")).exists():
                subprocess.run(["insmod", str(base / (module + ".ko"))], check=True)
        for _ in range(20):
            if Path("/sys/class/rtc/rtc0/since_epoch").exists():
                break
            time.sleep(0.5)
        assert Path("/sys/class/rtc/rtc0/since_epoch").exists(), "RTC did not register"
        time.sleep(0.5)
        print("RTC raw seconds:", Path("/sys/class/rtc/rtc0/since_epoch").read_text().strip())
    finally:
        # CONFIG_RTC_HCTOSYS sets the system clock at driver registration.
        # The vendor RTC counter has no Unix offset here. Restore system time
        # only; never write the RTC counter, vendor offset, or factory storage.
        time.clock_settime(time.CLOCK_REALTIME, wall + time.monotonic() - mono)
    print("System clock preserved:", time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()))


if __name__ == "__main__":
    main()
