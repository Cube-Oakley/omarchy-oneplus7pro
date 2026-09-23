"""Theme background compatibility and persistence, without desktop side effects."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('mobile_theme', Path(__file__).resolve().parents[1] / 'overlay/mobile/theme.py')


class ThemeBackgroundTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.m = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.m)
        root = Path(self.tmp.name)
        self.m.HOME = root
        self.m.CONFIG = root / 'config'
        self.m.STATE = root / 'state'
        self.m.DATA = root / 'data'
        self.m.MOBILE = self.m.STATE / 'omarchy-mobile'
        self.m.ROOTS = [root / 'fallback', root / 'stock', self.m.CONFIG / 'omarchy/themes']
        self.m.MOBILE.mkdir(parents=True)

    def file(self, path, text='fixture'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def theme(self, root, name='tokyo-night'):
        return self.file(root / name / 'colors.toml', 'background = "#123456"\n')

    def test_commented_rounding_is_unset_and_an_active_value_is_kept(self):
        self.assertIsNone(self.m.corner_radius())
        self.file(self.m.CONFIG / 'hypr/looknfeel.lua', '-- rounding = 8\n')
        self.assertIsNone(self.m.corner_radius())
        self.file(self.m.CONFIG / 'hypr/looknfeel.lua', 'hl.config({ decoration = { rounding = 0 } })\n')
        self.assertEqual(self.m.corner_radius(), 0)
        self.file(self.m.CONFIG / 'hypr/looknfeel.lua', 'hl.config({ decoration = { rounding = 8 } })\n')
        self.assertEqual(self.m.corner_radius(), 8)
        self.file(self.m.STATE / 'omarchy/toggles/hypr/rounded-corners.lua', 'hl.config({ decoration = { rounding = 6 } })\n')
        self.assertEqual(self.m.corner_radius(), 6)

    def test_overlay_and_user_backgrounds_preserve_stock(self):
        roots = self.m.ROOTS
        self.theme(roots[1])
        a = self.file(roots[1] / 'tokyo-night/backgrounds/a.jpg')
        self.file(roots[1] / 'tokyo-night/backgrounds/b.png')
        b = self.file(roots[2] / 'tokyo-night/backgrounds/b.png')
        c = self.file(self.m.CONFIG / 'omarchy/backgrounds/tokyo-night/c.WEBP')
        self.file(roots[1] / 'tokyo-night/backgrounds/script.lua')
        self.assertEqual(self.m.wallpaper_choices('tokyo-night', None), [a, b, c])

    def test_cycle_persists_per_theme_and_wraps(self):
        for theme in ['tokyo-night', 'nord']:
            self.theme(self.m.ROOTS[0], theme)
            for name in ['a.jpg', 'b.png']:
                self.file(self.m.ROOTS[0] / theme / 'backgrounds' / name)
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None)['name'], 'a.jpg')
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None, True)['name'], 'b.png')
        self.assertEqual(self.m.wallpaper_state('nord', None)['name'], 'a.jpg')
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None)['name'], 'b.png')
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None, True)['name'], 'a.jpg')
        self.assertIn('tokyo-night', json.loads((self.m.MOBILE / 'backgrounds.json').read_text()))

    def test_current_state_wins_and_background_link_is_read_only(self):
        self.theme(self.m.ROOTS[0])
        modern = self.m.STATE / 'omarchy/current/theme'
        self.file(modern / 'colors.toml', 'background = "#abcdef"\n')
        self.file(modern.parent / 'theme.name', 'Custom Theme\n')
        chosen = self.file(self.m.HOME / 'Pictures/a #1.jpg')
        (modern.parent / 'background').symlink_to(chosen)
        _, selected, palette, current = self.m.theme_context()
        self.assertEqual((selected, palette, current), ('Custom Theme', modern / 'colors.toml', modern))
        bg = self.m.wallpaper_state(selected, current)
        self.assertEqual(bg['path'], str(chosen))
        self.assertIn('a%20%231.jpg', bg['url'])
        with self.assertRaises(ValueError):
            self.m.wallpaper_state(selected, current, True)
        self.assertEqual((modern.parent / 'background').readlink(), chosen)

    def test_legacy_current_symlink(self):
        theme = self.theme(self.m.ROOTS[2], 'nord').parent
        current = self.m.CONFIG / 'omarchy/current/theme'
        current.parent.mkdir(parents=True)
        current.symlink_to(theme, target_is_directory=True)
        self.assertEqual(self.m.theme_context()[1], 'nord')

    def test_missing_selection_falls_back_and_empty_theme_uses_color(self):
        bg = self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/a.jpg')
        self.m.wallpaper_state('tokyo-night', None)
        bg.unlink()
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None)['url'], '')
        with self.assertRaisesRegex(ValueError, 'no wallpapers'):
            self.m.wallpaper_state('tokyo-night', None, True)

    def test_wallpaper_only_change_does_not_restart_keyboard_or_signal_kitty(self):
        self.theme(self.m.ROOTS[0])
        for name in ['a.jpg', 'b.jpg']:
            self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds' / name)
        with patch.object(self.m, 'signal_owned') as signals, patch.object(self.m.subprocess, 'run') as run:
            self.m.sync()
            signals.reset_mock()
            run.reset_mock()
            self.m.wallpaper_state('tokyo-night', None, True)
            result = self.m.sync()
            self.assertEqual(result['wallpaper']['name'], 'b.jpg')
            signals.assert_not_called()
            run.assert_not_called()

    def test_device_display_mode_is_validated(self):
        self.theme(self.m.ROOTS[0])
        device = self.m.CONFIG / 'omarchy-mobile/device.json'
        device.parent.mkdir(parents=True, exist_ok=True)
        lua = self.m.CONFIG / 'hypr/mobile.lua'
        for requested, expected in (('1440x3120@90', '1440x3120@90'),
                                    ('1440x3120@90",scale=9})\nos.exit()', 'preferred'),
                                    (None, 'preferred')):
            device.write_text(json.dumps({'scale': 3, 'displayMode': requested}))
            with patch.object(self.m, 'signal_owned'), patch.object(self.m.subprocess, 'run'):
                self.m.sync()
            self.assertIn(f'hl.monitor({{output="",mode="{expected}",position="auto",scale=3}})', lua.read_text())

    def test_device_hook_receives_changed_image_as_one_argument(self):
        self.theme(self.m.ROOTS[0])
        first = self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/a #1.jpg')
        second = self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/b.jpg')
        hook = self.file(self.m.CONFIG / 'omarchy-mobile/wallpaper-apply')
        hook.chmod(0o755)
        with patch.object(self.m, 'signal_owned'), patch.object(self.m.subprocess, 'run') as run:
            self.m.sync()
            self.assertEqual(run.call_args_list[0].args[0], [str(hook), str(first)])
            run.reset_mock()
            self.m.sync()
            run.assert_not_called()
            self.m.wallpaper_state('tokyo-night', None, True)
            self.m.sync()
            self.assertEqual(run.call_args.args[0], [str(hook), str(second)])

    def test_wallpaper_choices_and_pick_by_name(self):
        self.theme(self.m.ROOTS[0])
        self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/a.jpg')
        b = self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/b.jpg')
        state = self.m.wallpaper_state('tokyo-night', None)
        self.assertEqual([item['name'] for item in state['choices']], ['a.jpg', 'b.jpg'])
        self.assertEqual(state['name'], 'a.jpg')
        self.m.wallpaper_pick('tokyo-night', None, 'b.jpg')
        self.assertEqual(self.m.wallpaper_state('tokyo-night', None)['name'], 'b.jpg')
        self.assertEqual(self.m.wallpaper_pick('tokyo-night', None, str(b)), b.resolve())
        with self.assertRaisesRegex(ValueError, 'Unknown wallpaper'):
            self.m.wallpaper_pick('tokyo-night', None, 'missing.jpg')

    def test_theme_previews_use_first_wallpaper(self):
        self.theme(self.m.ROOTS[0])
        first = self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/a.jpg')
        self.file(self.m.ROOTS[0] / 'tokyo-night/backgrounds/b.jpg')
        previews = self.m.theme_previews({'tokyo-night': first})
        self.assertIn('tokyo-night', previews)
        self.assertIn('a.jpg', previews['tokyo-night'])

if __name__ == '__main__':
    unittest.main()
