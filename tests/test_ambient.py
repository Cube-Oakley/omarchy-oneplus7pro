import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'overlay/mobile/ambient.py'
spec = importlib.util.spec_from_file_location('ambient', SOURCE)
ambient = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ambient)


class PocketTests(unittest.TestCase):
    def setUp(self):
        self.pocket = ambient.Pocket()
        self.pocket.reading(tilt='face-up', lux=120.0, now=0.0)

    def test_face_down_sleeps_after_two_seconds_and_wakes_when_lifted(self):
        self.pocket.reading(tilt='face-down', now=1.0)
        self.assertIsNone(self.pocket.step(2.5))
        self.assertEqual(self.pocket.step(3.1), 'sleep')
        self.assertIsNone(self.pocket.step(10.0))
        self.pocket.reading(tilt='tilted-up', now=11.0)
        self.assertEqual(self.pocket.step(11.0), 'wake')

    def test_a_flat_phone_in_the_dark_never_asks_proximity(self):
        self.pocket.reading(lux=0.5, now=1.0)
        self.assertFalse(self.pocket.wants_proximity(10.0))
        self.assertIsNone(self.pocket.step(10.0))

    def test_pocket_sleeps_on_near_and_wakes_when_taken_out(self):
        self.pocket.reading(tilt='vertical', lux=0.5, now=1.0)
        self.assertFalse(self.pocket.wants_proximity(2.0))
        self.assertTrue(self.pocket.wants_proximity(2.6))
        self.pocket.reading(near=True, now=2.7)
        self.assertEqual(self.pocket.step(2.7), 'sleep')
        # Still asking proximity while asleep, to notice being taken out.
        self.assertTrue(self.pocket.wants_proximity(5.0))
        self.pocket.reading(near=False, now=6.0)
        self.assertEqual(self.pocket.step(6.0), 'wake')

    def test_light_alone_wakes_from_the_pocket(self):
        self.pocket.reading(tilt='vertical', lux=0.5, now=1.0)
        self.pocket.reading(near=True, now=3.0)
        self.assertEqual(self.pocket.step(3.0), 'sleep')
        self.pocket.reading(lux=40.0, now=4.0)
        self.assertEqual(self.pocket.step(4.0), 'wake')

    def test_dark_without_anything_near_stays_on(self):
        self.pocket.reading(tilt='vertical', lux=0.5, now=1.0)
        self.pocket.reading(near=False, now=3.0)
        self.assertIsNone(self.pocket.step(3.0))

    def test_monitor_sensor_lines(self):
        def parse(line):
            m = ambient.LINE.search(line)
            return m.groups() if m else None
        self.assertEqual(parse('=== Has accelerometer (orientation: undefined, tilt: face-up)'), ('face-up', None, None))
        self.assertEqual(parse('    Tilt changed: face-down'), ('face-down', None, None))
        self.assertEqual(parse('    Light changed: 1.500000 (lux)'), (None, '1.500000', None))
        self.assertEqual(parse('=== Has ambient light sensor (value: 12.000000, unit: lux)'), (None, '12.000000', None))
        self.assertEqual(parse('    Proximity value changed: 1'), (None, None, '1'))
        self.assertEqual(parse('=== Has proximity sensor (near: 0)'), (None, None, '0'))


if __name__ == '__main__':
    unittest.main()
