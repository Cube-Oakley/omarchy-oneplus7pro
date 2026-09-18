import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT=Path(__file__).resolve().parents[1]/'overlay/mobile'
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

class BackendTests(unittest.TestCase):
    def test_battery_units_missing_fields_and_charger_disagreement(self):
        m=module('battery')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'bat').mkdir();(root/'usb').mkdir()
            (root/'bat/uevent').write_text('POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_CAPACITY=84\nPOWER_SUPPLY_STATUS=Not charging\nPOWER_SUPPLY_CURRENT_NOW=-123000\nPOWER_SUPPLY_VOLTAGE_NOW=4192000\nPOWER_SUPPLY_TEMP=283\nPOWER_SUPPLY_CHARGE_NOW=3571000\n')
            (root/'usb/uevent').write_text('POWER_SUPPLY_TYPE=USB\nPOWER_SUPPLY_ONLINE=1\nPOWER_SUPPLY_STATUS=Full\nPOWER_SUPPLY_CURRENT_MAX=500000\n')
            r=m.read_battery(root)
            self.assertEqual((r['current_ma'],r['voltage_v'],r['temperature_c'],r['charge_mah']),(-123,4.192,28.3,3571))
            self.assertIsNone(r['full_mah']);self.assertFalse(r['charging'])
            self.assertEqual(r['chargers'][0]['status'],'Full')
            self.assertEqual(r['chargers'][0]['input_limit_ma'],500)

    def test_nmcli_escaping_and_deduplication(self):
        m=module('wifi')
        sample='*:aa\\:bb\\:cc\\:dd\\:ee\\:ff:My\\:Net\\\\name:45:WPA2\n:11\\:22\\:33\\:44\\:55\\:66:My\\:Net\\\\name:90:WPA2\n'
        with patch.object(m,'nmcli',return_value=sample):
            rows=m.networks('wlan0')
        self.assertEqual(len(rows),1);self.assertEqual(rows[0]['ssid'],'My:Net\\name')
        self.assertTrue(rows[0]['active'])
        self.assertEqual(m.split_fields('IP6.ADDRESS[1]:fe80\\:\\:1/64'),['IP6.ADDRESS[1]','fe80::1/64'])

    def test_secret_only_stdin_and_no_shell(self):
        m=module('wifi')
        with patch.object(m,'interfaces',return_value=['wlan0']), patch.object(m.subprocess,'run',return_value=Mock(stdout='')) as run:
            r=m.action('connect',{'interface':'wlan0','bssid':'aa:bb:cc:dd:ee:ff','password':'x$`secret'})
            self.assertTrue(r['ok'])
            args,kwargs=run.call_args
            self.assertNotIn('x$`secret',' '.join(args[0]))
            self.assertEqual(kwargs['input'],'x$`secret\n')
            self.assertNotIn('shell',kwargs)

    def test_invalid_interface_and_multiline_password_never_connect(self):
        m=module('wifi')
        with patch.object(m,'interfaces',return_value=['wlan0']),patch.object(m,'nmcli') as run:
            for request in ({'interface':'eth0'},{'interface':'wlan0','bssid':'bad'}, {'interface':'wlan0','bssid':'aa:bb:cc:dd:ee:ff','password':'x\ny'}):
                with self.assertRaises(ValueError):m.action('connect',request)
            run.assert_not_called()

    def test_weather_opt_in_cache_and_offline_data(self):
        m=module('weather')
        with tempfile.TemporaryDirectory() as d, patch.object(m.sys,'argv',['weather']):
            m.CONFIG=Path(d)/'config';m.CACHE=Path(d)/'cache'
            with patch.object(m,'get') as get:
                self.assertEqual(m.main(),{'configured':False});get.assert_not_called()
            config={'name':'Test','latitude':1,'longitude':2};m.save(m.CONFIG,config)
            cached={'configured':True,'available':True,'location':config,'fetched':m.time.time(),'current':{}}
            m.save(m.CACHE,cached)
            with patch.object(m,'get') as get:
                self.assertEqual(m.main(),cached);get.assert_not_called()
            cached['fetched']=0;m.save(m.CACHE,cached)
            with patch.object(m,'get',side_effect=OSError('offline')):
                result=m.main();self.assertTrue(result['stale']);self.assertTrue(result['available'])

if __name__=='__main__': unittest.main()
