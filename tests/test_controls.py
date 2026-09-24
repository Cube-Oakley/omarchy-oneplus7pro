import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'overlay/mobile/controls.py'


def load(root):
    os.environ['OMARCHY_MOBILE_SYSFS'] = str(root / 'sys')
    os.environ['OMARCHY_MOBILE_DEV'] = str(root / 'dev')
    os.environ['XDG_STATE_HOME'] = str(root / 'state')
    spec = importlib.util.spec_from_file_location('controls', SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class ControlsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        sys = self.root / 'sys/class'
        write(sys / 'backlight/ae94000.dsi.0/brightness', '320\n')
        write(sys / 'backlight/ae94000.dsi.0/max_brightness', '1023\n')
        for name in ('white:torch', 'white:flash-1', 'mmc0::'):
            write(sys / 'leds' / name / 'brightness', '0\n')
            write(sys / 'leds' / name / 'max_brightness', '255\n')
        # FF_RUMBLE is bit 0x50: the second 64-bit word, bit 16.
        write(sys / 'input/event5/device/capabilities/ff', '10000 0\n')
        write(sys / 'input/event4/device/capabilities/abs', '400000000\n')
        self.controls = load(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def brightness(self):
        return int((self.root / 'sys/class/backlight/ae94000.dsi.0/brightness').read_text())

    def test_status_finds_every_control(self):
        status = self.controls.status()
        self.assertEqual(status['backlight'], {'device': 'ae94000.dsi.0', 'percent': 56})
        self.assertEqual(status['torch'], {'available': True, 'on': False})
        self.assertTrue(status['haptics'])

    def test_brightness_follows_the_eye_and_is_remembered(self):
        self.controls.main(['brightness', '50'])
        self.assertEqual(self.brightness(), 256)
        self.controls.main(['brightness', '0'])
        self.assertEqual(self.brightness(), 10)
        self.controls.main(['brightness', '100'])
        self.assertEqual(self.brightness(), 1023)
        (self.root / 'sys/class/backlight/ae94000.dsi.0/brightness').write_text('320\n')
        self.controls.main(['restore'])
        self.assertEqual(self.brightness(), 1023)

    def test_serve_applies_each_level_and_remembers_the_last(self):
        import io
        import sys
        stdin = sys.stdin
        sys.stdin = io.StringIO('brightness 30\nnonsense\nbrightness 60\nremember 70\n')
        try:
            self.controls.serve()
        finally:
            sys.stdin = stdin
        self.assertEqual(self.brightness(), 501)
        self.assertEqual(self.controls.load_state(), {'brightness': 70})

    def test_torch_drives_every_flash_led_but_not_others(self):
        leds = self.root / 'sys/class/leds'
        self.controls.main(['torch', 'toggle'])
        self.assertEqual([(leds / n / 'brightness').read_text() for n in ('white:torch', 'white:flash-1', 'mmc0::')],
                         ['128', '128', '0\n'])
        self.assertTrue(self.controls.status()['torch']['on'])
        self.controls.main(['torch', 'toggle'])
        self.assertFalse(self.controls.status()['torch']['on'])

    def test_missing_hardware_is_reported_not_guessed(self):
        empty = tempfile.TemporaryDirectory()
        self.addCleanup(empty.cleanup)
        controls = load(Path(empty.name))
        status = controls.status()
        self.assertEqual((status['backlight'], status['torch']['available'], status['haptics'], status['slider']),
                         (None, False, False, None))
        with self.assertRaises(ValueError):
            controls.main(['torch', 'on'])


if __name__ == '__main__':
    unittest.main()
