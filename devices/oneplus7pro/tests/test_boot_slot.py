import binascii
import importlib.util
import os
from pathlib import Path
import struct
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('boot_slot', ROOT / 'adapter/boot-slot.py')
boot_slot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot_slot)

BLOCK = 4096
BLOCKS = 64
COUNT = 128
LABELS = ['xbl_a', 'abl_a', 'boot_a', 'dtbo_a', 'abl_b', 'boot_b', 'dtbo_b']


def crc(data):
    return binascii.crc32(data) & 0xffffffff


def flags(retry, active=False, successful=False, unbootable=False, priority=3):
    return priority | (0x04 if active else 0) | (retry << 3) | (0x40 if successful else 0) | \
        (0x80 if unbootable else 0)


def build_image(path, slot_flags):
    entries = bytearray(COUNT * 128)
    for i, label in enumerate(LABELS):
        entry = bytearray(128)
        entry[:16] = uuid.uuid4().bytes
        entry[16:32] = uuid.uuid4().bytes
        struct.pack_into('<QQ', entry, 32, 10 + i, 10 + i)
        # Unrelated attribute bits must survive untouched.
        struct.pack_into('<Q', entry, 48, 0x1000000000000001)
        entry[56:56 + 2 * len(label)] = label.encode('utf-16-le')
        if label.startswith('boot_'):
            entry[54] = slot_flags[label[-1]]
        entries[i * 128:(i + 1) * 128] = entry
    guid = uuid.uuid4().bytes
    image = bytearray(BLOCK * BLOCKS)
    # Protective MBR, so ordinary GPT tools accept the image too.
    struct.pack_into('<B3sB3sII', image, 446, 0, b'\x00\x02\x00', 0xEE, b'\xff\xff\xff',
                     1, BLOCKS - 1)
    image[510:512] = b'\x55\xaa'

    def header(my_lba, alternate, entries_lba):
        raw = bytearray(boot_slot.HEADER.pack(
            b'EFI PART', 0x00010000, 92, 0, 0, my_lba, alternate, 6, BLOCKS - 6,
            guid, entries_lba, COUNT, 128, crc(entries)))
        struct.pack_into('<I', raw, 16, crc(raw))
        return raw

    image[BLOCK:BLOCK + 92] = header(1, BLOCKS - 1, 2)
    image[2 * BLOCK:2 * BLOCK + len(entries)] = entries
    image[(BLOCKS - 1) * BLOCK:(BLOCKS - 1) * BLOCK + 92] = header(BLOCKS - 1, 1, BLOCKS - 5)
    image[(BLOCKS - 5) * BLOCK:(BLOCKS - 5) * BLOCK + len(entries)] = entries
    path.write_bytes(image)


class BootSlotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.dev = root / 'dev'
        self.dev.mkdir()
        queue = root / 'sys/block/sde/queue'
        queue.mkdir(parents=True)
        (queue / 'logical_block_size').write_text(f'{BLOCK}\n')
        (root / 'sys/block/sde/size').write_text(f'{BLOCKS * BLOCK // 512}\n')
        self.image = self.dev / 'sde'
        boot_slot.SYS_BLOCK = root / 'sys/block'
        boot_slot.DEV = self.dev
        os.environ['BOOT_SLOT_LOCK'] = str(root / 'lock')

    def tearDown(self):
        self.tmp.cleanup()

    def test_marks_only_the_active_boot_entry_in_both_copies(self):
        build_image(self.image, {'a': flags(7), 'b': flags(6, active=True)})
        before = self.image.read_bytes()
        boot_slot.mark_successful(boot_slot.find_disk(), dry_run=False)
        after = self.image.read_bytes()
        changed = {i for i in range(len(before)) if before[i] != after[i]}
        boot_b = 2 * BLOCK + LABELS.index('boot_b') * 128 + 54
        backup_b = (BLOCKS - 5) * BLOCK + LABELS.index('boot_b') * 128 + 54
        self.assertEqual(after[boot_b], flags(6, active=True, successful=True))
        self.assertEqual(after[backup_b], after[boot_b])
        # Besides the two attribute bytes, only the two headers' CRC fields change.
        allowed = {boot_b, backup_b}
        for lba in (1, BLOCKS - 1):
            allowed |= set(range(lba * BLOCK + 16, lba * BLOCK + 20))
            allowed |= set(range(lba * BLOCK + 88, lba * BLOCK + 92))
        self.assertTrue(changed <= allowed)
        disk = boot_slot.find_disk()
        self.assertEqual(disk.flags('a'), flags(7))
        self.assertEqual(struct.unpack_from('<Q', disk.primary.entries, 5 * 128 + 48)[0] & 0xff,
                         0x01)

    def test_repeat_is_a_no_op(self):
        build_image(self.image, {'a': flags(7), 'b': flags(6, active=True, successful=True)})
        before = self.image.read_bytes()
        boot_slot.mark_successful(boot_slot.find_disk(), dry_run=False)
        self.assertEqual(self.image.read_bytes(), before)

    def test_dry_run_writes_nothing(self):
        build_image(self.image, {'a': flags(7), 'b': flags(6, active=True)})
        before = self.image.read_bytes()
        boot_slot.mark_successful(boot_slot.find_disk(), dry_run=True)
        self.assertEqual(self.image.read_bytes(), before)

    def test_refuses_an_unbootable_slot(self):
        build_image(self.image, {'a': flags(7), 'b': flags(0, active=True, unbootable=True)})
        with self.assertRaises(boot_slot.GptError):
            boot_slot.mark_successful(boot_slot.find_disk(), dry_run=False)

    def test_refuses_ambiguous_active_slot(self):
        build_image(self.image, {'a': flags(7, active=True), 'b': flags(6, active=True)})
        with self.assertRaises(boot_slot.GptError):
            boot_slot.mark_successful(boot_slot.find_disk(), dry_run=False)

    def test_refuses_when_copies_disagree(self):
        build_image(self.image, {'a': flags(7), 'b': flags(6, active=True)})
        image = bytearray(self.image.read_bytes())
        image[(BLOCKS - 5) * BLOCK + 1] ^= 0xff
        self.image.write_bytes(image)
        with self.assertRaises(boot_slot.GptError):
            boot_slot.find_disk()

    def test_refuses_a_corrupt_header(self):
        build_image(self.image, {'a': flags(7), 'b': flags(6, active=True)})
        image = bytearray(self.image.read_bytes())
        image[BLOCK + 40] ^= 0x01
        self.image.write_bytes(image)
        with self.assertRaises(boot_slot.GptError):
            boot_slot.find_disk()


if __name__ == '__main__':
    unittest.main()
