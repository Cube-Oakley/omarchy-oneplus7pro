#!/usr/bin/env python3
"""Install a RAM-tested Pixel kernel to boot_a after persistent desktop validation.

Defaults to read-only preflight. Requires the exact image hash, ELF build ID,
and a trusted local SSH wrapper from the validated USB session. Never reboots.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shlex
import struct
import subprocess

STOCK_BOOT = '6922efd16e1e2af6ddac6f0ae65972ad13e7ba391c9896cd8de03ddd34000b10'


def kernel_build_id(notes):
    """Read the GNU build ID from the kernel's binary /sys/kernel/notes."""
    offset = 0
    found = []
    while offset + 12 <= len(notes):
        namesz, descsz, kind = struct.unpack_from('<III', notes, offset)
        offset += 12
        name_end = offset + namesz
        desc_start = (name_end + 3) & ~3
        desc_end = desc_start + descsz
        if desc_end > len(notes):
            raise RuntimeError('Truncated kernel note')
        if kind == 3 and notes[offset:name_end] == b'GNU\0':
            found.append(notes[desc_start:desc_end].hex())
        offset = (desc_end + 3) & ~3
    if len(found) != 1:
        raise RuntimeError('Expected one GNU kernel build ID')
    return found[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--image', type=Path, required=True)
    ap.add_argument('--sha256', required=True)
    ap.add_argument('--kernel-build-id', type=Path, required=True)
    ap.add_argument('--ssh-wrapper', type=Path, required=True)
    ap.add_argument('--previous-sha256', default=STOCK_BOOT)
    ap.add_argument('--replace-android-boot', action='store_true', help='write boot_a after all preflight checks pass')
    args = ap.parse_args()
    for digest in (args.sha256, args.previous_sha256):
        if not re.fullmatch(r'[0-9a-f]{64}', digest):
            ap.error('SHA256 arguments must be 64 lowercase hexadecimal characters')
    image = args.image.read_bytes()
    if len(image) != 67108864 or image[:8] != b'ANDROID!' or struct.unpack_from('<I', image, 40)[0] != 4:
        ap.error('Expected the verified 64 MiB Android v4 wrapper')
    if hashlib.sha256(image).hexdigest() != args.sha256:
        ap.error('Image checksum mismatch')
    expected_id = args.kernel_build_id.read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', expected_id):
        ap.error('Expected the kernel ELF SHA1 build ID')
    ssh = str(args.ssh_wrapper.resolve())

    def remote(command, **kwargs):
        return subprocess.run([ssh, command], check=True, **kwargs)

    live_id = kernel_build_id(remote('cat /sys/kernel/notes', capture_output=True).stdout)
    if live_id != expected_id:
        raise RuntimeError('Running kernel build ID differs from the image: RAM-test this exact kernel first')
    checks = '''set -eu
test "$(cat /etc/omarchy-mobile-pixel-root)" = v1
test "$(stat -f -c %T /)" = ext2/ext3
test "$(stat -f -c %T /run)" = tmpfs
test "$(tr '\\0' '\\n' </sys/firmware/devicetree/base/compatible | head -1)" = 'google,GS201 CHEETAH'
grep -qx PARTNAME=boot_a /sys/class/block/sda10/uevent
grep -qx PARTNAME=userdata /sys/class/block/sda31/uevent
test "$(blockdev --getsize64 /dev/sda10)" = 67108864
test "$(blockdev --getsize64 /dev/sda31)" = 245977141248
test -e /sys/module/pixel_reboot/parameters/bootloader
test -s /var/log/pixel-native-boots.log
grep -qx 'persistent desktop startup complete' /proc/1/root/run/pixel-persistent.log
pgrep -x Hyprland >/dev/null
pgrep -x quickshell >/dev/null
grep -q 'pixel_test_seconds=0\\b' /proc/cmdline
'''
    remote('bash -c ' + shlex.quote(checks))
    readback = 'dd if=/dev/sda10 bs=1M iflag=direct status=none | sha256sum'
    before = remote('bash -o pipefail -c ' + shlex.quote(readback), capture_output=True, text=True).stdout.split()[0]
    if before != args.previous_sha256:
        raise RuntimeError('Existing boot_a does not match the expected recovery/current image')
    print('Preflight passes: exact running kernel, persistent desktop, layout and boot_a hash.', flush=True)
    if not args.replace_android_boot:
        print('Read-only check complete; no partition was changed.')
        return
    with args.image.open('rb') as source:
        remote('cat > /run/pixel-boot-install.img', stdin=source)
    uploaded = remote('sha256sum /run/pixel-boot-install.img', capture_output=True, text=True).stdout.split()[0]
    if uploaded != args.sha256:
        raise RuntimeError('Uploaded image checksum mismatch; boot_a untouched')
    remote('dd if=/run/pixel-boot-install.img of=/dev/sda10 bs=1M oflag=direct conv=fsync status=progress')
    after = remote('bash -o pipefail -c ' + shlex.quote(readback), capture_output=True, text=True).stdout.split()[0]
    if after != args.sha256:
        raise RuntimeError('BOOT READBACK MISMATCH: stay in this recovery session; do not reboot')
    remote('rm /run/pixel-boot-install.img')
    print('boot_a written and direct readback matches ' + after)
    print('No other partition was written. Reboot validation is still required.')


if __name__ == '__main__':
    main()
