import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'overlay/mobile/rotation.py'


def load():
    spec = importlib.util.spec_from_file_location('rotation', SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RotationTests(unittest.TestCase):
    def setUp(self):
        self.rotation = load()

    def test_monitor_sensor_lines(self):
        parse = self.rotation.parse
        self.assertEqual(parse('=== Has accelerometer (orientation: undefined, tilt: undefined)'), 'undefined')
        self.assertEqual(parse('    Accelerometer orientation changed: right-up'), 'right-up')
        self.assertIsNone(parse('    Tilt changed: face-up'))
        self.assertIsNone(parse('    Light changed: 12.000000 (lux)'))

    def test_rule_keeps_the_device_mode_and_scale(self):
        rule = self.rotation.monitor_rule('DSI-1', {'displayMode': '1440x3120@90', 'scale': 3}, 1)
        self.assertEqual(rule, 'hl.monitor({ output = "DSI-1", mode = "1440x3120@90", '
                               'position = "auto", scale = 3, transform = 1 })')
        self.assertIn('mode = "preferred"', self.rotation.monitor_rule('DSI-1', {}, 0))
        self.assertIn('scale = "auto"', self.rotation.monitor_rule('DSI-1', {}, 0))

    def test_every_orientation_has_its_own_transform(self):
        transforms = self.rotation.TRANSFORMS
        self.assertEqual(set(transforms), {'normal', 'left-up', 'right-up', 'bottom-up'})
        self.assertEqual(len(set(transforms.values())), 4)
        self.assertEqual(transforms['normal'], 0)

    def test_unknown_orientation_is_refused(self):
        with self.assertRaises(ValueError):
            self.rotation.set_rotation('sideways')


if __name__ == '__main__':
    unittest.main()
