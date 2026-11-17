"""bin/kuwai-migrate: ~/.local/share/rice moves into ~/.local/share/kuwai, which is also the
stable copy of the repo. The rename once moved state, cache and config but not this folder, so
the screensaver films, the clipboard pins, alarms and reminders stayed behind under the old name."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(home: Path):
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "KUWAI_ROOT": str(ROOT)}   # no XDG_*: the defaults under HOME
    return subprocess.run(["bash", str(ROOT / "bin/kuwai-migrate")], env=env, capture_output=True, text=True, timeout=30)


def test_share_folder_moves_and_merges_all_the_way_down():
    with tempfile.TemporaryDirectory() as d:
        home = Path(d)
        old, new = home / ".local/share/rice", home / ".local/share/kuwai"
        (old / "screensavers/src").mkdir(parents=True)
        (old / "screensavers/smoke-soft.mp4").write_text("film")
        (old / "screensavers/src/smoke-soft.mp4").write_text("source")
        (old / "clipboard/pins").mkdir(parents=True)
        (old / "clipboard/pins/1.png").write_text("pin")
        (old / "clipboard/times.tsv").write_text("t")
        (old / "alarms.json").write_text("[]")
        (old / "aur/1password").mkdir(parents=True)
        # the new side already has the install's own files and empty folders of the same names
        (new / "clipboard/pins").mkdir(parents=True)
        (new / "aur/grok-bot-bin").mkdir(parents=True)
        (new / "shell").mkdir()
        (new / "shell/shell.qml").write_text("keep")
        (new / "alarms.json").write_text("[new]")

        r = run(home)
        assert r.returncode == 0, r.stderr
        assert (new / "screensavers/smoke-soft.mp4").read_text() == "film"
        assert (new / "screensavers/src/smoke-soft.mp4").read_text() == "source"
        assert (new / "clipboard/pins/1.png").read_text() == "pin"      # a pins folder on both sides
        assert (new / "clipboard/times.tsv").read_text() == "t"
        assert (new / "aur/1password").is_dir() and (new / "aur/grok-bot-bin").is_dir()
        assert (new / "shell/shell.qml").read_text() == "keep"
        assert (new / "alarms.json").read_text() == "[new]"             # the newer file wins
        assert "kept" in r.stderr and "alarms.json" in r.stderr         # …and the old one says so
        assert (old / "alarms.json").exists()
        assert not old.is_symlink()                                     # still holds the kept file

        # Idempotent, and quiet about what it already said? (it repeats the one kept file: fine)
        assert run(home).returncode == 0
        assert (new / "screensavers/smoke-soft.mp4").read_text() == "film"


def test_clean_move_leaves_a_link_at_the_old_name():
    with tempfile.TemporaryDirectory() as d:
        home = Path(d)
        old, new = home / ".local/share/rice", home / ".local/share/kuwai"
        (old / "screensavers").mkdir(parents=True)
        (old / "screensavers/a.mp4").write_text("film")
        assert run(home).returncode == 0
        assert old.is_symlink() and os.readlink(old) == "kuwai"
        assert (new / "screensavers/a.mp4").read_text() == "film"
        assert (old / "screensavers/a.mp4").read_text() == "film"
        assert run(home).returncode == 0                                 # a second run changes nothing
