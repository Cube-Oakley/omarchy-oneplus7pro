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


class FilesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name) / 'home'
        self.home.mkdir()
        (self.home / 'Downloads').mkdir()
        (self.home / 'notes.txt').write_text('hello')
        (self.home / 'big.bin').write_bytes(b'x' * 5000)
        (self.home / '.secret').write_text('hidden')
        outside = Path(self.temporary.name) / 'secret'
        outside.mkdir()
        (outside / 'key').write_text('nope')
        (self.home / 'escape').symlink_to(outside)
        state = Path(self.temporary.name) / 'state'
        data = Path(self.temporary.name) / 'data'
        os.environ['XDG_STATE_HOME'] = str(state)
        os.environ['XDG_DATA_HOME'] = str(data)
        os.environ['HOME'] = str(self.home)
        app = data / 'omarchy-mobile/apps/files'
        app.mkdir(parents=True)
        (app / 'manifest.json').write_text(json.dumps({
            'id': 'files',
            'name': 'Files',
            'permissions': ['files.home'],
        }))
        self.apps = load('app')
        self.files = load('files')

    def tearDown(self):
        self.temporary.cleanup()

    def test_unknown_permission_is_rejected(self):
        path = Path(os.environ['XDG_DATA_HOME']) / 'omarchy-mobile/apps/files/manifest.json'
        path.write_text(json.dumps({'id': 'files', 'permissions': ['files.system']}))
        with self.assertRaises(ValueError):
            self.apps.load_manifest('files')

    def test_grant_is_required_and_limited_to_the_manifest(self):
        with self.assertRaises(PermissionError):
            self.files.roots_for()
        self.apps.grant('files', 'files.home')
        self.assertTrue(self.apps.has_grant('files', 'files.home'))
        with self.assertRaises(ValueError):
            self.apps.grant('files', 'files.system')

    def test_listing_stays_inside_home_and_hides_symlink_escapes(self):
        self.apps.grant('files', 'files.home')
        roots = self.files.home_roots(self.home)
        listed = self.files.snapshot(self.home, roots)
        names = [item['name'] for item in listed['entries']]
        self.assertIn('Downloads', names)
        self.assertIn('notes.txt', names)
        self.assertNotIn('escape', names)
        self.assertNotIn('.secret', names)
        self.assertEqual(listed['name'], 'Home')
        self.assertEqual(listed['crumbs'][-1]['name'], 'Home')
        shown = self.files.snapshot(self.home, roots, hidden=True)
        self.assertIn('.secret', [item['name'] for item in shown['entries']])
        by_size = self.files.snapshot(self.home, roots, order='size')
        files = [item['name'] for item in by_size['entries'] if not item['dir']]
        self.assertEqual(files[0], 'big.bin')
        self.assertIsNone(listed['parent'])
        with self.assertRaises(PermissionError):
            self.files.snapshot('/', roots)
        with self.assertRaises(PermissionError):
            self.files.snapshot(self.home / 'escape', roots)

    def test_mkdir_and_delete_cannot_leave_home_or_remove_it(self):
        self.apps.grant('files', 'files.home')
        roots = self.files.home_roots(self.home)
        made = self.files.make_dir(self.home, 'Album', roots)
        self.assertTrue((self.home / 'Album').is_dir())
        self.assertIn('Album', [item['name'] for item in made['entries']])
        with self.assertRaises(ValueError):
            self.files.make_dir(self.home, '../Album', roots)
        with self.assertRaises(PermissionError):
            self.files.remove(self.home, roots)
        self.files.remove(self.home / 'notes.txt', roots)
        self.assertFalse((self.home / 'notes.txt').exists())
        self.files.rename(self.home / 'big.bin', 'bigger.bin', roots)
        self.assertTrue((self.home / 'bigger.bin').is_file())
        with self.assertRaises(PermissionError):
            self.files.rename(self.home, 'nope', roots)
        moved = self.files.transfer(self.home / 'bigger.bin', self.home / 'Downloads', roots, False)
        self.assertTrue((self.home / 'Downloads' / 'bigger.bin').is_file())
        self.assertEqual(moved['path'], str((self.home / 'Downloads').resolve()))
        with self.assertRaises(PermissionError):
            self.files.transfer(self.home / 'Downloads' / 'bigger.bin', Path('/'), roots, False)
        copied = self.files.transfer(self.home / 'Downloads' / 'bigger.bin', self.home, roots, True)
        self.assertTrue((self.home / 'bigger.bin').is_file())
        self.assertIn('bigger.bin', [item['name'] for item in copied['entries']])
        (self.home / 'readme.txt').write_text('hello file')
        text = self.files.preview(self.home / 'readme.txt', roots)
        self.assertEqual(text['text'], 'hello file')
        self.assertEqual(text['kind'], 'text')


if __name__ == '__main__':
    unittest.main()
