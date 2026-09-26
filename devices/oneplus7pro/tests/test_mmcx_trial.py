"""Reject unsafe vote snapshots and restore MMCX even when a trial fails."""
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


def cache(votes=None, truncated=0):
    votes = m.STARTUP_VOTES if votes is None else votes
    return f'device=18200000.rsc dirty=0 truncated={truncated}\n' + ''.join(
        f'cache {address:08x} {sleep:08x} {wake:08x}\n'
        for address, (sleep, wake) in votes.items())


class VoteTests(unittest.TestCase):
    def check(self, text, released=False):
        with patch.object(m, 'VOTE_CACHE', Mock(read_text=Mock(return_value=text))):
            m.check_cx_votes(released, released_address=0x30080)

    def test_baseline_and_mmcx_sleep_only(self):
        self.check(cache())
        votes = dict(m.STARTUP_VOTES)
        votes[0x30080] = (0, 6)
        self.check(cache(votes), True)

    def test_refuse_each_protected_change(self):
        for address in m.STARTUP_VOTES:
            votes = dict(m.STARTUP_VOTES)
            votes[0x30080] = (0, 6)
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


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.control = Mock()
        self.control.read_text.side_effect = ['1', '0']
        for name, value in [('MMCX_RELEASE', self.control), ('check_mmcx', Mock()),
                            ('check_cx_votes', Mock()), ('emit', Mock()),
                            ('snapshot', Mock())]:
            patcher = patch.object(m, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_success(self):
        with m.mmcx_trial(True):
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
                    with m.mmcx_trial(True):
                        if failure == 'suspend':
                            raise RuntimeError('failed')
                        self.fail('Must not suspend after a failed preflight')
                self.control.write_text.assert_called_with('0\n')

    def test_restore_error_reported(self):
        self.control.read_text.side_effect = ['1', '1']
        with self.assertRaisesRegex(RuntimeError, 'MMCX restore failed'):
            with m.mmcx_trial(True):
                pass

    def test_preflight_failure_never_writes(self):
        m.check_mmcx.side_effect = RuntimeError('bad baseline')
        with self.assertRaises(RuntimeError):
            with m.mmcx_trial(True):
                self.fail('Must not suspend')
        self.control.write_text.assert_not_called()

    def test_disabled_never_writes(self):
        with m.mmcx_trial(False):
            pass
        self.control.write_text.assert_not_called()

    def test_duration_guard_before_hardware(self):
        result = subprocess.run([sys.executable, m.__file__, '--mmcx-sleep',
                                 '--seconds', '90'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('requires --seconds 30', result.stderr)




class GuardTests(unittest.TestCase):
    def setUp(self):
        for name, value in [('CX_RELEASE', Mock(read_text=Mock(return_value='0'))),
                            ('MMCX_RELEASE', Mock(read_text=Mock(return_value='0'))),
                            ('MSS_RELEASE', Mock(exists=Mock(return_value=False))),
                            ('check_power_holds', Mock()), ('check_cx_votes', Mock()),
                            ('check_clock_inventory', Mock())]:
            patcher = patch.object(m, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher=patch.object(m.os, 'uname', return_value=Mock(version='#188 SMP'))
        self.uname=patcher.start()
        self.addCleanup(patcher.stop)

    def test_valid(self):
        m.check_mmcx()
        m.check_power_holds.assert_called_once()
        m.check_cx_votes.assert_called_once()
        m.check_clock_inventory.assert_called_once()

    def test_wrong_kernel_and_active_controls(self):
        for version in ('#187 SMP', '#189 SMP', '#1880 SMP', 'other #188 SMP'):
            self.uname.return_value.version=version
            with self.assertRaises(RuntimeError): m.check_mmcx()
        self.uname.return_value.version='#188 SMP'
        for control in (m.CX_RELEASE, m.MMCX_RELEASE):
            control.read_text.return_value='1'
            with self.assertRaises(RuntimeError): m.check_mmcx()
            control.read_text.return_value='0'
        m.check_power_holds.assert_not_called()

    def test_mss_control_forbidden(self):
        m.MSS_RELEASE.exists.return_value=True
        with self.assertRaises(RuntimeError): m.check_mmcx()
        m.check_power_holds.assert_not_called()

    def test_preflight_observation_never_enables_control(self):
        m.check_clock_refs()
        m.MMCX_RELEASE.write_text.assert_not_called()
        m.CX_RELEASE.write_text.assert_not_called()

    def test_observer_and_power_checks_fail_closed(self):
        for check in (m.check_power_holds, m.check_cx_votes, m.check_clock_inventory):
            check.side_effect=RuntimeError('guard failure')
            with self.assertRaises(RuntimeError):
                with m.mmcx_trial(True): self.fail('must not run')
            m.MMCX_RELEASE.write_text.assert_not_called()
            check.side_effect=None

    def test_combined_cli_modes_forbidden(self):
        for extra in ('--cx-sleep', '--clock-refs'):
            result=subprocess.run([sys.executable,m.__file__,'--mmcx-sleep',
                                   '--seconds','30',extra],text=True,capture_output=True)
            self.assertEqual(result.returncode,2)
            self.assertIn('no other trial mode',result.stderr)

if __name__ == '__main__':
    unittest.main()
