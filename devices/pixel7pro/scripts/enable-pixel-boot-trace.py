#!/usr/bin/env python3
"""Enable initcall_debug in an already verified Pixel boot image's header only.

Default is read-only. The caller must have verified the complete installed image
against --current-sha256. This narrowly scoped diagnostic checks both host images,
the running kernel, layout and current header, then writes/readbacks one 4 KiB
block. It never changes kernel bytes, switches slots or reboots.

Historical G diagnostic: normal ABL boot appears to ignore this header setting.
New persistent kernels force their embedded command line; rebuild those with
build-pixel-shell.py --initcall-debug instead.
"""
import argparse
import gzip
import hashlib
from pathlib import Path
import runpy
import shlex
import struct
import subprocess


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--current-image', type=Path, required=True)
    ap.add_argument('--current-sha256', required=True)
    ap.add_argument('--trace-image', type=Path, required=True)
    ap.add_argument('--trace-sha256', required=True)
    ap.add_argument('--kernel-build-id', type=Path, required=True)
    ap.add_argument('--ssh-wrapper', type=Path, required=True)
    ap.add_argument('--write-header', action='store_true')
    args = ap.parse_args()
    old, new = args.current_image.read_bytes(), args.trace_image.read_bytes()
    for data, digest in ((old, args.current_sha256), (new, args.trace_sha256)):
        if len(data) != 67108864 or data[:8] != b'ANDROID!' or struct.unpack_from('<I', data, 40)[0] != 4:
            ap.error('Expected a 64 MiB Android v4 wrapper')
        if hashlib.sha256(data).hexdigest() != digest:
            ap.error('Host image checksum mismatch')
    if old[:44] != new[:44] or old[1580:] != new[1580:]:
        ap.error('Images differ outside the command-line field')
    old_cmd = old[44:1580].split(b'\0', 1)[0]
    new_cmd = new[44:1580].split(b'\0', 1)[0]
    if new_cmd != old_cmd + b' initcall_debug' or b'initcall_debug' in old_cmd.split():
        ap.error('Only adding initcall_debug is supported')
    ssh = str(args.ssh_wrapper.resolve())

    def remote(command, **kwargs):
        return subprocess.run([ssh, command], check=True, **kwargs)

    parse_id = runpy.run_path(str(Path(__file__).with_name('install-pixel-boot.py')))['kernel_build_id']
    notes = remote('cat /sys/kernel/notes', capture_output=True).stdout
    if parse_id(notes) != args.kernel_build_id.read_text().strip():
        ap.error('Running kernel build ID mismatch')
    config = gzip.decompress(remote('cat /proc/config.gz', capture_output=True).stdout).decode()
    if 'CONFIG_CMDLINE_FORCE=y' in config.splitlines():
        ap.error('Kernel forces its embedded command line; rebuild with --initcall-debug instead')
    checks = '''set -eu
test "$(tr '\\0' '\\n' </sys/firmware/devicetree/base/compatible | head -1)" = 'google,GS201 CHEETAH'
grep -qx PARTNAME=boot_a /sys/class/block/sda10/uevent
test "$(blockdev --getsize64 /dev/sda10)" = 67108864
test "$(stat -f -c %T /run)" = tmpfs
'''
    remote('sh -c ' + shlex.quote(checks))
    read = 'dd if=/dev/sda10 bs=4096 count=1 iflag=direct status=none'
    if remote(read, capture_output=True).stdout != old[:4096]:
        ap.error('Installed header differs from the verified current image')
    if not args.write_header:
        print('Read-only preflight passed; no write performed.')
        return
    remote('cat > /run/pixel-trace-header.bin', input=new[:4096])
    if remote('cat /run/pixel-trace-header.bin', capture_output=True).stdout != new[:4096]:
        ap.error('Uploaded header mismatch; boot partition untouched')
    remote('dd if=/run/pixel-trace-header.bin of=/dev/sda10 bs=4096 count=1 oflag=direct conv=fsync status=none')
    if remote(read, capture_output=True).stdout != new[:4096]:
        raise RuntimeError('HEADER READBACK MISMATCH: remain in recovery; do not reboot')
    remote('rm /run/pixel-trace-header.bin')
    print('Tracing header written; direct 4 KiB readback matches. Kernel bytes untouched.')
    print('Full-image verification and traced normal boot remain separate checks.')


if __name__ == '__main__':
    main()
