"""bin/kuwai-livewall out-play|out-pause|out-stop|freeze: one mpvpaper per screen, serialized and verified over IPC."""
import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-livewall"

FAKE_MPVPAPER = '''#!/usr/bin/python3
import json
import os
import re
import signal
import socket
import sys
import time
from pathlib import Path

log = Path(os.environ["FAKE_MPV_LOG"])
args = sys.argv[1:]
with log.open("a") as f:
    f.write(f"mpvpaper MPV_HOME={os.environ.get('MPV_HOME', '')} {' '.join(args)}\\n")

opts = args[1] if len(args) >= 2 and args[0] == "-o" else ""
m = re.search(r"input-ipc-server=(\\S+)", opts)
sock_path = m.group(1) if m else ""

delay = float(os.environ.get("FAKE_MPV_DELAY", "0"))
if delay > 0:
    time.sleep(delay)

mode = os.environ.get("FAKE_MPV_MODE", "play")
state = {
    "pause": False,
    "idle-active": mode in ("idle", "stall"),
    "core-idle": mode in ("idle", "stall", "buffering"),
    "playback-time": None if mode in ("idle", "stall", "no-time") else 0.25,
    "file": args[-1] if args else "",
}

def stop(_sig, _frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, stop)

if mode == "no-sock" or not sock_path:
    time.sleep(30)
    sys.exit(0)

if os.path.exists(sock_path):
    os.unlink(sock_path)

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(sock_path)
srv.listen(8)
srv.settimeout(0.5)
end = time.time() + 30

while time.time() < end:
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        continue
    with conn:
        buf = b""
        conn.settimeout(0.5)
        try:
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\\n" in buf:
                    raw, buf = buf.split(b"\\n", 1)
                    if not raw.strip():
                        continue
                    with log.open("a") as f:
                        f.write(f"ipc {raw.decode('utf-8', 'replace')}\\n")
                    req = json.loads(raw.decode("utf-8"))
                    cmd = req.get("command") or []
                    rid = req.get("request_id")
                    op = cmd[0] if cmd else ""
                    if mode == "hang":
                        time.sleep(2)
                        continue
                    reply = {"error": "success"}
                    if rid is not None:
                        reply["request_id"] = rid
                    if op == "get_property" and len(cmd) >= 2:
                        prop = cmd[1]
                        if prop == "playback-time" and state[prop] is None:
                            reply["error"] = "property unavailable"
                        elif prop in state:
                            reply["data"] = state[prop]
                        else:
                            reply["error"] = "property unavailable"
                    elif op == "set_property" and len(cmd) >= 3:
                        if cmd[1] == "pause":
                            state["pause"] = bool(cmd[2])
                            if mode == "play":
                                state["core-idle"] = state["pause"]
                    elif op == "loadfile" and len(cmd) >= 2:
                        state["file"] = cmd[1]
                        if mode == "play":
                            state["idle-active"] = False
                            state["playback-time"] = 0.1
                    elif op == "screenshot-to-file" and len(cmd) >= 2:
                        Path(cmd[1]).write_bytes(b"\\xff\\xd8\\xff\\xd9")
                    else:
                        reply["error"] = "invalid parameter"
                    conn.sendall((json.dumps(reply) + "\\n").encode("utf-8"))
        except Exception:
            pass
'''


def setup(tmp: Path, **extra_env):
    fake = tmp / "fakebin"
    fake.mkdir(exist_ok=True)
    log = tmp / "log"
    mpv = fake / "mpvpaper"
    mpv.write_text(FAKE_MPVPAPER)
    mpv.chmod(0o755)
    run_dir = tmp / "run"
    run_dir.mkdir(mode=0o700, exist_ok=True)
    env = {
        **os.environ,
        "PATH": f"{fake}:/usr/bin:/bin",
        "XDG_RUNTIME_DIR": str(run_dir),
        "XDG_STATE_HOME": str(tmp / "state"),
        "HOME": str(tmp),
        "FAKE_MPV_LOG": str(log),
        "KUWAI_LIVEWALL_WAIT_MS": "1500",
        **extra_env,
    }
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


def proc_dead(pid: int) -> bool:
    p = Path(f"/proc/{pid}")
    return not p.exists() or (p / "stat").read_text().split()[2] == "Z"


def test_can_play_needs_mpvpaper(tmp_path):
    env, _, _ = setup(tmp_path)
    assert lw(env, "can-play").returncode == 0
    (tmp_path / "fakebin" / "mpvpaper").unlink()
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
    assert f"input-ipc-server={sock}/mpvpaper-DP-3.sock" in line and "no-audio" in line
    assert ("hwdec=vaapi-copy" in line or "hwdec=nvdec-copy" in line or "hwdec=no" in line) and "hwdec=auto" not in line
    assert f"DP-3 {video}" in line and " pause " not in line + " "
    pid = int((sock / "mpvpaper-DP-3.pid").read_text())
    assert Path(f"/proc/{pid}/comm").read_text().strip() == "mpvpaper"
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    assert log.read_text().count("mpvpaper ") == 1
    assert lw(env, "out-stop", "DP-3").returncode == 0
    time.sleep(0.2)
    assert proc_dead(pid)
    assert not (sock / "mpvpaper-DP-3.pid").exists()


def test_a_covered_screen_does_not_spawn_a_cold_player(tmp_path):
    env, log, sock = setup(tmp_path)
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "eDP-1", str(video), "paused").returncode == 0
    time.sleep(0.2)
    assert not log.exists()
    assert not (sock / "mpvpaper-eDP-1.pid").exists()
    assert lw(env, "out-play", "eDP-1", str(video)).returncode == 0
    r = lw(env, "out-play", "eDP-1", str(video), "paused")
    assert r.returncode == 0
    assert '"pause", true' in log.read_text() or '"pause",true' in log.read_text()
    frozen = sock / "frozen-eDP-1.jpg"
    assert frozen.is_file() and frozen.stat().st_size > 0
    assert f"eDP-1 {frozen}" in r.stdout
    lw(env, "out-stop", "eDP-1")


def test_pause_goes_to_that_screens_socket_only(tmp_path):
    env, log, sock = setup(tmp_path)
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    r = lw(env, "out-pause", "DP-3", "true")
    assert r.returncode == 0
    assert '"screenshot-to-file"' in log.read_text()
    assert (sock / "frozen-DP-3.jpg").is_file()
    assert lw(env, "out-pause", "eDP-1", "true").returncode != 0
    lw(env, "out-stop", "DP-3")


def test_the_wallpaper_mpv_never_reads_your_film_config(tmp_path):
    env, log, sock = setup(tmp_path)
    films = tmp_path / ".config/mpv"
    films.mkdir(parents=True)
    (films / "mpv.conf").write_text("profile=high-quality\ndeband=yes\n")
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    home = sock / "mpvpaper-home"
    assert f"MPV_HOME={home} " in log.read_text()
    conf = (home / "mpv.conf").read_text()
    for line in ("profile=fast", "load-scripts=no", "cache=no"):
        assert line in conf.splitlines()
    assert "deband=yes" not in conf
    assert oct(home.stat().st_mode & 0o777) == "0o700"
    before = (home / "mpv.conf").stat().st_mtime_ns
    assert lw(env, "out-play", "eDP-1", str(video)).returncode == 0
    assert (home / "mpv.conf").stat().st_mtime_ns == before
    lw(env, "out-stop", "DP-3")
    lw(env, "out-stop", "eDP-1")


def test_the_shell_taking_over_ends_a_fallback_player(tmp_path):
    env, log, sock = setup(tmp_path)
    fake = tmp_path / "fakebin"
    for name, body in (("qs", "exit 1"), ("pgrep", "exit 1"), ("pkill", "exit 0"), ("notify-send", "exit 0")):
        (fake / name).write_text(f"#!/bin/sh\n{body}\n")
        (fake / name).chmod(0o755)
    video = tmp_path / "loop.mp4"
    video.write_text("v")
    assert lw(env, "play", str(video)).returncode == 0
    assert wait_for(log, "mpvpaper")
    fallback = int((sock / "mpvpaper-ipc.pid").read_text())
    assert Path(f"/proc/{fallback}/comm").read_text().strip() == "mpvpaper"
    assert lw(env, "out-play", "DP-3", str(video)).returncode == 0
    time.sleep(0.3)
    assert proc_dead(fallback)
    assert not (sock / "mpvpaper-ipc.pid").exists()
    assert (sock / "mpvpaper-DP-3.pid").exists()
    lw(env, "out-stop", "DP-3")


def test_mpvpaper_that_starts_but_never_plays_fails_and_cleans_up(tmp_path):
    for mode in ("stall", "buffering", "no-time", "no-sock"):
        sub = tmp_path / mode
        sub.mkdir()
        env, log, sock = setup(sub, FAKE_MPV_MODE=mode, KUWAI_LIVEWALL_WAIT_MS="400")
        video = sub / "broken.mp4"
        video.write_text("v")
        r = lw(env, "out-play", "DP-3", str(video))
        assert r.returncode != 0, f"mode {mode} should fail when mpv never plays"
        assert not (sock / "mpvpaper-DP-3.pid").exists()
        assert not (sock / "mpvpaper-DP-3.sock").exists()


def test_two_quick_changes_on_one_output_serialize_cleanly(tmp_path):
    env, log, sock = setup(tmp_path, FAKE_MPV_DELAY="0.25", KUWAI_LIVEWALL_WAIT_MS="3000")
    v1 = tmp_path / "one.mp4"
    v2 = tmp_path / "two.mp4"
    v1.write_text("1")
    v2.write_text("2")
    p1 = subprocess.Popen([str(BIN), "out-play", "DP-3", str(v1)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(0.05)
    p2 = subprocess.Popen([str(BIN), "out-play", "DP-3", str(v2)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert p1.wait(timeout=15) == 0
    assert p2.wait(timeout=15) == 0
    assert log.read_text().count("mpvpaper ") == 1, "second change serialized onto the first player via loadfile"
    assert (sock / "mpvpaper-DP-3.file").read_text() == str(v2)
    pid = int((sock / "mpvpaper-DP-3.pid").read_text())
    assert not proc_dead(pid)
    lock_check = subprocess.run(["flock", "-n", str(sock / "mpvpaper-DP-3.lock"), "true"], timeout=5)
    assert lock_check.returncode == 0, "spawned mpvpaper must not inherit the per-output lock fd"
    assert lw(env, "out-stop", "DP-3").returncode == 0
    time.sleep(0.2)
    assert proc_dead(pid)
