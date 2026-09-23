import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def module():
    spec = importlib.util.spec_from_file_location('stats', ROOT / 'stats.py')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class StatsTests(unittest.TestCase):
    def test_cpu_memory_thermals_and_busy_processes(self):
        m = module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            proc = root / 'proc'
            thermal = root / 'thermal'
            write(proc / 'stat', 'cpu  10 0 10 80 0 0 0 0 0 0\ncpu0 5 0 5 40 0 0 0 0 0 0\ncpu1 5 0 5 40 0 0 0 0 0 0\n')
            write(proc / 'meminfo', 'MemTotal:        2048000 kB\nMemAvailable:     512000 kB\n')
            write(proc / 'loadavg', '0.40 0.30 0.20 1/200 9\n')
            write(thermal / 'thermal_zone0' / 'type', 'cpu-silver\n')
            write(thermal / 'thermal_zone0' / 'temp', '42100\n')
            write(thermal / 'thermal_zone1' / 'type', 'gpu\n')
            write(thermal / 'thermal_zone1' / 'temp', '39000\n')
            write(thermal / 'thermal_zone2' / 'type', 'broken\n')
            write(thermal / 'thermal_zone2' / 'temp', '9990000\n')
            write(proc / '1' / 'stat', '1 (init) S 0 0 0 0 0 0 0 0 0 0 5 5 0 0 0 0 0 0 0\n')
            write(proc / '1' / 'cmdline', '/sbin/init\x00')
            write(proc / '1' / 'status', 'VmRSS:\t  10240 kB\n')
            write(proc / '2' / 'stat', '2 (kthreadd) S 0 0 0 0 0 0 0 0 0 0 9 9 0 0 0 0 0 0 0\n')
            write(proc / '2' / 'cmdline', '')
            write(proc / '2' / 'status', 'VmRSS:\t  1 kB\n')
            write(proc / '9' / 'stat', '9 (Hyprland) R 1 0 0 0 0 0 0 0 0 0 20 10 0 0 0 0 0 0 0\n')
            write(proc / '9' / 'cmdline', 'Hyprland\x00')
            write(proc / '9' / 'status', 'VmRSS:\t  204800 kB\n')
            first = m.snapshot(proc=proc, thermal=thermal, previous=None, now=1)
            self.assertTrue(first['available'])
            self.assertIsNone(first['cpu'])
            self.assertEqual(first['memory']['percent'], 75.0)
            self.assertEqual(first['memory']['total_mb'], 2000.0)
            self.assertEqual(first['load'], [0.4, 0.3, 0.2])
            self.assertEqual([row['name'] for row in first['thermals']], ['cpu-silver', 'gpu'])
            write(proc / 'stat', 'cpu  30 0 30 120 0 0 0 0 0 0\ncpu0 15 0 15 60 0 0 0 0 0 0\ncpu1 15 0 15 60 0 0 0 0 0 0\n')
            write(proc / '9' / 'stat', '9 (Hyprland) R 1 0 0 0 0 0 0 0 0 0 50 20 0 0 0 0 0 0 0\n')
            write(proc / '1' / 'stat', '1 (init) S 0 0 0 0 0 0 0 0 0 0 6 5 0 0 0 0 0 0 0\n')
            previous = {'cpu': first['_cpu'], 'cores': first['_cores'], 'processes': first['_processes']}
            second = m.snapshot(proc=proc, thermal=thermal, previous=previous, now=2)
            self.assertEqual(second['cpu'], 50.0)
            self.assertEqual(second['cores'], [50.0, 50.0])
            names = [row['name'] for row in second['processes']]
            self.assertEqual(names[0], 'Hyprland')
            self.assertNotIn('kthreadd', names)
            self.assertEqual(second['processes'][0]['cpu'], 50.0)
            self.assertEqual(second['processes'][0]['rss_mb'], 200.0)
            self.assertEqual(m.public(second)['cpu'], 50.0)
            self.assertNotIn('_cpu', m.public(second))

    def test_cache_round_trip_and_missing_proc(self):
        m = module()
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'stats.json'
            missing = Path(directory) / 'missing'
            self.assertEqual(m.main(proc=missing, thermal=missing, cache=cache), {'available': False})


if __name__ == '__main__':
    unittest.main()
