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
