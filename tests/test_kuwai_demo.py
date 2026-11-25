"""bin/kuwai-demo: the island tour plays its story through the shell's test hooks and always
puts the real agents back, at the end or on Ctrl+C. Driven against a stand-in `qs` that records
each call, so no shell, pane or hook is touched."""
import json
import os
import signal
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def stage(tmp_path, locked=False):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    log = tmp_path / "calls.log"
    (bin_ / "qs").write_text(f"""#!/bin/sh
[ "$5" = lock ] && {{ echo {'locked' if locked else 'unlocked'}; exit 0; }}
printf '%s\\n' "$*" >> {log}
""")
    (bin_ / "hyprctl").write_text('#!/bin/sh\necho \'[{"name": "DP-3", "focused": true}]\'\n')
    for f in bin_.iterdir():
        f.chmod(0o755)
    env = {**os.environ, "PATH": f"{bin_}:{os.environ['PATH']}", "KUWAI_SHELL": str(tmp_path / "shell"), "KUWAI_DEMO_PACE": "0.01"}
    return env, log


def calls(log):
    return [l for l in log.read_text().splitlines() if l.startswith("ipc -p")]


def test_the_tour_tells_its_story_and_cleans_up(tmp_path):
    env, log = stage(tmp_path)
    r = subprocess.run([str(ROOT / "bin/kuwai-demo")], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    c = calls(log)
    tests = [l.split(" call test ", 1)[1] for l in c if " call test " in l]
    assert tests[0] == "clear" and tests[-1] == "clear", "it starts clean and always puts the real feed back"
    feeds = [json.loads(t.split(" ", 1)[1]) for t in tests if t.startswith("feed ")]
    states = [[a["state"] for a in f["agents"]] for f in feeds]
    assert states[0] == ["working"] * 3
    assert "done" in states[1] and "waiting" in states[2] and "limited" in states[-2] and states[-1] == ["done"] * 3
    asking = next(a for f in feeds for a in f["agents"] if a["state"] == "waiting")
    assert asking["question"].startswith("Allow Bash:") and asking["agent"] == "claude"
    limited = next(a for f in feeds for a in f["agents"] if a["state"] == "limited")
    assert limited["limit_reset"] > time.time() and limited["account"] == "personal"
    assert any(t.startswith("demoTimer 90") for t in tests), "the timer is the demo's, so clear cancels it"
    assert any(t.startswith("peek DP-3") for t in tests), "the notification peeks on the screen you're on"
    assert "Everything done." in r.stdout


def test_ctrl_c_still_puts_everything_back(tmp_path):
    env, log = stage(tmp_path)
    env["KUWAI_DEMO_PACE"] = "1"
    p = subprocess.Popen([str(ROOT / "bin/kuwai-demo")], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(1.5)
    p.send_signal(signal.SIGINT)
    p.wait(timeout=10)
    tests = [l.split(" call test ", 1)[1] for l in calls(log) if " call test " in l]
    assert tests[-1] == "clear"


def test_it_waits_for_the_lock_and_for_a_shell(tmp_path):
    env, log = stage(tmp_path, locked=True)
    r = subprocess.run([str(ROOT / "bin/kuwai-demo")], env=env, capture_output=True, text=True, timeout=30)
    assert r.returncode == 1 and "Unlock" in r.stderr
    assert not any(" call test feed" in l for l in calls(log))
