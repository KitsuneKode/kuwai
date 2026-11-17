"""kuwai-livewall playable: the file the shell should play for a live wallpaper.

A loop the GPU can't decode (H.264 in 4:4:4 colour, most of what the web
offers) made the shell's two players decode in software and hold the frames:
over a gigabyte in the shell with one 1440p loop. `playable` hands back a
4:2:0 copy, made once in the background; a file that is already fine is
handed back as it is.
"""
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "bin" / "kuwai-livewall"
pytestmark = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="needs ffmpeg and ffprobe")


def clip(path, pix_fmt):
    subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30",
                    "-t", "1", "-c:v", "libx264", "-pix_fmt", pix_fmt, str(path)], check=True)


def env_for(home):
    return {"PATH": os.environ["PATH"], "HOME": str(home), "XDG_STATE_HOME": str(home / ".local/state"),
            "XDG_CACHE_HOME": str(home / ".cache"), "XDG_RUNTIME_DIR": str(home / "run")}


def playable(home, file):
    r = subprocess.run([str(TOOL), "playable", str(file)], env=env_for(home), capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return Path(r.stdout.strip())


def pix_fmt(file):
    return subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=pix_fmt", "-of", "csv=p=0", str(file)],
                          capture_output=True, text=True).stdout.strip()


def wait_for_copy(home, seconds=30):
    cache = home / ".cache/kuwai/live"
    end = time.time() + seconds
    while time.time() < end:
        done = [p for p in cache.glob("*.mp4")] if cache.is_dir() else []
        if done and not list(cache.glob("*.lock")):
            return done[0]
        time.sleep(0.2)
    raise AssertionError("no copy was made")


def test_a_444_loop_plays_now_and_gets_a_420_copy(tmp_path):
    home = tmp_path / "home"
    (home / ".local/state/live-wallpaper").mkdir(parents=True)
    (home / "run").mkdir()
    src = tmp_path / "loop 444.mp4"                    # a space in the name: it is an argument, never pasted
    clip(src, "yuv444p")
    last = home / ".local/state/live-wallpaper/last"
    last.write_text(str(src))
    before = last.stat().st_mtime_ns

    assert playable(home, src) == src                  # the original, at once
    copy = wait_for_copy(home)
    assert pix_fmt(copy) == "yuv420p"
    assert last.read_text() == str(src)                # the pick is unchanged…
    assert last.stat().st_mtime_ns > before            # …and written again, so the shell asks once more
    assert playable(home, src) == copy                 # from now on, the copy
    assert not list((home / ".cache/kuwai/live").glob("*.part"))


def test_a_loop_that_is_already_fine_is_left_alone(tmp_path):
    home = tmp_path / "home"
    (home / "run").mkdir(parents=True)
    src = tmp_path / "loop420.mp4"
    clip(src, "yuv420p")
    assert playable(home, src) == src
    time.sleep(0.5)
    assert not (home / ".cache/kuwai/live").exists()


def test_a_changed_file_gets_a_new_copy(tmp_path):
    home = tmp_path / "home"
    (home / "run").mkdir(parents=True)
    src = tmp_path / "loop.mp4"
    clip(src, "yuv444p")
    playable(home, src)
    first = wait_for_copy(home)
    clip(tmp_path / "other.mp4", "yuv444p")
    os.replace(tmp_path / "other.mp4", src)
    os.utime(src, (time.time() + 5, time.time() + 5))
    assert playable(home, src) == src                  # not the old copy
    end = time.time() + 30
    while time.time() < end and len(list((home / ".cache/kuwai/live").glob("*.mp4"))) < 2:
        time.sleep(0.2)
    assert len(list((home / ".cache/kuwai/live").glob("*.mp4"))) == 2 and first.exists()


def test_what_cannot_be_read_is_played_as_it_is(tmp_path):
    home = tmp_path / "home"
    (home / "run").mkdir(parents=True)
    missing = tmp_path / "nope.mp4"
    assert playable(home, missing) == missing
    junk = tmp_path / "junk.mp4"
    junk.write_bytes(b"not a video")
    assert playable(home, junk) == junk
    assert not (home / ".cache/kuwai/live").exists()
