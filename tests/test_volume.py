import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1] / 'overlay/mobile'
spec = importlib.util.spec_from_file_location('volume', ROOT / 'volume.py')
volume = importlib.util.module_from_spec(spec)
spec.loader.exec_module(volume)


def sink(node_id, name):
    return {'id': node_id, 'type': 'PipeWire:Interface:Node',
            'info': {'props': {'media.class': 'Audio/Sink', 'node.name': name}}}


def control(name):
    return {'id': 40, 'type': 'PipeWire:Interface:Metadata',
            'metadata': [{'subject': 0, 'key': 'default.audio.sink', 'value': {'name': 'speakers'}},
                         {'subject': 0, 'key': volume.CONTROL_KEY, 'value': {'name': name}}]}


GROUP_SINKS = [sink(31, 'guacamole-speakers'),
               sink(50, volume.GROUPS['media']), sink(51, volume.GROUPS['ring']),
               sink(52, volume.GROUPS['call']), sink(53, volume.GROUPS['alarm'])]
LEVELS = {'50': 'Volume: 0.60', '51': 'Volume: 0.80 [MUTED]', '52': 'Volume: 1.00',
          '53': 'Volume: 0.45', '60': 'Volume: 0.40', '@DEFAULT_AUDIO_SINK@': 'Volume: 0.85'}
HEADPHONES = {'id': 60, 'type': 'PipeWire:Interface:Node', 'info': {'props': {
    'media.class': 'Audio/Sink', 'node.name': 'bluez_output.11_22_33_44_55_66.1',
    'node.description': 'Headphones', 'device.api': 'bluez5'}}}
ON_HEADPHONES = {'id': 40, 'type': 'PipeWire:Interface:Metadata', 'metadata': [
    {'subject': 0, 'key': 'default.audio.sink', 'value': {'name': 'bluez_output.11_22_33_44_55_66.1'}}]}


class VolumeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        state = patch.object(volume, 'STATE', Path(self.tmp.name) / 'volume.json')
        state.start()
        self.addCleanup(state.stop)
        self.addCleanup(self.tmp.cleanup)

    def run_volume(self, objects, args):
        calls = []

        def wpctl(*a):
            calls.append(a)
            return LEVELS[a[-1]] + '\n' if a[0] == 'get-volume' else ''
        with patch.object(volume, 'pw_dump', return_value=objects), patch.object(volume, 'wpctl', wpctl):
            result = volume.main(args)
        return result, [c for c in calls if c[0] != 'get-volume']

    def test_status_keeps_media_at_top_level_for_older_callers(self):
        result, changes = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['media'])], [])
        self.assertEqual((result['percent'], result['muted'], result['keys']), (60, False, 'media'))
        self.assertEqual(result['groups']['ring'], {'available': True, 'percent': 80, 'muted': True})
        self.assertEqual(result['groups']['alarm']['percent'], 45)
        self.assertEqual(changes, [])

    def test_keys_follow_the_group_wireplumber_selects(self):
        result, changes = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['call'])], ['up'])
        self.assertEqual(result['keys'], 'call')
        self.assertEqual(changes, [('set-volume', '-l', '1.0', '52', '5%+'), ('set-mute', '52', '0')])
        self.assertEqual(result['changed'], 'call')

    def test_explicit_group_and_set_default_to_media(self):
        _, changes = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['call'])], ['mute', 'ring'])
        self.assertEqual(changes, [('set-mute', '51', 'toggle')])
        _, changes = self.run_volume(GROUP_SINKS, ['mute', 'ring', 'on'])
        self.assertEqual(changes, [('set-mute', '51', '1')])
        _, changes = self.run_volume(GROUP_SINKS, ['mute', 'ring', 'off'])
        self.assertEqual(changes, [('set-mute', '51', '0')])
        _, changes = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['call'])], ['set', '30'])
        self.assertEqual(changes, [('set-volume', '-l', '1.0', '50', '30%'), ('set-mute', '50', '0')])
        _, changes = self.run_volume(GROUP_SINKS, ['set', '0', 'alarm'])
        self.assertEqual(changes, [('set-volume', '-l', '1.0', '53', '0%')])

    def test_without_group_loopbacks_media_uses_the_default_sink(self):
        result, changes = self.run_volume([sink(31, 'guacamole-speakers')], ['down'])
        self.assertEqual(changes, [('set-volume', '-l', '1.0', '@DEFAULT_AUDIO_SINK@', '5%-')])
        self.assertEqual(result['percent'], 85)
        self.assertFalse(result['groups']['call']['available'])

    def test_unknown_stale_or_unavailable_targets_are_refused(self):
        with self.assertRaises(ValueError):
            self.run_volume([sink(31, 'guacamole-speakers')], ['mute', 'call'])
        with self.assertRaises(ValueError):
            self.run_volume(GROUP_SINKS, ['up', 'speaker'])
        with self.assertRaises(ValueError):
            self.run_volume(GROUP_SINKS, ['set', '101'])
        # A published control naming a vanished loopback falls back to media.
        result, _ = self.run_volume([sink(31, 'guacamole-speakers'), sink(50, volume.GROUPS['media']),
                                     control(volume.GROUPS['call'])], [])
        self.assertEqual(result['keys'], 'media')

    def test_reports_the_output_the_groups_play_into(self):
        speakers = dict(sink(31, 'speakers'))
        speakers['info'] = {'props': {'media.class': 'Audio/Sink', 'node.name': 'speakers',
                                      'node.description': 'Internal speakers'}}
        result, _ = self.run_volume([speakers] + GROUP_SINKS[1:] + [control(volume.GROUPS['media'])], [])
        self.assertEqual(result['output'], {'name': 'speakers', 'id': '31',
                                            'description': 'Internal speakers', 'bluetooth': False})
        result, _ = self.run_volume([HEADPHONES] + GROUP_SINKS[1:] + [ON_HEADPHONES], [])
        self.assertTrue(result['output']['bluetooth'])
        self.assertEqual(result['output']['description'], 'Headphones')

    def test_headphones_media_is_their_own_volume(self):
        result, calls = self.run_volume([HEADPHONES] + GROUP_SINKS[1:] + [ON_HEADPHONES], ['up'])
        # Entering headphones remembers the speaker level and opens the media loopback.
        self.assertIn(('set-volume', '-l', '1.0', '50', '100%'), calls)
        self.assertIn(('set-volume', '-l', '1.0', '60', '5%+'), calls)
        self.assertEqual(result['groups']['media']['percent'], 40)
        self.assertEqual(json.loads(volume.STATE.read_text()), {'speakerMedia': 60, 'bluetooth': True})

    def test_speaker_level_returns_when_headphones_leave(self):
        volume.STATE.write_text(json.dumps({'speakerMedia': 35, 'bluetooth': True}))
        _, calls = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['media'])], [])
        self.assertEqual(calls, [('set-volume', '-l', '1.0', '50', '35%')])
        self.assertFalse(json.loads(volume.STATE.read_text())['bluetooth'])
        _, calls = self.run_volume(GROUP_SINKS + [control(volume.GROUPS['media'])], [])
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
