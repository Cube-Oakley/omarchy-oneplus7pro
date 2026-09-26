"""Unit conversion and invalid-run guards for the supervised battery comparison."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('idle_measure', Path(__file__).resolve().parents[1] / 'adapter/measure-idle.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IdleMeasurementTests(unittest.TestCase):
    def setUp(self):
        self.start = dict(boot=100., mono=100., charge_now=3500000, online=0)
        self.end = dict(boot=400., mono=102., charge_now=3490000, online=0)

    def test_charge_units_and_sleep_accounting(self):
        result = module.summarize(self.start, self.end)
        self.assertAlmostEqual(result['interval_average_mA'], 120)
        self.assertAlmostEqual(result['suspended_seconds'], 298)
        self.assertAlmostEqual(result['approximate_1mAh_resolution_mA'], 12)

    def test_screen_off_awake_time_is_not_sleep(self):
        self.end['mono'] = 400
        self.assertEqual(module.summarize(self.start, self.end)['suspended_seconds'], 0)

    def test_reconnected_cable_invalidates_average(self):
        self.end['online'] = 1
        with self.assertRaises(ValueError):
            module.summarize(self.start, self.end)

    def test_charge_increase_is_not_negative_drain(self):
        self.end['charge_now'] = self.start['charge_now'] + 1000
        with self.assertRaises(ValueError):
            module.summarize(self.start, self.end)

    def test_zero_duration_rejected(self):
        self.end['boot'] = self.start['boot']
        with self.assertRaises(ValueError):
            module.summarize(self.start, self.end)

    def test_low_battery_and_hot_battery_stop_trial(self):
        for capacity, temp in [(19, 280), (80, 390)]:
            with self.assertRaises(RuntimeError):
                module.validate(dict(online=0, capacity=capacity, temp=temp))


if __name__ == '__main__':
    unittest.main()
