"""bin/kuwai-livewall out-play|out-pause|out-stop: one mpvpaper per screen, driven by the shell.

Stand-ins for mpvpaper and socat record what they were given; nothing is drawn."""
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-livewall"


def setup(tmp: Path):
    fake = tmp / "fakebin"
    fake.mkdir()
    log = tmp / "log"
    # Named mpvpaper so /proc/PID/comm says so; it stays up like the real one.
    (fake / "mpvpaper").write_text(f'#!/bin/sh\necho "mpvpaper MPV_HOME=$MPV_HOME $*" >> "{log}"\ntrap \'kill $! 2>/dev/null; exit 0\' TERM\nsleep 30 & wait\n')
    (fake / "socat").write_text(f'#!/bin/sh\necho "socat $(cat)" >> "{log}"\n')
    for f in fake.iterdir():
        f.chmod(0o755)
    run_dir = tmp / "run"
    run_dir.mkdir(mode=0o700)
    env = {**os.environ, "PATH": f"{fake}:/usr/bin:/bin", "XDG_RUNTIME_DIR": str(run_dir),
           "XDG_STATE_HOME": str(tmp / "state"), "HOME": str(tmp)}
    return env, log, run_dir / "kuwai"


def lw(env, *args):
    return subprocess.run([str(BIN), *args], env=env, capture_output=True, text=True, timeout=15)


def wait_for(path: Path, text: str, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if path.exists() and text in path.read_text():
            return True
        time.sleep(0.05)
    return False


def test_can_play_needs_mpvpaper(tmp_path):
    env, _, _ = setup(tmp_path)
    assert lw(env, "can-play").returncode == 0
    (tmp_path / "fakebin" / "mpvpaper").unlink()
    # Only the stand-ins on PATH: a real mpvpaper in /usr/bin must not answer for the missing one.
    bare = {**env, "PATH": str(tmp_path / "fakebin")}
    r = subprocess.run(["/usr/bin/bash", str(BIN), "can-play"], env=bare, capture_output=True, text=True, timeout=15)
    assert r.returncode != 0


def test_play_starts_one_player_per_screen_then_stop_ends_it(tmp_path):
    env, log, sock = setup(tmp_path)
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    assert wait_for(log, "mpvpaper")
    line = log.read_text()
    assert f"input-ipc-server={sock}/mpvpaper-DP-3.sock" in line and "hwdec=auto" in line and "no-audio" in line
    assert f"DP-3 {video}" in line and " pause " not in line + " "
    pid = int((sock / "mpvpaper-DP-3.pid").read_text())
    assert Path(f"/proc/{pid}/comm").read_text().strip() == "mpvpaper"
    # The same file again: the running player is reused (no second mpvpaper).
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    time.sleep(0.3)
    assert log.read_text().count("mpvpaper ") == 1
    assert lw(env, "out-stop", "DP-3").returncode == 0
    time.sleep(0.3)
    assert not Path(f"/proc/{pid}").exists() or Path(f"/proc/{pid}/stat").read_text().split()[2] == "Z"
    assert not (sock / "mpvpaper-DP-3.pid").exists()


def test_a_covered_screen_starts_paused(tmp_path):
    env, log, sock = setup(tmp_path)
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "eDP-1", str(video), "paused").returncode == 0
    assert wait_for(log, "mpvpaper")
    assert " pause eDP-1 " in log.read_text()
    lw(env, "out-stop", "eDP-1")


def test_pause_goes_to_that_screens_socket_only(tmp_path):
    env, log, sock = setup(tmp_path)
    sock.mkdir(mode=0o700)
    # a socket that exists (out_cmd only writes to a live socket)
    import socket
    s = socket.socket(socket.AF_UNIX)
    s.bind(str(sock / "mpvpaper-DP-3.sock"))
    try:
        assert lw(env, "out-pause", "DP-3", "true").returncode == 0
        assert '"pause", true' in log.read_text()
        assert lw(env, "out-pause", "eDP-1", "true").returncode != 0      # no player there: nothing sent
        assert log.read_text().count("socat") == 1
    finally:
        s.close()


def test_the_wallpaper_mpv_never_reads_your_film_config(tmp_path):
    # Measured on the wire: mpvpaper's libmpv loaded ~/.config/mpv (config yes, scripts,
    # debanding, ewa_lanczos, a 256 MiB cache), per screen, for a loop behind the windows.
    env, log, sock = setup(tmp_path)
    films = tmp_path / ".config/mpv"
    films.mkdir(parents=True)
    (films / "mpv.conf").write_text("profile=high-quality\ndeband=yes\n")
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    assert wait_for(log, "mpvpaper")
    home = sock / "mpvpaper-home"
    assert f"MPV_HOME={home} " in log.read_text()
    conf = (home / "mpv.conf").read_text()
    for line in ("profile=fast", "load-scripts=no", "cache=no"):
        assert line in conf.splitlines()
    assert "deband=yes" not in conf
    assert oct(home.stat().st_mode & 0o777) == "0o700"
    before = (home / "mpv.conf").stat().st_mtime_ns
    assert lw(env, "out-play", "eDP-1", str(video)).returncode == 0   # the same file: not rewritten
    assert wait_for(log, "eDP-1")
    assert (home / "mpv.conf").stat().st_mtime_ns == before
    lw(env, "out-stop", "DP-3"); lw(env, "out-stop", "eDP-1")
