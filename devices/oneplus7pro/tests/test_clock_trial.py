"""Observation mode must retain all startup holds and have complete clock data."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('residency',
    Path(__file__).resolve().parents[1] / 'adapter/sleep-residency.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ClockTrialTests(unittest.TestCase):
    def test_cli_rejects_power_change_and_wrong_duration(self):
        for extra in (['--cx-sleep', '--seconds', '30'], ['--seconds', '90']):
            result = subprocess.run([sys.executable, m.__file__, '--clock-refs',
                                     *extra], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('no --cx-sleep', result.stderr)

    def run_check(self, text, history=True, hold_error=None, kernel='#186 '):
        with patch.object(m, 'check_cx', Mock(side_effect=hold_error)) as holds, \
             patch.object(Path, 'read_text', return_value=text), \
             patch.object(Path, 'is_file', return_value=history):
            m.check_clock_refs()
            holds.assert_called_once_with(kernel_version=kernel)

    def test_dsi_pm_candidate_uses_exact_187_guard(self):
        with patch.object(m.os, 'uname', return_value=Mock(version='#187 SMP PREEMPT')):
            self.run_check('missing_provider_clocks=0\ncurrent valid=1 count=1\n'
                           'current 0 bi_tcxo prepare=9\n', kernel='#187 ')

    def test_good_inventory(self):
        self.run_check('missing_provider_clocks=0\ncurrent valid=1 count=280\n'
                       'current 0 bi_tcxo prepare=9 enable=9 parent=1 flags=0\n')

    def test_bad_inventory(self):
        for text in ('', 'missing_provider_clocks=1\ncurrent valid=1 count=2\n',
                     'missing_provider_clocks=0\ncurrent valid=0 count=0\n',
                     'missing_provider_clocks=0\ncurrent valid=1 count=1\n'):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                self.run_check(text)

    def test_history_required(self):
        with self.assertRaisesRegex(RuntimeError, 'history'):
            self.run_check('missing_provider_clocks=0\ncurrent valid=1 count=1\n'
                           'current 0 bi_tcxo prepare=9\n', history=False)

    def test_original_holds_required(self):
        with self.assertRaisesRegex(RuntimeError, 'hold changed'):
            self.run_check('', hold_error=RuntimeError('hold changed'))

if __name__ == '__main__':
    unittest.main()
