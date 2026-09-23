#!/usr/bin/env python3
"""Read and mark the A/B boot-slot flags that ABL keeps in the GPT.

ABL picks a slot from the attribute bits of the boot_a/boot_b entries and
spends one retry on every boot of a slot that is not marked successful. When
the count reaches zero it marks the slot unbootable and stops. Linux here has
no boot-control service, so this marks the running slot successful: one bit in
the boot_<slot> entry of both GPT copies, plus their CRCs. Nothing else in the
table changes. Bit layout follows Qualcomm ABL and qbootctl.

Usage: guacamole-boot-slot [status | mark-successful [--dry-run]]
"""
import binascii
import fcntl
import os
from pathlib import Path
import stat
import struct
import sys

HEADER = struct.Struct('<8sIIIIQQQQ16sQIII')
ENTRY_SIZE = 128
# Byte 6 of the 64-bit entry attributes at offset 48 holds bits 48-55.
AB_BYTE = 48 + 6
PRIORITY = 0x03
ACTIVE = 0x04
RETRY_SHIFT, RETRY_MASK = 3, 0x38
SUCCESSFUL = 0x40
UNBOOTABLE = 0x80
BLKFLSBUF = 0x1261
SYS_BLOCK = Path('/sys/block')
DEV = Path('/dev')


class GptError(Exception):
    pass


def crc32(data):
    return binascii.crc32(data) & 0xffffffff


class Copy:
    """One GPT header and its partition entry array."""

    def __init__(self, fd, block, lba):
        raw = os.pread(fd, block, lba * block)
        if len(raw) != block:
            raise GptError(f'short read at LBA {lba}')
        (sig, rev, size, header_crc, _, my_lba, self.alternate, self.first, self.last,
         self.guid, self.entries_lba, self.count, esize, self.entries_crc) = HEADER.unpack_from(raw)
        if sig != b'EFI PART' or rev != 0x00010000:
            raise GptError(f'no GPT header at LBA {lba}')
        if not HEADER.size <= size <= block or my_lba != lba:
            raise GptError(f'bad header geometry at LBA {lba}')
        self.header = bytearray(raw[:size])
        struct.pack_into('<I', self.header, 16, 0)
        if crc32(self.header) != header_crc:
            raise GptError(f'header CRC mismatch at LBA {lba}')
        if esize != ENTRY_SIZE or not 0 < self.count <= 1024:
            raise GptError(f'unexpected entry array at LBA {lba}')
        self.lba = lba
        self.entries = bytearray(os.pread(fd, self.count * ENTRY_SIZE, self.entries_lba * block))
        if len(self.entries) != self.count * ENTRY_SIZE or crc32(self.entries) != self.entries_crc:
            raise GptError(f'entry array CRC mismatch for header at LBA {lba}')

    def rebuilt(self, entries):
        header = bytearray(self.header)
        struct.pack_into('<I', header, 88, crc32(entries))
        struct.pack_into('<I', header, 16, 0)
        struct.pack_into('<I', header, 16, crc32(header))
        return bytes(header)


class Disk:
    def __init__(self, name):
        self.name = name
        self.path = str(DEV / name)
        self.block = int((SYS_BLOCK / name / 'queue/logical_block_size').read_text())
        last = int((SYS_BLOCK / name / 'size').read_text()) * 512 // self.block - 1
        fd = os.open(self.path, os.O_RDONLY)
        try:
            self.primary = Copy(fd, self.block, 1)
            if self.primary.alternate != last:
                raise GptError(f'{name}: backup header is not at the last LBA')
            self.backup = Copy(fd, self.block, self.primary.alternate)
        finally:
            os.close(fd)
        p, b = self.primary, self.backup
        if (b.alternate, b.guid, b.count, b.first, b.last) != (1, p.guid, p.count, p.first, p.last):
            raise GptError(f'{name}: primary and backup headers disagree')
        if p.entries != b.entries:
            raise GptError(f'{name}: primary and backup entry arrays differ')
        self.index = {}
        for i in range(p.count):
            entry = p.entries[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE]
            if any(entry[:16]):
                label = entry[56:].decode('utf-16-le', 'replace').split('\0', 1)[0]
                self.index[label] = i

    def flags(self, slot):
        return self.primary.entries[self.index[f'boot_{slot}'] * ENTRY_SIZE + AB_BYTE]


def find_disk():
    found = []
    for block in sorted(SYS_BLOCK.glob('sd*')):
        try:
            disk = Disk(block.name)
        except (GptError, OSError):
            continue
        if {'boot_a', 'boot_b'} <= disk.index.keys():
            found.append(disk)
    if len(found) != 1:
        raise GptError(f'expected one disk with boot_a and boot_b, found {len(found)}')
    return found[0]


def describe(value):
    return (f'priority={value & PRIORITY} active={int(bool(value & ACTIVE))} '
            f'retry={(value & RETRY_MASK) >> RETRY_SHIFT} '
            f'successful={int(bool(value & SUCCESSFUL))} unbootable={int(bool(value & UNBOOTABLE))}')


def current_slot(disk):
    active = [slot for slot in 'ab' if disk.flags(slot) & ACTIVE]
    if len(active) != 1:
        raise GptError(f'expected one active boot slot, found {active}')
    return active[0]


def status(disk):
    print(f'disk {disk.path} block={disk.block} entries={disk.primary.count} copies=consistent')
    for slot in 'ab':
        print(f'boot_{slot}: {describe(disk.flags(slot))}')
    print(f'current slot: {current_slot(disk)}')


def mark_successful(disk, dry_run):
    slot = current_slot(disk)
    offset = disk.index[f'boot_{slot}'] * ENTRY_SIZE + AB_BYTE
    old = disk.primary.entries[offset]
    print(f'boot_{slot} before: {describe(old)}')
    if old & UNBOOTABLE:
        raise GptError(f'boot_{slot} is marked unbootable; reset it with fastboot set_active')
    if old & SUCCESSFUL:
        print(f'boot_{slot} is already marked successful')
        return
    entries = bytearray(disk.primary.entries)
    entries[offset] = old | SUCCESSFUL
    changed = [i for i in range(len(entries)) if entries[i] != disk.primary.entries[i]]
    if changed != [offset]:
        raise GptError(f'refusing a change outside one attribute byte: {changed}')
    headers = {copy.lba: copy.rebuilt(entries) for copy in (disk.primary, disk.backup)}
    print(f'boot_{slot} after:  {describe(entries[offset])}')
    print(f'entry array CRC {disk.primary.entries_crc:08x} -> {crc32(entries):08x}')
    if dry_run:
        print('dry run: nothing written')
        return
    fd = os.open(disk.path, os.O_RDWR)
    try:
        # Backup first: one complete, valid copy exists at every moment.
        for copy in (disk.backup, disk.primary):
            os.pwrite(fd, entries, copy.entries_lba * disk.block)
            os.pwrite(fd, headers[copy.lba], copy.lba * disk.block)
            os.fsync(fd)
        if stat.S_ISBLK(os.fstat(fd).st_mode):
            fcntl.ioctl(fd, BLKFLSBUF)
    finally:
        os.close(fd)
    check = Disk(disk.name)
    if check.flags(slot) != entries[offset] or current_slot(check) != slot:
        raise GptError('read-back did not match the written flags')
    print(f'boot_{slot} marked successful and verified from disk')


def main(argv):
    command = argv[1] if len(argv) > 1 else 'status'
    dry_run = argv[2:] == ['--dry-run']
    if command not in ('status', 'mark-successful') or argv[2:] not in ([], ['--dry-run']) or \
            (dry_run and command != 'mark-successful'):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    print(f'boot {Path("/proc/sys/kernel/random/boot_id").read_text().strip()}')
    try:
        disk = find_disk()
        if command == 'status':
            status(disk)
            return 0
        with open(os.environ.get('BOOT_SLOT_LOCK', '/run/guacamole-boot-slot.lock'), 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            mark_successful(disk, dry_run)
    except (GptError, OSError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
