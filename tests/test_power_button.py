"""Power-key policy and wake-event races, without accessing phone hardware."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('power_button', Path(__file__).resolve().parents[1] / 'overlay/mobile/power-button.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PowerButtonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {
            'XDG_RUNTIME_DIR': str(self.root), 'XDG_CONFIG_HOME': str(self.root),
            'XDG_STATE_HOME': str(self.root),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.button = module.PowerButton()
        self.button.adapter.parent.mkdir()
        self.button.adapter.touch(mode=0o755)
        self.button.display_on = Mock(return_value=True)
        self.button.set_display = Mock()
        self.calls = []
        self.ready = True
        self.during_sleep = lambda: None
        self.patch_run = patch.object(module.subprocess, 'run', side_effect=self.run_command)
        self.patch_run.start()
        self.addCleanup(self.patch_run.stop)

    def run_command(self, command, **kwargs):
        self.calls.append(command)
        if '--check' in command:
            return subprocess.CompletedProcess(command, 0 if self.ready else 1,
                                               '', '' if self.ready else 'Unplug before sleeping')
        self.during_sleep()
        return subprocess.CompletedProcess(command, 0)

    def tap(self):
        self.button.event('press')
        self.button.event('release')

    def test_unplugged_suspends_and_restores_display(self):
        self.tap()
        self.assertEqual(self.calls, [[str(self.button.adapter), '--check'], [str(self.button.adapter)]])
        self.button.set_display.assert_called_once_with('on')

    def test_plugged_in_blanks_without_sleeping(self):
        self.ready = False
        self.tap()
        self.assertEqual(len(self.calls), 1)
        self.button.set_display.assert_called_once_with('off')

    def test_blanked_screen_restores_without_suspend(self):
        self.button.display_on.return_value = False
        self.tap()
        self.assertFalse(self.calls)
        self.button.set_display.assert_called_once_with('on')

    def test_missing_adapter_retains_display_control(self):
        self.button.adapter.unlink()
        self.tap()
        self.assertFalse(self.calls)
        self.button.set_display.assert_called_once_with('off')

    def test_release_without_press_never_sleeps(self):
        self.button.event('release')
        self.assertFalse(self.calls)

    def test_wake_press_during_suspend_and_late_release_do_not_resleep(self):
        other = module.PowerButton()
        other.act = Mock()
        self.during_sleep = lambda: other.event('press')
        self.tap()
        # Even a long-held wake key released after the grace period is unpaired.
        with patch.object(module.time, 'monotonic', return_value=module.time.monotonic() + 10):
            other.event('release')
        other.act.assert_not_called()

    def test_queued_wake_pair_ignored_then_new_tap_works(self):
        self.tap()
        self.tap()
        self.assertEqual(len(self.calls), 2)
        with patch.object(module.time, 'monotonic', return_value=module.time.monotonic() + 3):
            self.tap()
        self.assertEqual(len(self.calls), 4)

    def test_failed_suspend_restores_display_and_suppresses_wake(self):
        self.during_sleep = Mock(side_effect=OSError('suspend process failed'))
        with self.assertRaises(OSError):
            self.tap()
        self.button.set_display.assert_called_once_with('on')
        self.assertIn('ignore_until', self.button.load())

    def test_supervised_alarm_is_passed_to_adapter(self):
        (self.root / 'omarchy-mobile-power-test-alarm').write_text('90\n')
        self.tap()
        self.assertEqual(self.calls[-1][-2:], ['--wake-after', '90'])


if __name__ == '__main__':
    unittest.main()
