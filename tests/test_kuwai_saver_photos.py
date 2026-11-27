import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "bin" / "kuwai-saver-photos"


def run(home, *args, state=None):
    env = {"PATH": os.environ["PATH"], "HOME": str(home)}
    if state:
        env["XDG_STATE_HOME"] = str(state)
    done = subprocess.run([sys.executable, str(TOOL), *args], env=env, capture_output=True, text=True, timeout=20)
    return done


def touch(path, size=4):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    return path


class SaverPhotos(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def theme(self, name):
        state = self.home / ".local/state/hyde/staterc"
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(f'HYDE_THEME="{name}"\n')

    def test_a_folder_lists_its_pictures_only_sorted_and_without_hidden_or_empty_files(self):
        pics = self.home / "Pictures"
        for name in ("b.JPG", "a.png", "c.webp", "notes.txt", ".hidden.jpg"):
            touch(pics / name)
        touch(pics / "empty.jpg", 0)
        (pics / "sub").mkdir()
        touch(pics / "sub" / "deep.jpg")
        done = run(self.home, str(pics))
        self.assertEqual(done.returncode, 0)
        self.assertEqual([Path(p).name for p in json.loads(done.stdout)], ["a.png", "b.JPG", "c.webp"])

    def test_no_folder_is_the_current_themes_wallpapers(self):
        self.theme("Nord")
        walls = self.home / ".config/hyde/themes/Nord/wallpapers"
        touch(walls / "two.jpg")
        touch(walls / "one.png")
        touch(self.home / ".config/hyde/themes/Other/wallpapers/x.jpg")
        done = run(self.home)
        self.assertEqual([Path(p).name for p in json.loads(done.stdout)], ["one.png", "two.jpg"])

    def test_a_theme_with_none_falls_back_to_the_folder_of_the_wallpaper_in_use(self):
        self.theme("Bare")
        (self.home / ".config/hyde/themes/Bare").mkdir(parents=True)
        shots = self.home / "Pictures/walls"
        touch(shots / "now.jpg")
        touch(shots / "other.jpg")
        link = self.home / "state/kuwai/wallpaper"
        link.parent.mkdir(parents=True)
        link.symlink_to(shots / "now.jpg")
        done = run(self.home, state=self.home / "state")
        self.assertEqual([Path(p).name for p in json.loads(done.stdout)], ["now.jpg", "other.jpg"])

    def test_nothing_there_is_an_empty_list_not_an_error(self):
        self.assertEqual(json.loads(run(self.home).stdout), [])
        self.assertEqual(json.loads(run(self.home, str(self.home / "missing")).stdout), [])

    def test_a_home_relative_folder_and_a_cap(self):
        pics = self.home / "Pics"
        for i in range(450):
            touch(pics / f"{i:04}.jpg", 1)
        done = run(self.home, "~/Pics")
        self.assertEqual(len(json.loads(done.stdout)), 400)

    def test_extra_arguments_are_refused(self):
        self.assertEqual(run(self.home, "a", "b").returncode, 2)


if __name__ == "__main__":
    unittest.main()
