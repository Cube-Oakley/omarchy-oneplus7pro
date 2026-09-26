"""Verify restoration on diagnostic failures without accessing hardware."""
import importlib.util
from pathlib import Path
import unittest
import subprocess
import sys
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    'residency', Path(__file__).resolve().parents[1] /
    'adapter/sleep-residency.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MssTrialTests(unittest.TestCase):
    def test_retired_cli_refuses_before_hardware_access(self):
        result = subprocess.run([sys.executable, module.__file__, '--seconds',
                                 '30', '--mss-handoff'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('MSS release trial retired', result.stderr)

    def setUp(self):
        self.control = Mock()
        self.control.read_text.side_effect = ['1', '0']
        for name, value in [('MSS_RELEASE', self.control), ('check_mss', Mock()),
                            ('emit', Mock()), ('snapshot', Mock())]:
            patcher = patch.object(module, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_success_restores(self):
        with module.mss_trial(True):
            pass
        self.assertEqual([c.args[0] for c in self.control.write_text.call_args_list],
                         ['1\n', '0\n'])

    def test_failed_suspend_restores(self):
        with self.assertRaisesRegex(RuntimeError, 'suspend failed'):
            with module.mss_trial(True):
                raise RuntimeError('suspend failed')
        self.control.write_text.assert_called_with('0\n')

    def test_failed_enable_still_attempts_restore(self):
        self.control.write_text.side_effect = [OSError('enable failed'), None]
        self.control.read_text.side_effect = ['0']
        with self.assertRaisesRegex(OSError, 'enable failed'):
            with module.mss_trial(True):
                self.fail('Must not suspend')
        self.control.write_text.assert_called_with('0\n')

    def test_failed_snapshot_restores(self):
        module.snapshot.side_effect = OSError('snapshot failed')
        with self.assertRaises(OSError):
            with module.mss_trial(True):
                self.fail('Must not suspend')
        self.control.write_text.assert_called_with('0\n')

    def test_failed_restore_is_reported(self):
        self.control.read_text.side_effect = ['1', '1']
        with self.assertRaisesRegex(RuntimeError, 'MSS restore failed'):
            with module.mss_trial(True):
                pass

    def test_disabled_path_never_writes(self):
        with module.mss_trial(False):
            pass
        self.control.write_text.assert_not_called()

    def test_preflight_failure_never_enables(self):
        module.check_mss.side_effect = RuntimeError('unsafe start')
        with self.assertRaises(RuntimeError):
            with module.mss_trial(True):
                self.fail('Must not suspend')
        self.control.write_text.assert_not_called()


if __name__ == '__main__':
    unittest.main()
