"""Reject unsafe vote snapshots and restore CX even when a trial fails."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('residency',
    Path(__file__).resolve().parents[1] / 'devices/oneplus7pro/sleep-residency.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def cache(votes=None, truncated=0):
    votes = m.STARTUP_VOTES if votes is None else votes
    return f'device=18200000.rsc dirty=0 truncated={truncated}\n' + ''.join(
        f'cache {address:08x} {sleep:08x} {wake:08x}\n'
        for address, (sleep, wake) in votes.items())


class VoteTests(unittest.TestCase):
    def check(self, text, released=False):
        with patch.object(m, 'VOTE_CACHE', Mock(read_text=Mock(return_value=text))):
            m.check_cx_votes(released)

    def test_baseline_and_cx_sleep_only(self):
        self.check(cache())
        votes = dict(m.STARTUP_VOTES)
        votes[0x30000] = (0, 7)
        self.check(cache(votes), True)

    def test_refuse_each_protected_change(self):
        for address in m.STARTUP_VOTES:
            votes = dict(m.STARTUP_VOTES)
            votes[0x30000] = (0, 7)
            votes[address] = (0, 0)
            with self.subTest(address=address), self.assertRaises(RuntimeError):
                self.check(cache(votes), True)

    def test_missing_duplicate_truncated_and_no_change(self):
        missing = dict(m.STARTUP_VOTES)
        del missing[0x30060]
        for data in (cache(missing), cache() + 'cache 00030000 7 7\n',
                     cache(truncated=1), cache()):
            with self.subTest(data=data), self.assertRaises(RuntimeError):
                self.check(data, True)


class KernelGuardTests(unittest.TestCase):
    def setUp(self):
        for name, value in [('CX_RELEASE', Mock(read_text=Mock(return_value='0'))),
                            ('MSS_RELEASE', Mock(exists=Mock(return_value=False))),
                            ('check_power_holds', Mock()), ('check_cx_votes', Mock()),
                            ('check_clock_inventory', Mock())]:
            patcher = patch.object(m, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_verified_builds_and_combined_observer_requirement(self):
        for version in ('#186 SMP PREEMPT', '#187 SMP PREEMPT'):
            m.check_clock_inventory.reset_mock()
            with patch.object(m.os, 'uname', return_value=Mock(version=version)):
                m.check_cx()
            self.assertEqual(m.check_clock_inventory.call_count,
                             int(version.startswith('#187 ')))

    def test_unknown_or_misplaced_build_rejected_before_hardware(self):
        for version in ('#185 SMP', '#188 SMP', '#1870 SMP', 'other #187 SMP'):
            with patch.object(m.os, 'uname', return_value=Mock(version=version)):
                with self.assertRaises(RuntimeError):
                    m.check_cx()
        m.check_power_holds.assert_not_called()

    def test_explicit_build_remains_restricted(self):
        with patch.object(m.os, 'uname', return_value=Mock(version='#187 SMP')):
            with self.assertRaises(RuntimeError):
                m.check_cx(kernel_version='#186 ')

    def test_missing_observer_rejects_combined_trial(self):
        m.check_clock_inventory.side_effect = RuntimeError('Missing clocks')
        with patch.object(m.os, 'uname', return_value=Mock(version='#187 SMP')):
            with self.assertRaisesRegex(RuntimeError, 'Missing clocks'):
                m.check_cx()
        m.CX_RELEASE.write_text.assert_not_called()


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.control = Mock()
        self.control.read_text.side_effect = ['1', '0']
        for name, value in [('CX_RELEASE', self.control), ('check_cx', Mock()),
                            ('check_cx_votes', Mock()), ('emit', Mock()),
                            ('snapshot', Mock())]:
            patcher = patch.object(m, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_success(self):
        with m.cx_trial(True):
            pass
        self.assertEqual([c.args[0] for c in self.control.write_text.call_args_list],
                         ['1\n', '0\n'])
        m.check_cx_votes.assert_called_with()

    def test_failed_enable_snapshot_votes_and_suspend_restore(self):
        for failure in ('enable', 'snapshot', 'votes', 'suspend'):
            with self.subTest(failure=failure):
                self.control.reset_mock(side_effect=True)
                self.control.read_text.side_effect = ['0'] if failure == 'enable' else ['1', '0']
                self.control.write_text.side_effect = [OSError('failed'), None] if failure == 'enable' else None
                m.snapshot.side_effect = OSError('failed') if failure == 'snapshot' else None
                m.check_cx_votes.side_effect = [RuntimeError('failed'), None] if failure == 'votes' else None
                with self.assertRaises((RuntimeError, OSError)):
                    with m.cx_trial(True):
                        if failure == 'suspend':
                            raise RuntimeError('failed')
                        self.fail('Must not suspend after a failed preflight')
                self.control.write_text.assert_called_with('0\n')

    def test_restore_error_reported(self):
        self.control.read_text.side_effect = ['1', '1']
        with self.assertRaisesRegex(RuntimeError, 'CX restore failed'):
            with m.cx_trial(True):
                pass

    def test_preflight_failure_never_writes(self):
        m.check_cx.side_effect = RuntimeError('bad baseline')
        with self.assertRaises(RuntimeError):
            with m.cx_trial(True):
                self.fail('Must not suspend')
        self.control.write_text.assert_not_called()

    def test_disabled_never_writes(self):
        with m.cx_trial(False):
            pass
        self.control.write_text.assert_not_called()

    def test_duration_guard_before_hardware(self):
        result = subprocess.run([sys.executable, m.__file__, '--cx-sleep',
                                 '--seconds', '90'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('requires --seconds 30', result.stderr)


if __name__ == '__main__':
    unittest.main()
