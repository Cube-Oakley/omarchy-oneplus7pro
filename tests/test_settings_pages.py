import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SettingsPageTests(unittest.TestCase):
    def test_storage_reports_one_volume_when_home_shares_the_disk(self):
        storage = load('storage')
        with tempfile.TemporaryDirectory() as directory:
            result = storage.snapshot(directory)
        self.assertTrue(result['ok'])
        self.assertGreaterEqual(len(result['volumes']), 1)
        self.assertIn('free', result['volumes'][0])

    def test_revoke_removes_only_the_named_grant(self):
        apps = load('app')
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            os.environ['HOME'] = str(home)
            os.environ['XDG_DATA_HOME'] = str(home / 'data')
            os.environ['XDG_STATE_HOME'] = str(home / 'state')
            manifest = home / 'data/omarchy-mobile/apps/files'
            manifest.mkdir(parents=True)
            (manifest / 'manifest.json').write_text(json.dumps({
                'id': 'files', 'name': 'Files', 'permissions': ['files.home'],
            }))
            apps.grant('files', 'files.home')
            self.assertTrue(apps.has_grant('files', 'files.home'))
            apps.revoke('files', 'files.home')
            self.assertFalse(apps.has_grant('files', 'files.home'))
            listed = apps.installed()
            self.assertEqual(listed['apps'][0]['name'], 'Files')
            self.assertFalse(listed['apps'][0]['permissions'][0]['granted'])


if __name__ == '__main__':
    unittest.main()
