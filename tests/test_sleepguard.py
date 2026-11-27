"""kuwai-sleepguard: sleep waits for a confirmed lock, never past logind's deadline, and the guard comes back on waking."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(tmp_path, lock_ok_after, events):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    log = tmp_path / "log"
    def stub(name, body):
        (bin_ / name).write_text("#!/bin/bash\n" + body)
        (bin_ / name).chmod(0o755)
    stub("systemd-inhibit", f'echo hold >> {log}\ntrap "echo release >> {log}; kill $s; exit 0" TERM\nsleep 1000 >/dev/null 2>&1 & s=$!; wait\n')
    stub("busctl", 'echo "t 2000000"\n')
    stub("gdbus", "".join(f'sleep {d}; echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep ({v},)"\n' for d, v in events) + "sleep 0.5\n")
    stub("kuwai", f'n=$(( $(cat {tmp_path}/n 2>/dev/null || echo 0) + 1 )); echo $n > {tmp_path}/n; echo "lock $n" >> {log}; [ $n -ge {lock_ok_after} ]\n')
    env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}")
    p = subprocess.run([str(ROOT / "bin/kuwai-sleepguard"), str(bin_ / "kuwai")], env=env, capture_output=True, text=True, timeout=20)
    return p.returncode, log.read_text().split("\n")[:-1]


def test_released_only_after_the_lock_is_confirmed_then_held_again(tmp_path):
    code, log = run(tmp_path, 3, [(0.3, "true"), (0.3, "false")])
    assert log[:5] == ["hold", "lock 1", "lock 2", "lock 3", "release"]
    assert log[5] == "hold"
    assert log[-1] == "release"
    assert code == 1


def test_a_lock_that_never_comes_still_lets_sleep_go_by_the_deadline(tmp_path):
    code, log = run(tmp_path, 999, [(0.3, "true")])
    assert log[0] == "hold"
    assert log.count("release") >= 1
    assert sum(1 for l in log if l.startswith("lock")) >= 3
    assert log.index("release") > log.index("lock 3")
