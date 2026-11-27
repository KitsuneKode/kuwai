"""The screensaver's looks: every one the settings schema allows is one the screensaver draws, the
Settings page offers and the Themes tab lists; and a failed film is retried, not remembered.

A look the schema allowed but nothing drew was a setting that did nothing; a film that failed once
kept Dusk on screen for the rest of the session, after the file was back and the look re-picked."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "shell"
SAVER = (SHELL / "modules/screensaver/Screensaver.qml").read_text()
SETTINGS_PANEL = (SHELL / "modules/island/SettingsPanel.qml").read_text()
THEME_PANEL = (SHELL / "modules/island/ThemePanel.qml").read_text()


def styles():
    schema = json.loads((SHELL / "config/settings-schema.json").read_text())
    return next(e for e in schema["settings"] if e["key"] == "screensaverStyle")["enum"]


class SaverStyles(unittest.TestCase):
    def test_every_look_is_drawn_offered_and_listed(self):
        for st in styles():
            with self.subTest(style=st):
                self.assertIn(f'"{st}"', SAVER, "Screensaver.qml never mentions it")
                self.assertRegex(SETTINGS_PANEL, rf'id: "{st}"', "Settings → Screensaver doesn't offer it")
                self.assertRegex(THEME_PANEL, rf'style: "{st}"', "Themes → Screensaver doesn't list it")

    def test_a_drawn_scene_has_its_file_and_thumbnail(self):
        self.assertTrue((SHELL / "modules/screensaver/BorealisScene.qml").exists())
        self.assertTrue((SHELL / "assets/screensaver/borealis.jpg").exists())

    def test_a_failed_film_is_retried_not_remembered(self):
        self.assertRegex(SAVER, r"function filmFresh\(\) \{ clipFailed = false; \}")   # filmOnCpu stays learnt
        for on in ("onStyleChanged", "onClipChanged", "onVideoChanged"):
            self.assertRegex(SAVER, on + r":\s*filmFresh\(\)")
        self.assertRegex(SAVER, r"if \(showing\) \{[^}]*filmFresh\(\)")
        self.assertIn("didn't start", SAVER, "the failure is logged, so 'it didn't change' has a reason to find")

    def test_theme_tokens_it_uses_exist(self):
        theme = (SHELL / "config/Theme.qml").read_text()
        scene = (SHELL / "modules/screensaver/BorealisScene.qml").read_text()
        for name in set(re.findall(r"Theme\.(borealis\w+)", scene)):
            self.assertRegex(theme, rf"property \w+ {name}\b", name)



def test_every_picker_tab_names_where_tab_goes_and_no_empty_picture():
    # The Screensaver tab had no ⇥ label (undefined, a warning per showing) and the preview
    # asked for file:/// (a folder) for an item with no picture.
    qml = (ROOT / "shell/modules/island/ThemePanel.qml").read_text()
    modes = re.findall(r'"(\w+)"', re.search(r"readonly property var modes: \[(.*?)\]", qml)[1])
    nxt = dict(re.findall(r'(\w+): "(\w+)"', re.search(r'\["Tab", \(\{(.*?)\}\)', qml)[1]))
    assert set(nxt) == set(modes)
    for i, m in enumerate(modes):   # the label is the tab after it, in order
        label = {"themes": "Themes", "wallpapers": "Wallpapers", "live": "Live", "saver": "Screensaver"}[modes[(i + 1) % len(modes)]]
        assert nxt[m] == label, (m, nxt[m])
    assert '"file://" + (preview.it.thumb || preview.it.path || "")' not in qml
    # A spinner bound to `parent.visible` warned 81 times a close: parent is null while cards go.
    assert "running: parent.visible" not in qml


if __name__ == "__main__":
    unittest.main()
