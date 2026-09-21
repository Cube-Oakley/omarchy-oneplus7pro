import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "overlay/mobile"))
import theme_install as installer


HTML = """
<ul>
<li><a href="https://github.com/JJDizz1L/aetheria" class="group"><img src="/assets/themes/aetheria.webp" alt="Aetheria theme screenshot" width="1200"/></a></li>
<li><a href="https://github.com/davidguttman/archwave" class="group"><img src="/assets/themes/archwave.webp" alt="Archwave theme screenshot"/></a></li>
<li><a href="https://github.com/evil/ext::id" class="group"><img src="/assets/themes/bad.webp" alt="Bad theme screenshot"/></a></li>
</ul>
"""


class ThemeInstallTests(unittest.TestCase):
    def test_catalog_keeps_named_github_cards(self):
        themes = installer.parse_catalog(HTML)
        self.assertEqual([item["id"] for item in themes], ["aetheria", "archwave"])
        self.assertEqual(themes[0]["preview"], "https://omarchy.us/assets/themes/aetheria.webp")
        self.assertEqual(themes[0]["name"], "Aetheria")

    def test_name_matches_omarchy_repo_stripping(self):
        self.assertEqual(installer.theme_name("https://github.com/x/omarchy-ash-theme.git"), "ash")
        self.assertEqual(installer.theme_name("git@github.com:x/omarchy-blue-theme.git"), "blue")

    def test_refuses_helpers_and_unknown_transports(self):
        for url in ("ext::id", "-upload-pack=touch", "ext://example.com/repo.git", ""):
            with self.assertRaises(ValueError):
                installer.check_url(url)
        installer.check_url("https://github.com/x/omarchy-ash-theme.git")

    def test_unusable_names_are_rejected(self):
        with self.assertRaises(ValueError):
            installer.theme_name("https://github.com/x/..")

    def test_hook_is_the_same_helper(self):
        hook = installer.hook()
        self.assertEqual(hook["install-url"][1:], ["url", "GIT_URL"])
        self.assertEqual(hook["install-name"][1:], ["name", "CATALOG_NAME"])
        self.assertTrue(hook["idempotent"])

    def test_progress_splits_on_carriage_return(self):
        lines, rest = installer.take_lines(b"", b"Receiving objects:  20%\rReceiving objects: 100%\nResolving deltas: 100%\n")
        self.assertEqual(lines, ["Receiving objects:  20%", "Receiving objects: 100%", "Resolving deltas: 100%"])
        self.assertEqual(rest, b"")


if __name__ == "__main__":
    unittest.main()
