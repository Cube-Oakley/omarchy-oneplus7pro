import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'


def module():
    spec = importlib.util.spec_from_file_location('clipboard', ROOT / 'clipboard.py')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class ClipboardTests(unittest.TestCase):
    def setUp(self):
        self.m = module()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'clipboard.json'
        self.copied = []

    def run_action(self, name, request=None, paste=''):
        return self.m.action(
            name, request or {}, path=self.path,
            copier=self.copied.append,
            paster=lambda: paste,
            paste_key=lambda: self.copied.append('PASTE'),
        )

    def test_record_dedupes_and_keeps_newest_first(self):
        first = self.run_action('record', {'text': 'one', 'origin': 'local'})
        second = self.run_action('record', {'text': 'two'})
        again = self.run_action('record', {'text': 'one'})
        ids = [item['id'] for item in again['items']]
        self.assertEqual([item['preview'] for item in again['items']], ['one', 'two'])
        self.assertEqual(ids[0], first['id'])
        self.assertEqual(second['count'], 2)
        self.assertTrue(again['ok'])

    def test_evicts_unpinned_not_pinned(self):
        self.m.MAX_ITEMS = 3
        for text in ('a', 'b', 'c'):
            self.run_action('record', {'text': text})
        pin_b = self.run_action('pin', {'id': self.run_action('history')['items'][1]['id']})
        self.assertTrue(pin_b['items'][1]['pinned'])
        self.run_action('record', {'text': 'd'})
        previews = [item['preview'] for item in self.run_action('history')['items']]
        self.assertIn('b', previews)
        self.assertIn('d', previews)
        self.assertEqual(len(previews), 3)

    def test_copy_paste_clear_and_rejects_nul(self):
        recorded = self.run_action('record', {'text': 'secret token'})
        copied = self.run_action('copy', {'id': recorded['id']})
        self.assertEqual(self.copied[-1], 'secret token')
        self.assertEqual(copied['current'], 'secret token')
        self.run_action('paste', {'id': recorded['id']})
        self.assertEqual(self.copied[-2:], ['secret token', 'PASTE'])
        self.run_action('clear')
        self.assertEqual(self.run_action('history')['count'], 0)
        with self.assertRaises(ValueError):
            self.m.record_text({'items': []}, 'x\0y')

    def test_json_request_and_unknown_action(self):
        result = self.m.main(['record'], stdin=io.StringIO('{"text":"hello"}'), path=self.path)
        self.assertEqual(result['items'][0]['text'], 'hello')
        with self.assertRaises(ValueError):
            self.m.action('explode', {}, path=self.path, copier=lambda t: None, paster=lambda: '', paste_key=lambda: None)

    def test_contents_never_appear_in_error_payload(self):
        dumped = json.dumps(self.run_action('record', {'text': 's3cret-value'}))
        self.assertIn('s3cret-value', dumped)
        failed = {'available': False, 'ok': False, 'error': 'Clipboard request failed'}
        self.assertNotIn('s3cret', json.dumps(failed))


if __name__ == '__main__':
    unittest.main()
