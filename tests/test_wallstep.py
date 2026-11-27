"""kuwai-wallstep: a key steps wallpapers, live wallpapers and screensaver styles, wrapping round."""
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def setup(tmp_path, themes_json, live_names, last=""):
    bin_ = tmp_path / "kuwai" / "bin"
    bin_.mkdir(parents=True)
    shutil.copy(ROOT / "bin/kuwai-wallstep", bin_ / "kuwai-wallstep")
    log = tmp_path / "log"
    stub = lambda name, body: ((bin_ / name).write_text("#!/bin/sh\n" + body), (bin_ / name).chmod(0o755))
    stub("kuwai-themes", f"echo '{json.dumps(themes_json)}'\n")
    stub("kuwai-wall", f'[ "$1" = list ] && printf "%s\\n" {" ".join(live_names)}; echo "wall $*" >> {log}\n')
    stub("kuwai", f'[ "$1" = get ] && cat {tmp_path}/style 2>/dev/null; [ "$1" = set ] && printf %s "$3" > {tmp_path}/style; true\n')
    stub("qs", f'echo "qs $*" >> {log}\n')
    stub("kuwai-look", "true\n")
    home = tmp_path / "home"
    (home / ".local/state/live-wallpaper").mkdir(parents=True)
    (home / ".local/state/live-wallpaper/last").write_text(last)
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_}:{os.environ['PATH']}", XDG_STATE_HOME=str(home / ".local/state"))
    return bin_, log, env


def test_wallpapers_step_and_wrap(tmp_path):
    walls = [{"path": f"/w/{n}.jpg", "current": n == "c"} for n in "abc"]
    bin_, log, env = setup(tmp_path, {"hyde": True, "wallpapers": walls}, [])
    assert subprocess.run([str(bin_ / "kuwai-wallstep"), "still", "next"], env=env, timeout=30).returncode == 0
    assert "wallfx play /w/a.jpg" in log.read_text(), "after the last comes the first"
    subprocess.run([str(bin_ / "kuwai-wallstep"), "still", "prev"], env=env, timeout=30)
    assert "wallfx play /w/b.jpg" in log.read_text()


def test_live_and_saver_step(tmp_path):
    bin_, log, env = setup(tmp_path, {"hyde": False, "wallpapers": []}, ["1-a.mp4", "2-b.mp4"], last="/lib/2-b.mp4")
    subprocess.run([str(bin_ / "kuwai-wallstep"), "live", "next"], env=env, timeout=30)
    assert "qs ipc -p" in log.read_text() and "call wallfx live 1-a.mp4" in log.read_text(), "the shell plays the change into it"
    assert "wall play" not in log.read_text()
    (tmp_path / "style").write_text("dusk")
    subprocess.run([str(bin_ / "kuwai-wallstep"), "saver", "prev"], env=env, timeout=30)
    assert (tmp_path / "style").read_text() == "still"
    assert "moment say Screensaver: Still" in log.read_text()
