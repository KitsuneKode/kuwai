"""The brightness controller is the session's copy of the code.

It detaches and outlives whatever started it: started once from a working
checkout, it served the installed desktop's brightness keys with that
checkout's code for 46 hours. The client now replaces a controller that is
another copy (or this copy before it changed), but only when the client is
the session's own copy; and it only ever signals a process that is the
controller.
"""
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("brightness_client", REPO / "lib/brightness/brightness-client.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)


def test_code_id_follows_the_file(tmp_path):
    f = tmp_path / "brightness.py"
    f.write_text("a = 1\n")
    one = bc.code_id(f)
    f.write_text("a = 2\n")
    two = bc.code_id(f)
    assert one["path"] == two["path"] == str(f.resolve()) and one["sha"] != two["sha"]
    assert bc.code_id(tmp_path / "missing.py")["sha"] == ""


def test_only_the_sessions_copy_may_replace(tmp_path):
    stable, dev = tmp_path / "stable", tmp_path / "dev"
    for d in (stable, dev):
        (d / "lib/brightness").mkdir(parents=True)
        (d / "lib/brightness/brightness.py").write_text("x\n")
    assert bc.session_copy(stable / "lib/brightness/brightness.py", str(stable)) is True
    assert bc.session_copy(dev / "lib/brightness/brightness.py", str(stable)) is False
    assert bc.session_copy(stable / "lib/brightness/brightness.py", "") is False      # no session root known: never replace


def test_stale_when_another_copy_changed_code_or_no_owner(tmp_path):
    mine = {"path": "/s/brightness.py", "sha": "abc"}
    assert bc.stale_daemon(tmp_path, mine) is True                                   # a controller from before it said
    (tmp_path / "owner").write_text(json.dumps(mine))
    assert bc.stale_daemon(tmp_path, mine) is False
    (tmp_path / "owner").write_text(json.dumps({"path": "/dev/brightness.py", "sha": "abc"}))
    assert bc.stale_daemon(tmp_path, mine) is True                                   # another checkout
    (tmp_path / "owner").write_text(json.dumps({"path": "/s/brightness.py", "sha": "old"}))
    assert bc.stale_daemon(tmp_path, mine) is True                                   # the same file before a promote
    (tmp_path / "owner").write_text("not json")
    assert bc.stale_daemon(tmp_path, mine) is True


def test_stop_only_signals_the_controller(tmp_path):
    # A bystander of yours whose pid ends up in the file is never signalled.
    bystander = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        (tmp_path / "pid").write_text(str(bystander.pid))
        assert bc.stop_daemon(tmp_path) is False
        time.sleep(0.1)
        assert bystander.poll() is None
    finally:
        bystander.kill()
    # The controller's own command line is.
    script = tmp_path / "brightness.py"
    script.write_text("import time\ntime.sleep(30)\n")
    daemon = subprocess.Popen([sys.executable, str(script), "--serve"])
    try:
        cmdline = Path(f"/proc/{daemon.pid}/cmdline")
        deadline = time.monotonic() + 5
        while b"--serve" not in cmdline.read_bytes() and time.monotonic() < deadline:
            time.sleep(0.01)
        (tmp_path / "pid").write_text(str(daemon.pid))
        assert bc.stop_daemon(tmp_path) is True
        assert daemon.wait(timeout=5) is not None
    finally:
        daemon.kill()
    for junk in ("", "abc", "1", "0", "-5"):
        (tmp_path / "pid").write_text(junk)
        assert bc.stop_daemon(tmp_path) is False
    (tmp_path / "pid").unlink()
    assert bc.stop_daemon(tmp_path) is False


def test_the_controller_says_which_code_it_is():
    text = (REPO / "lib/brightness/brightness.py").read_text()
    assert "(runtime / 'owner').write_text" in text and "(runtime / 'owner').unlink" in text
