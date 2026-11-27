"""Regression tests for bin/kuwai-crash-poll JSON parsing, UID filtering, and NDJSON output."""
import json
import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-crash-poll"


def make_fake_coredumpctl(bin_dir, entries):
    script = bin_dir / "coredumpctl"
    payload = json.dumps(entries)
    script.write_text(
        "#!/usr/bin/env python3\n"
        "import json, sys\n"
        "args = sys.argv[1:]\n"
        "if '--user' in args:\n"
        "    sys.stderr.write('coredumpctl: unrecognized option --user\\n')\n"
        "    sys.exit(1)\n"
        "if args and args[0] == 'list':\n"
        f"    print({payload!r})\n"
        "elif args and args[0] == 'info':\n"
        "    pid = args[1]\n"
        "    for i in range(1, 26):\n"
        "        print(f'line {i} pid={pid}')\n"
    )
    script.chmod(script.stat().st_mode | stat.S_IEXEC)


def test_crash_poll_filters_uid_emits_ndjson_and_dedupes(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    uid = os.getuid()
    make_fake_coredumpctl(
        fake_bin,
        [
            {"time": 1001, "pid": 111, "uid": uid, "gid": uid, "sig": 11, "exe": "/usr/bin/app1"},
            {"time": 1002, "pid": 222, "uid": uid + 1, "gid": uid + 1, "sig": 6, "exe": "/usr/bin/other"},
            {"time": 1003, "pid": 333, "uid": uid, "gid": uid, "sig": 6, "exe": "/usr/bin/app2"},
        ],
    )
    env = {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "XDG_STATE_HOME": str(tmp_path / "state"),
    }
    first = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, check=True)
    lines = [l for l in first.stdout.splitlines() if l.strip()]
    assert len(lines) == 2
    rows = [json.loads(l) for l in lines]
    assert [r["exe"] for r in rows] == ["/usr/bin/app1", "/usr/bin/app2"]
    assert all("pid=" in r["brief"] for r in rows)

    second = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, check=True)
    assert second.stdout.strip() == ""


def test_a_crash_from_a_session_that_has_ended_is_not_reported(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    uid = os.getuid()
    (fake_bin / "coredumpctl").write_text(
        "#!/usr/bin/env python3\nimport json, sys\na = sys.argv[1:]\n"
        f"if a[0] == 'list': print(json.dumps([{{'time': 1, 'pid': 808, 'uid': {uid}, 'sig': 6, 'exe': '/usr/bin/Xwayland'}},"
        f" {{'time': 2, 'pid': 909, 'uid': {uid}, 'sig': 11, 'exe': '/usr/bin/qs'}}]))\n"
        "else: print('  Session: ' + ('7' if a[1] == '808' else '9'))\n")
    (fake_bin / "loginctl").write_text("#!/bin/sh\n[ \"$2\" = 9 ]\n")
    for f in ("coredumpctl", "loginctl"):
        (fake_bin / f).chmod(0o755)
    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "XDG_STATE_HOME": str(tmp_path / "state")}
    out = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, check=True).stdout
    rows = [json.loads(l) for l in out.splitlines() if l.strip()]
    assert [r["exe"] for r in rows] == ["/usr/bin/qs"], "Xwayland ending with a logout is not news at the next login"
    again = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, check=True).stdout
    assert again.strip() == ""


def test_a_crash_inside_a_container_is_not_reported(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    uid = os.getuid()
    (fake_bin / "coredumpctl").write_text(
        "#!/usr/bin/env python3\nimport json, sys\na = sys.argv[1:]\n"
        f"if a[0] == 'list': print(json.dumps([{{'time': 1, 'pid': 501, 'uid': {uid}, 'sig': 6, 'exe': '/usr/bin/Hyprland'}},"
        f" {{'time': 2, 'pid': 502, 'uid': {uid}, 'sig': 11, 'exe': '/usr/bin/qs'}}]))\n"
        "else: print('  Unit: ' + ('docker-dda9bdc3.scope' if a[1] == '501' else 'user@1000.service'))\n")
    (fake_bin / "coredumpctl").chmod(0o755)
    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "XDG_STATE_HOME": str(tmp_path / "state")}
    out = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, check=True).stdout
    rows = [json.loads(l) for l in out.splitlines() if l.strip()]
    assert [r["exe"] for r in rows] == ["/usr/bin/qs"], "a test container's Hyprland is not your desktop's"
