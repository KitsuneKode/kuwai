"""bin/kuwai-hotwatch: the shell busy for two minutes is caught once, with which thread was busy.

On 27 Nov the shell sat at 99 % for three hours and stopped answering notifications for
155 s; nothing recorded what it was doing. The watcher samples /proc once a minute."""
import importlib.machinery
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HZ = 100


def load():
    loader = importlib.machinery.SourceFileLoader("kuwai_hotwatch", str(ROOT / "bin/kuwai-hotwatch"))
    spec = importlib.util.spec_from_loader("kuwai_hotwatch", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


hw = load()


def stat_line(pid, name, ticks, start=777):
    fields = ["S"] + ["0"] * 10 + [str(ticks), "0"] + ["0"] * 6 + [str(start)] + ["0"] * 20
    return f"{pid} ({name}) " + " ".join(fields) + "\n"


def fake_proc(root, pid, threads, start=777):
    p = root / str(pid)
    (p / "task").mkdir(parents=True, exist_ok=True)
    (p / "stat").write_text(stat_line(pid, "qs", sum(t for _, t in threads.values()), start))
    (p / "smaps_rollup").write_text("Rss:  400000 kB\nPss:  380000 kB\nPss_Anon: 200000 kB\nSwap: 0 kB\n")
    for tid, (name, ticks) in threads.items():
        t = p / "task" / str(tid)
        t.mkdir(exist_ok=True)
        (t / "stat").write_text(stat_line(tid, name, ticks, start))
        (t / "comm").write_text(name + "\n")
        (t / "wchan").write_text("futex_wait\n")


def run_steps(tmp_path, samples, pid=42, start=777):
    proc, state, out = tmp_path / "proc", tmp_path / "run/hotwatch.json", tmp_path / "hot"
    told, made = [], []
    for i, threads in enumerate(samples):
        fake_proc(proc, pid, threads, start)
        made.append(hw.step(pid, proc, state, out, 1000.0 + 60 * i, HZ, notify=lambda: told.append(1)))
    return made, told, out, state


def test_two_busy_minutes_are_caught_once_with_the_busy_thread_first(tmp_path):
    samples = [
        {42: ("qs", 0), 43: ("Thread (pooled)", 0)},
        {42: ("qs", 600), 43: ("Thread (pooled)", 3000)},
        {42: ("qs", 1200), 43: ("Thread (pooled)", 6000)},
        {42: ("qs", 1800), 43: ("Thread (pooled)", 9000)},
    ]
    made, told, out, _ = run_steps(tmp_path, samples)
    assert made[0] is None and made[1] is None, "one busy minute is not yet a busy shell"
    assert made[2] is not None and made[3] is None, "caught once a run, not every minute after"
    assert told == [1]
    threads = (made[2] / "threads.txt").read_text().splitlines()
    assert "Thread (pooled)" in threads[0] and "50.0%" in threads[0]
    summary = (made[2] / "summary.txt").read_text()
    assert "busy: 60% of one CPU" in summary and "Rss: 400000 kB" in summary


def test_a_quiet_shell_and_a_short_burst_are_left_alone(tmp_path):
    samples = [
        {42: ("qs", 0)},
        {42: ("qs", 6000)},
        {42: ("qs", 6100)},
        {42: ("qs", 12100)},
    ]
    made, told, out, _ = run_steps(tmp_path, samples)
    assert made == [None, None, None, None] and told == []
    assert not out.exists()


def test_a_restarted_shell_starts_counting_again(tmp_path):
    proc, state, out = tmp_path / "proc", tmp_path / "run/hotwatch.json", tmp_path / "hot"
    fake_proc(proc, 42, {42: ("qs", 0)}, start=1)
    hw.step(42, proc, state, out, 1000.0, HZ, notify=lambda: None)
    fake_proc(proc, 42, {42: ("qs", 6000)}, start=2)
    hw.step(42, proc, state, out, 1060.0, HZ, notify=lambda: None)
    assert json.loads(state.read_text())["streak"] == 0, "a new run with the same pid is not a continuation"


def test_no_shell_running_clears_the_state(tmp_path):
    state = tmp_path / "run/hotwatch.json"
    assert hw.step(0, tmp_path / "proc", state, tmp_path / "hot", 1000.0, HZ, notify=lambda: None) is None
    assert json.loads(state.read_text()) == {}


def test_only_the_newest_five_captures_are_kept(tmp_path):
    out = tmp_path / "hot"
    for i in range(7):
        (out / f"2026112{i}-000000").mkdir(parents=True)
    proc = tmp_path / "proc"
    fake_proc(proc, 42, {42: ("qs", 0)})
    prev = hw.sample(42, proc, 1000.0)
    fake_proc(proc, 42, {42: ("qs", 9000)})
    cur = hw.sample(42, proc, 1060.0)
    hw.capture(out, 42, 150.0, prev, cur, HZ, proc)
    assert len([p for p in out.iterdir() if p.is_dir()]) == 5


def test_last_says_so_when_nothing_was_caught(tmp_path):
    r = subprocess.run([str(ROOT / "bin/kuwai-hotwatch"), "--last"], capture_output=True, text=True,
                       env={"HOME": str(tmp_path), "XDG_STATE_HOME": str(tmp_path / "state"), "PATH": "/usr/bin:/bin"})
    assert r.returncode == 1 and "hasn't been caught busy" in r.stdout


def test_the_units_and_the_installer_agree():
    timer = (ROOT / "systemd/kuwai-hotwatch.timer").read_text()
    service = (ROOT / "systemd/kuwai-hotwatch.service").read_text()
    assert "OnUnitActiveSec=1min" in timer and "WantedBy=timers.target" in timer
    assert "bin/kuwai-hotwatch" in service and "Type=oneshot" in service
    units = (ROOT / "install.sh").read_text()
    assert "kuwai-hotwatch.service kuwai-hotwatch.timer" in units
