#!/usr/bin/env python3
"""Collect a WPA personal password before starting NM's activation timeout."""

import getpass
import os
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 2 or not sys.stdin.isatty():
        print("Run in a terminal with an existing Wi-Fi profile name or UUID.")
        return 1
    profile = sys.argv[1]
    result = subprocess.run(
        ["nmcli", "-g", "connection.uuid,802-11-wireless-security.key-mgmt",
         "connection", "show", profile], capture_output=True, text=True,
    )
    values = result.stdout.splitlines()
    if result.returncode or len(values) != 2 or values[1] not in {"wpa-psk", "sae"}:
        print("This helper needs an existing WPA Personal Wi-Fi profile.")
        input("Press Enter to close.")
        return 1

    print(f"Connect to {profile}\n")
    print("Take your time. Password typing has no time limit.")
    print("The password stays hidden as you type. Press Enter when finished.\n")
    while True:
        password = getpass.getpass("Wi-Fi password: ")
        if not password or "\n" in password or "\r" in password:
            print("Please enter a nonempty, single-line password.")
            continue
        # Keep the credential off command lines and logs. /run is volatile;
        # mkstemp creates this file with mode 0600, and finally removes it.
        fd, path = tempfile.mkstemp(prefix="wifi-password-", dir="/run")
        try:
            with os.fdopen(fd, "w") as secret_file:
                secret_file.write("802-11-wireless-security.psk:" + password + "\n")
            del password
            result = subprocess.run(
                ["nmcli", "--wait", "90", "connection", "up", "uuid", values[0],
                 "passwd-file", path],
            )
        finally:
            os.unlink(path)
        if result.returncode == 0:
            print("\nWi-Fi connected.")
            input("Press Enter to close.")
            return 0
        if input("\nConnection failed. Press Enter to retry, or type q to close: ").lower() == "q":
            return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        sys.exit(130)
