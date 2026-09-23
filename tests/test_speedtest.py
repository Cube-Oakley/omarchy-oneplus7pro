import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def module():
    spec = importlib.util.spec_from_file_location('speedtest', ROOT / 'speedtest.py')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class FakeResponse:
    def __init__(self, data):
        self.data = data
    def read(self, n=-1):
        if n < 0:
            out, self.data = self.data, b''
            return out
        out, self.data = self.data[:n], self.data[n:]
        return out
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False


class FakeHandle:
    def __init__(self, payload=b'x' * 2048):
        self.payload = payload
        self.calls = []
    def open(self, req, timeout=0):
        self.calls.append((req.full_url, req.get_method(), timeout))
        return FakeResponse(self.payload)


class SpeedtestTests(unittest.TestCase):
    def test_mbps_and_successful_run_emits_done(self):
        m = module()
        self.assertEqual(m.mbps(1_000_000, 1), 8.0)
        self.assertEqual(m.mbps(10, 0), 0.0)
        handle = FakeHandle()
        lines = []
        with patch.object(m, 'PING_BYTES', 8), patch.object(m, 'DOWN_BYTES', 64), \
             patch.object(m, 'UP_CHUNK', 8), patch.object(m, 'UP_LIMIT', 8), \
             patch.object(m, 'PHASE_SECONDS', 0.05), patch.object(m, 'emit', side_effect=lambda p: lines.append(p)):
            self.assertEqual(m.run(handle), 0)
        phases = [row['phase'] for row in lines]
        self.assertIn('done', phases)
        done = next(row for row in lines if row['phase'] == 'done')
        self.assertIn('download_mbps', done)
        self.assertEqual(done['server'], 'Cloudflare')

    def test_error_path_is_generic(self):
        m = module()
        class Boom:
            def open(self, req, timeout=0):
                raise OSError('offline')
        lines = []
        with patch.object(m, 'emit', side_effect=lambda p: lines.append(p)):
            self.assertEqual(m.run(Boom()), 1)
        self.assertEqual(lines[-1]['phase'], 'error')
        self.assertNotIn('offline', json.dumps(lines[-1]))


if __name__ == '__main__':
    unittest.main()
