import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def load():
    spec = importlib.util.spec_from_file_location('bluetooth', ROOT / 'bluetooth.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def v(kind, data):
    return {'type': kind, 'data': data}


def device(address, name=None, paired=False, connected=False, rssi=None, battery=None):
    props = {'Address': v('s', address), 'Alias': v('s', name or address.replace(':', '-')),
             'Paired': v('b', paired), 'Trusted': v('b', paired), 'Connected': v('b', connected),
             'Icon': v('s', 'audio-headset')}
    if name:
        props['Name'] = v('s', name)
    if rssi is not None:
        props['RSSI'] = v('n', rssi)
    ifaces = {'org.bluez.Device1': props}
    if battery is not None:
        ifaces['org.bluez.Battery1'] = {'Percentage': v('y', battery)}
    return ifaces


OBJECTS = {
    '/org/bluez': {'org.bluez.AgentManager1': {}},
    '/org/bluez/hci0': {'org.bluez.Adapter1': {
        'Address': v('s', '02:00:00:00:00:01'), 'Name': v('s', 'BlueZ 5.87'),
        'Alias': v('s', 'Phone'), 'Powered': v('b', True), 'Discovering': v('b', False)}},
    '/org/bluez/hci0/dev_11_22_33_44_55_66': device('11:22:33:44:55:66', 'Headphones', True, True, battery=80),
    '/org/bluez/hci0/dev_22_22_33_44_55_66': device('22:22:33:44:55:66', 'Old speaker', True, False),
    '/org/bluez/hci0/dev_33_22_33_44_55_66': device('33:22:33:44:55:66', 'Far TV', rssi=-90),
    '/org/bluez/hci0/dev_44_22_33_44_55_66': device('44:22:33:44:55:66', 'Near watch', rssi=-40),
    '/org/bluez/hci0/dev_55_22_33_44_55_66': device('55:22:33:44:55:66', rssi=-30),
}


class BluetoothTests(unittest.TestCase):
    def test_snapshot_reads_adapter_and_devices(self):
        status = load().snapshot(OBJECTS)
        self.assertTrue(status['available'])
        self.assertEqual(status['name'], 'Phone')
        self.assertTrue(status['powered'])
        headphones = status['devices'][0]
        self.assertEqual((headphones['name'], headphones['connected'], headphones['battery']),
                         ('Headphones', True, 80))

    def test_devices_sort_connected_then_paired_then_signal(self):
        names = [d['name'] for d in load().snapshot(OBJECTS)['devices']]
        self.assertEqual(names[:2], ['Headphones', 'Old speaker'])
        self.assertLess(names.index('Near watch'), names.index('Far TV'))

    def test_nameless_devices_are_marked_for_hiding(self):
        nameless = [d for d in load().snapshot(OBJECTS)['devices'] if not d['named']]
        self.assertEqual([d['address'] for d in nameless], ['55:22:33:44:55:66'])

    def test_no_adapter_is_unavailable(self):
        status = load().snapshot({'/org/bluez': {'org.bluez.AgentManager1': {}}})
        self.assertFalse(status['available'])
        self.assertEqual(status['devices'], [])

    def test_rejects_bad_addresses_and_actions(self):
        bluetooth = load()
        with mock.patch.object(bluetooth, 'read_status', return_value=bluetooth.snapshot(OBJECTS)):
            for args in (['pair', 'not-an-address'], ['connect'], ['power', 'maybe'], ['explode']):
                with self.assertRaises(ValueError):
                    bluetooth.act(args)

    def test_failed_action_keeps_the_controller_available(self):
        bluetooth = load()
        out = io.StringIO()
        with mock.patch.object(bluetooth, 'read_status', return_value=bluetooth.snapshot(OBJECTS)), \
                mock.patch('sys.stdout', out):
            self.assertEqual(bluetooth.main(['pair', 'bad']), 1)
        result = json.loads(out.getvalue())
        self.assertTrue(result['available'])
        self.assertFalse(result['ok'])

    def test_power_on_runs_the_board_start_command_without_a_controller(self):
        bluetooth = load()
        down = bluetooth.unavailable('Bluetooth is not running.')
        up = bluetooth.snapshot(OBJECTS)
        with mock.patch.object(bluetooth, 'start_command', return_value='/usr/local/sbin/bt-start'), \
                mock.patch.object(bluetooth, 'read_status', side_effect=[down, up, up]), \
                mock.patch.object(bluetooth, 'ctl', return_value=(True, '')) as ctl, \
                mock.patch('subprocess.run') as run:
            status, ok, _ = bluetooth.power(True)
        run.assert_called_once()
        self.assertEqual(run.call_args[0][0], ['/usr/local/sbin/bt-start'])
        ctl.assert_called_once_with('power', 'on')
        self.assertTrue(ok and status['available'])


if __name__ == '__main__':
    unittest.main()
