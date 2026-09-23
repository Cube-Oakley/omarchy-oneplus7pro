import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def module():
    spec = importlib.util.spec_from_file_location('about', ROOT / 'about.py')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class AboutTests(unittest.TestCase):
    def test_slot_os_backup_and_report_omit_serials(self):
        m = module()
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory) / 'proc'
            etc = Path(directory) / 'etc'
            state = Path(directory) / 'state'
            (proc / 'sys/kernel').mkdir(parents=True)
            (proc / 'sys/kernel/hostname').write_text('phone\n')
            (proc / 'cmdline').write_text('androidboot.slot_suffix=_b androidboot.serialno=SECRET console=tty0')
            (etc).mkdir()
            (etc / 'os-release').write_text('NAME="Arch Linux ARM"\nPRETTY_NAME="Arch Linux ARM"\n')
            latest = state / 'backups' / '20260919-014517'
            latest.mkdir(parents=True)
            (state / 'backups' / '20260918-235300').mkdir()
            (state / 'backups' / 'notification-shade-20260918').mkdir()
            data = m.snapshot(proc=proc, etc=etc, state=state, uname='6.16.0-native5')
            self.assertEqual(data['hostname'], 'phone')
            self.assertEqual(data['os'], 'Arch Linux ARM')
            self.assertEqual(data['kernel'], '6.16.0-native5')
            self.assertEqual(data['slot'], 'b')
            self.assertTrue(data['backup'].endswith('20260919-014517'))
            self.assertEqual(data['backups'], 2)
            self.assertNotIn('notification-shade', data['backup'])
            text = m.report(data)
            self.assertIn('6.16.0-native5', text)
            self.assertIn('Slot: b', text)
            self.assertNotIn('SECRET', text)
            self.assertNotIn('serialno', text)

    def test_missing_slot_and_backups(self):
        m = module()
        self.assertEqual(m.slot_from_cmdline('console=tty0'), '')
        with tempfile.TemporaryDirectory() as directory:
            data = m.snapshot(proc=Path(directory) / 'missing', etc=Path(directory) / 'missing',
                              state=Path(directory), uname='1.0')
            self.assertEqual(data['slot'], '')
            self.assertEqual(data['backup'], '')
            self.assertEqual(data['backups'], 0)


if __name__ == '__main__':
    unittest.main()
