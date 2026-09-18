"""Safety checks for the explicit phone sleep command; never accesses hardware."""
import importlib.util
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('phone_suspend', Path(__file__).resolve().parents[1] / 'devices/oneplus7pro/suspend.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SuspendPolicyTests(unittest.TestCase):
    def setUp(self):
        self.values = {
            '/sys/power/mem_sleep': '[s2idle]',
            '/sys/class/rtc/rtc0/device/power/wakeup': 'enabled',
            '/sys/bus/platform/devices/c440000.spmi:pmic@0:pon@800:pwrkey/power/wakeup': 'enabled',
            '/sys/class/power_supply/pm8150b-charger/online': '0',
            '/sys/class/power_supply/bq27541-0/capacity': '80',
            '/sys/class/rtc/rtc0/wakealarm': '',
        }

    def check(self):
        with patch.object(module.os, 'uname', return_value=SimpleNamespace(release='6.17.0-sm8150-codex-native5-test')), \
             patch.object(module, 'read', side_effect=self.values.__getitem__):
            module.prerequisites()

    def test_unplugged_ready(self):
        self.check()

    def test_plugged_in_refused(self):
        self.values['/sys/class/power_supply/pm8150b-charger/online'] = '1'
        with self.assertRaisesRegex(RuntimeError, 'Unplug'):
            self.check()

    def test_existing_alarm_preserved(self):
        self.values['/sys/class/rtc/rtc0/wakealarm'] = '123456'
        with self.assertRaisesRegex(RuntimeError, 'already scheduled'):
            self.check()

    def test_wake_source_required(self):
        self.values['/sys/bus/platform/devices/c440000.spmi:pmic@0:pon@800:pwrkey/power/wakeup'] = 'disabled'
        with self.assertRaisesRegex(RuntimeError, 'Power-button wake'):
            self.check()

    def test_display_recovery_after_multiple_cleanup_failures(self):
        commands = []
        def fake_run(*command):
            commands.append(command)
            if command[0] != 'display-helper':
                raise subprocess.TimeoutExpired(command, 30)
        fake_path = Mock()
        fake_path.write_text.side_effect = OSError('pm_async write failed')
        with patch.object(module, 'Path', return_value=fake_path), \
             patch.object(module, 'run', side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, 'cleanup needs attention'):
                module.restore('1', True, 'display-helper')
        self.assertEqual(commands[-1], ('display-helper', 'on'))


if __name__ == '__main__':
    unittest.main()
