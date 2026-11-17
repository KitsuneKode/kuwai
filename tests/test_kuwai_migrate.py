"""bin/kuwai-migrate: ~/.local/share/rice (screensaver films, clipboard pins, alarms, reminders,
AUR recipes) moves into ~/.local/share/kuwai-data. Not ~/.local/share/kuwai: that is the stable copy
of the repo, and an earlier version that moved the data there left it in a git checkout as untracked
files (the next promote refused to run). That version's leftovers are moved out again."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(home: Path):
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "KUWAI_ROOT": str(ROOT)}   # no XDG_*: the defaults under HOME
    return subprocess.run(["bash", str(ROOT / "bin/kuwai-migrate")], env=env, capture_output=True, text=True, timeout=30)


def test_share_folder_moves_to_kuwai_data_and_merges_all_the_way_down():
    with tempfile.TemporaryDirectory() as d:
        home = Path(d)
        old, new = home / ".local/share/rice", home / ".local/share/kuwai-data"
        stable = home / ".local/share/kuwai"
        (old / "screensavers/src").mkdir(parents=True)
        (old / "screensavers/smoke-soft.mp4").write_text("film")
        (old / "screensavers/src/smoke-soft.mp4").write_text("source")
        (old / "clipboard/pins").mkdir(parents=True)
        (old / "clipboard/pins/1.png").write_text("pin")
        (old / "clipboard/times.tsv").write_text("t")
        (old / "alarms.json").write_text("[]")
        (old / "aur/1password").mkdir(parents=True)
        # the new side already has folders of the same names, and a newer file
        (new / "clipboard/pins").mkdir(parents=True)
        (new / "aur/grok-bot-bin").mkdir(parents=True)
        (new / "alarms.json").write_text("[new]")
        (stable / "shell").mkdir(parents=True)
        (stable / "shell/shell.qml").write_text("keep")

        r = run(home)
        assert r.returncode == 0, r.stderr
        assert (new / "screensavers/smoke-soft.mp4").read_text() == "film"
        assert (new / "screensavers/src/smoke-soft.mp4").read_text() == "source"
        assert (new / "clipboard/pins/1.png").read_text() == "pin"      # a pins folder on both sides
        assert (new / "clipboard/times.tsv").read_text() == "t"
        assert (new / "aur/1password").is_dir() and (new / "aur/grok-bot-bin").is_dir()
        assert (new / "alarms.json").read_text() == "[new]"             # the newer file wins
        assert "kept" in r.stderr and "alarms.json" in r.stderr         # …and the old one says so
        assert (old / "alarms.json").exists() and not old.is_symlink()  # still holds the kept file
        assert sorted(p.name for p in stable.iterdir()) == ["shell"]    # the stable copy is never written
        assert run(home).returncode == 0
        assert (new / "screensavers/smoke-soft.mp4").read_text() == "film"


def test_clean_move_leaves_a_link_at_the_old_name():
    with tempfile.TemporaryDirectory() as d:
        home = Path(d)
        old, new = home / ".local/share/rice", home / ".local/share/kuwai-data"
        (old / "screensavers").mkdir(parents=True)
        (old / "screensavers/a.mp4").write_text("film")
        assert run(home).returncode == 0
        assert old.is_symlink() and os.readlink(old) == "kuwai-data"
        assert (new / "screensavers/a.mp4").read_text() == "film"
        assert (old / "screensavers/a.mp4").read_text() == "film"
        assert run(home).returncode == 0                                 # a second run changes nothing


def test_data_an_earlier_version_left_in_the_stable_copy_moves_out():
    with tempfile.TemporaryDirectory() as d:
        home = Path(d)
        share = home / ".local/share"
        stable, data = share / "kuwai", share / "kuwai-data"
        stable.mkdir(parents=True)
        g = {"cwd": stable, "capture_output": True, "check": True}
        subprocess.run(["git", "init", "-q"], **g)
        (stable / "shell").mkdir()
        (stable / "shell/shell.qml").write_text("tracked")
        (stable / "screensavers").mkdir()
        (stable / "screensavers/README").write_text("a tracked file of the same name stays")
        subprocess.run(["git", "add", "."], **g)
        subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", "commit", "-qm", "x"], **g)
        # what the earlier migration put there, untracked
        (stable / "alarms.json").write_text("[mine]")
        (stable / "clipboard/pins").mkdir(parents=True)
        (stable / "clipboard/pins/1.png").write_text("pin")
        (share / "rice").symlink_to("kuwai")

        r = run(home)
        assert r.returncode == 0, r.stderr
        assert (data / "alarms.json").read_text() == "[mine]"
        assert (data / "clipboard/pins/1.png").read_text() == "pin"
        assert not (stable / "alarms.json").exists() and not (stable / "clipboard").exists()
        assert (stable / "screensavers/README").exists()                 # tracked by git: not data, stays
        assert (stable / "shell/shell.qml").read_text() == "tracked"
        assert os.readlink(share / "rice") == "kuwai-data"
        status = subprocess.run(["git", "status", "--porcelain"], cwd=stable, capture_output=True, text=True).stdout
        assert status == ""                                              # the checkout is clean again
