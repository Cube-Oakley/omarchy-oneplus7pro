#!/usr/bin/env python3
"""Atomically promote the verified native5 module pair; retain the old directory."""
import ctypes
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess


EXPECTED = {
    'ath10k_core.ko': 'f5e3ff33c5f9b5ccc9ea7a454d56db944e870114068933ecf516698e6b22541b',
    'ath10k_snoc.ko': '65d924cfd47ac7ec029edb4fdc0ff8820df79522e86cb87a1cdfcacf28198ddb',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    release = os.uname().release
    if release != '6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty':
        raise RuntimeError('This promotion is for the verified native5 build only')
    active = Path('/root/radio-bringup/modules') / release
    staged = active.with_name(release + '.key-ack-stage')
    backup = active.with_name(release + '.before-key-ack')
    tested = Path('/root/wifi-key-ack-test')
    with open('/run/guacamole-radio.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if all(digest(active / name) == expected for name, expected in EXPECTED.items()):
            print('Verified key-ack modules already installed')
            return
        if staged.exists() or backup.exists():
            raise RuntimeError('Existing stage/backup needs inspection; no changes made')
        subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=active, check=True)
        for name, expected in EXPECTED.items():
            if digest(tested / name) != expected:
                raise RuntimeError('Test module hash mismatch')
        shutil.copytree(active, staged)
        for name in EXPECTED:
            shutil.copy2(tested / name, staged / name)
        for module in staged.glob('*.ko'):
            version = subprocess.check_output(['modinfo', '-F', 'vermagic', str(module)], text=True)
            if not version.startswith(release + ' '):
                raise RuntimeError('Module version mismatch; active directory unchanged')
        (staged / 'SHA256SUMS').write_text(''.join(
            digest(module) + '  ./' + module.name + '\n'
            for module in sorted(staged.glob('*.ko'))))
        subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=staged, check=True)
        os.sync()
        libc = ctypes.CDLL(None, use_errno=True)
        exchange = libc.renameat2
        exchange.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        exchange.restype = ctypes.c_int
        # RENAME_EXCHANGE keeps the complete matching pair visible atomically.
        if exchange(-100, os.fsencode(active), -100, os.fsencode(staged), 2):
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
        staged.rename(backup)
        os.sync()
        print('Persistent module pair installed; running driver unchanged')
        print('Original complete module directory:', backup)


if __name__ == '__main__':
    main()
