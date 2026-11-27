"""kuwai-activity: apps by systemd unit, from fake cgroup and proc trees; kuwai-procs --end-unit."""
import importlib.machinery
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
ACTIVITY = ROOT / "bin/kuwai-activity"
PROCS = ROOT / "bin/kuwai-procs"


def load(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


@pytest.fixture(scope="module")
def activity():
    return load(ACTIVITY, "activity_fixture")


@pytest.fixture(scope="module")
def procs():
    return load(PROCS, "procs_fixture")


class World:
    def __init__(self, base):
        self.cg = base / "cg"
        self.proc = base / "proc"
        (self.cg / "app.slice").mkdir(parents=True)
        self.proc.mkdir()

    def unit(self, name, usec, pids, slice="app.slice"):
        d = self.cg / slice / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "cpu.stat").write_text("usage_usec %d\nuser_usec 0\nsystem_usec 0\n" % usec)
        (d / "cgroup.procs").write_text("".join("%d\n" % p for p in pids))
        return d

    def process(self, pid, comm, ppid=1, start=100, pss_kb=None, rss_pages=0, cmd=None):
        d = self.proc / str(pid)
        d.mkdir(exist_ok=True)
        (d / "comm").write_text(comm + "\n")
        (d / "cmdline").write_bytes((cmd or comm).replace(" ", "\0").encode() + b"\0")
        fields = ["S", str(ppid)] + ["0"] * 17 + [str(start), "0", str(rss_pages)]
        (d / "stat").write_text("%d (%s) %s\n" % (pid, comm, " ".join(fields)))
        if pss_kb is not None:
            (d / "smaps_rollup").write_text("Rss: 1 kB\nPss:   %d kB\n" % pss_kb)

    def sampler(self, activity, mem_every=5.0):
        return activity.Sampler(str(self.cg), str(self.proc), 8, mem_every)


@pytest.fixture
def world(tmp_path):
    return World(tmp_path)


def by_unit(frame):
    return {u["unit"]: u for u in frame["units"]}


def test_unit_names_give_the_launcher_and_the_application(procs):
    cases = {
        "app-com.t3tools.T3Code-7010.scope": ("", "com.t3tools.T3Code"),
        "app-cursor-868066.scope": ("", "cursor"),
        "app-gnome-org.gnome.Nautilus-1234.scope": ("gnome", "org.gnome.Nautilus"),
        "app-Hyprland-zen\\x2dbrowser-2345.scope": ("Hyprland", "zen-browser"),
        "app-org.mozilla.firefox@autostart.service": ("", "org.mozilla.firefox"),
        "app-flatpak-org.foo.Bar-99.scope": ("flatpak", "org.foo.Bar"),
    }
    for name, want in cases.items():
        assert procs.unit_app(name) == want, name


def test_cpu_is_the_unit_usage_over_the_time_between_two_readings(activity, world):
    world.process(10, "kitty")
    world.process(11, "zsh", ppid=10, start=101)
    world.unit("app-kitty-1.scope", 1_000_000, [10, 11])
    s = world.sampler(activity)
    first = by_unit(s.sample(now=0.0))
    assert first["app-kitty-1.scope"]["cpu"] == 0.0
    world.unit("app-kitty-1.scope", 1_500_000, [10, 11])
    frame = s.sample(now=1.0)
    assert by_unit(frame)["app-kitty-1.scope"]["cpu"] == 50.0
    assert frame["cpus"] == 8
    world.unit("app-kitty-1.scope", 3_700_000, [10, 11])
    assert by_unit(s.sample(now=2.0))["app-kitty-1.scope"]["cpu"] == 220.0


def test_the_share_follows_the_real_time_between_readings(activity, world):
    world.process(10, "kitty")
    world.unit("app-kitty-1.scope", 0, [10])
    s = world.sampler(activity)
    s.sample(now=0.0)
    world.unit("app-kitty-1.scope", 500_000, [10])
    assert by_unit(s.sample(now=2.0))["app-kitty-1.scope"]["cpu"] == 25.0


def test_a_counter_that_goes_backwards_reads_zero_not_negative(activity, world):
    world.process(10, "kitty")
    world.unit("app-kitty-1.scope", 9_000_000, [10])
    s = world.sampler(activity)
    s.sample(now=0.0)
    world.unit("app-kitty-1.scope", 1_000, [10])
    assert by_unit(s.sample(now=1.0))["app-kitty-1.scope"]["cpu"] == 0.0


def test_a_scope_that_vanishes_between_readings_is_left_out_and_forgotten(activity, world):
    world.process(10, "kitty")
    world.process(20, "mpv")
    world.unit("app-kitty-1.scope", 0, [10])
    gone = world.unit("app-mpv-2.scope", 0, [20])
    s = world.sampler(activity)
    s.sample(now=0.0)
    (gone / "cpu.stat").unlink()
    frame = s.sample(now=1.0)
    assert list(by_unit(frame)) == ["app-kitty-1.scope"]
    assert "app-mpv-2.scope" not in s.last and "app-mpv-2.scope" not in s.facts
    (gone / "cpu.stat").write_text("usage_usec 5\n")
    again = by_unit(s.sample(now=2.0))["app-mpv-2.scope"]
    assert again["cpu"] == 0.0, "a unit that comes back starts from nothing, not from before it left"


def test_a_scope_with_no_processes_is_not_listed(activity, world):
    world.unit("app-empty-3.scope", 0, [])
    assert world.sampler(activity).sample(now=0.0)["units"] == []


def test_a_process_that_exits_mid_sample_does_not_break_the_unit(activity, world):
    world.process(10, "kitty")
    world.unit("app-kitty-1.scope", 0, [10, 99])
    row = by_unit(world.sampler(activity).sample(now=0.0))["app-kitty-1.scope"]
    assert row["main"] == "kitty" and row["procs"] == 2


def test_memory_is_the_sum_of_proportional_sizes(activity, world):
    world.process(10, "firefox", pss_kb=1000)
    world.process(11, "Web Content", ppid=10, start=101, pss_kb=2000)
    world.process(12, "Web Content", ppid=10, start=102, pss_kb=500)
    world.unit("app-firefox-1.scope", 0, [10, 11, 12])
    row = by_unit(world.sampler(activity).sample(now=0.0))["app-firefox-1.scope"]
    assert row["mem"] == 3500 * 1024
    assert row["procs"] == 3


def test_a_process_that_hides_its_map_counts_its_resident_pages(activity, world):
    world.process(10, "cursor", pss_kb=None, rss_pages=250)
    world.unit("app-cursor-1.scope", 0, [10])
    row = by_unit(world.sampler(activity).sample(now=0.0))["app-cursor-1.scope"]
    assert row["mem"] == 250 * os.sysconf("SC_PAGE_SIZE")


def test_memory_is_read_on_the_slow_beat_and_carried_between(activity, world):
    world.process(10, "kitty", pss_kb=1000)
    world.unit("app-kitty-1.scope", 0, [10])
    s = world.sampler(activity, mem_every=5.0)
    assert by_unit(s.sample(now=0.0))["app-kitty-1.scope"]["mem"] == 1000 * 1024
    world.process(10, "kitty", pss_kb=9000)
    assert by_unit(s.sample(now=1.0))["app-kitty-1.scope"]["mem"] == 1000 * 1024
    assert by_unit(s.sample(now=4.9))["app-kitty-1.scope"]["mem"] == 1000 * 1024
    assert by_unit(s.sample(now=5.1))["app-kitty-1.scope"]["mem"] == 9000 * 1024


def test_the_main_process_is_the_one_whose_parent_is_not_in_the_unit(activity, world):
    world.process(30, "helper", ppid=20, start=300)
    world.process(20, "zen-bin", ppid=1, start=200)
    world.process(31, "helper", ppid=20, start=301)
    world.unit("app-zen-1.scope", 0, [30, 20, 31])
    row = by_unit(world.sampler(activity).sample(now=0.0))["app-zen-1.scope"]
    assert row["pid"] == 20 and row["main"] == "zen-bin" and row["start"] == 200
    assert row["id"] == "zen" and row["label"] == "Zen"


def test_a_long_command_name_is_read_in_full_from_the_command_line(activity, world):
    world.process(10, "quickshell-long", cmd="/usr/bin/quickshell-long-name -p x")
    world.unit("app-q-1.scope", 0, [10])
    assert by_unit(world.sampler(activity).sample(now=0.0))["app-q-1.scope"]["main"] == "quickshell-long-name"


def test_nested_cgroups_count_with_their_unit(activity, world):
    world.process(10, "podman")
    world.process(11, "conmon", ppid=10, start=101)
    d = world.unit("app-podman-1.scope", 0, [10])
    (d / "sub").mkdir()
    (d / "sub" / "cgroup.procs").write_text("11\n")
    assert by_unit(world.sampler(activity).sample(now=0.0))["app-podman-1.scope"]["procs"] == 2


def test_units_the_session_lives_on_are_marked_protected(activity, world):
    world.process(1, "pipewire")
    world.unit("app-pipewire-1.scope", 0, [1])
    world.process(2, "kitty")
    world.process(3, "ssh-agent", ppid=2, start=101)
    world.unit("app-kitty-2.scope", 0, [2, 3])
    world.process(4, "qs")
    world.unit("app-kuwai\\x2dshell-4.scope", 0, [4])
    world.process(5, "xdg-desktop-por")
    world.unit("app-org.freedesktop.impl.portal.desktop.gtk-5.scope", 0, [5])
    world.process(6, "mpv")
    world.unit("app-mpv-6.scope", 0, [6])
    rows = by_unit(world.sampler(activity).sample(now=0.0))
    assert {k: v["protected"] for k, v in rows.items()} == {
        "app-pipewire-1.scope": True,
        "app-kitty-2.scope": True,
        "app-kuwai\\x2dshell-4.scope": True,
        "app-org.freedesktop.impl.portal.desktop.gtk-5.scope": True,
        "app-mpv-6.scope": False,
    }


def test_the_unit_this_helper_runs_in_is_protected(activity, world, monkeypatch):
    world.process(10, "mpv")
    world.unit("app-mpv-1.scope", 0, [10])
    s = world.sampler(activity)
    s.own = "app-mpv-1.scope"
    assert by_unit(s.sample(now=0.0))["app-mpv-1.scope"]["protected"] is True


def test_slices_are_searched_but_the_sessions_are_not(activity, world):
    world.process(10, "mpv")
    world.process(11, "dunst")
    world.unit("app-mpv-1.scope", 0, [10], slice="app-graphical.slice")
    world.unit("app-dunst-1.scope", 0, [11], slice="session.slice")
    world.unit("app-nested-2.scope", 0, [10], slice="app.slice/app-t3code.slice/app-t3code-agents.slice")
    names = sorted(by_unit(world.sampler(activity).sample(now=0.0)))
    assert names == ["app-mpv-1.scope", "app-nested-2.scope"]


def test_plain_services_are_not_apps(activity, world):
    world.process(10, "voxtype")
    world.unit("voxtype.service", 0, [10])
    assert world.sampler(activity).sample(now=0.0)["units"] == []


def test_the_stream_is_json_lines_and_ends_with_its_frames(world):
    world.process(10, "kitty", pss_kb=100)
    world.unit("app-kitty-1.scope", 100, [10])
    out = subprocess.run([sys.executable, str(ACTIVITY), "--cgroup-root", str(world.cg), "--proc-root", str(world.proc),
                          "--first", "0.05", "--interval", "0.05", "--frames", "3", "--cpus", "4"],
                         capture_output=True, text=True, timeout=10)
    lines = out.stdout.splitlines()
    assert out.returncode == 0 and len(lines) == 3
    frame = json.loads(lines[0])
    assert frame["cpus"] == 4 and frame["units"][0]["unit"] == "app-kitty-1.scope"
    assert set(frame["units"][0]) == {"unit", "id", "launcher", "label", "main", "pid", "start", "protected", "mem", "procs", "cpu"}


def test_the_stream_stops_when_the_reader_goes_away(world):
    world.process(10, "kitty")
    world.unit("app-kitty-1.scope", 100, [10])
    p = subprocess.Popen([sys.executable, str(ACTIVITY), "--cgroup-root", str(world.cg), "--proc-root", str(world.proc),
                          "--first", "0.05", "--interval", "0.05"], stdout=subprocess.PIPE, text=True)
    p.stdout.readline()
    p.stdout.close()
    assert p.wait(timeout=5) == 0


def test_it_ends_on_the_terminate_signal_while_waiting(world):
    p = subprocess.Popen([sys.executable, str(ACTIVITY), "--cgroup-root", str(world.cg), "--proc-root", str(world.proc),
                          "--interval", "30", "--first", "30"], stdout=subprocess.PIPE)
    time.sleep(0.3)
    p.send_signal(signal.SIGTERM)
    assert p.wait(timeout=5) == -signal.SIGTERM


def end_unit(world, unit, *flags):
    r = subprocess.run([str(PROCS), "--end-unit", unit, "--cgroup-root", str(world.cg), *flags],
                       capture_output=True, text=True, timeout=15)
    return json.loads(r.stdout)


def reap(procs_):
    for p in procs_:
        try:
            p.kill()
        except OSError:
            pass
        p.wait()


def test_stop_ends_every_process_of_the_unit_and_nothing_else(world):
    inside = [subprocess.Popen(["sleep", "30"]) for _ in range(3)]
    outside = subprocess.Popen(["sleep", "30"])
    try:
        world.unit("app-sleeper-1.scope", 0, [p.pid for p in inside])
        waiter = [subprocess.Popen(["true"])]
        out = end_unit_with_reaping(world, "app-sleeper-1.scope", inside)
        assert out == {"ok": True, "gone": True}
        assert outside.poll() is None
        reap(waiter)
    finally:
        reap(inside + [outside])


def end_unit_with_reaping(world, unit, children, *flags):
    import threading
    result = {}

    def run():
        result["out"] = end_unit(world, unit, *flags)

    t = threading.Thread(target=run)
    t.start()
    deadline = time.monotonic() + 10
    while t.is_alive() and time.monotonic() < deadline:
        for c in children:
            c.poll()
        time.sleep(0.05)
    t.join(timeout=1)
    return result["out"]


def test_stop_reports_an_app_that_ignores_it_and_force_ends_it(world):
    p = subprocess.Popen(["sh", "-c", 'trap "" TERM; while :; do sleep 1; done'])
    try:
        time.sleep(0.2)
        world.unit("app-stubborn-1.scope", 0, [p.pid])
        out = end_unit_with_reaping(world, "app-stubborn-1.scope", [p])
        assert out == {"ok": True, "gone": False, "why": "it's still running; force quit ends it"}
        assert p.poll() is None
        out = end_unit_with_reaping(world, "app-stubborn-1.scope", [p], "--force")
        assert out == {"ok": True, "gone": True}
    finally:
        reap([p])


def test_a_unit_with_a_session_process_is_refused(world, tmp_path):
    fake = tmp_path / "pipewire"
    fake.write_bytes(Path("/usr/bin/sleep").read_bytes())
    fake.chmod(0o755)
    p = subprocess.Popen([str(fake), "30"])
    try:
        world.unit("app-audio-1.scope", 0, [p.pid])
        out = end_unit(world, "app-audio-1.scope", "--force")
        assert out["ok"] is False and "session" in out["why"]
        assert p.poll() is None
    finally:
        reap([p])


def test_the_shells_own_and_portal_units_are_refused_by_name(world):
    p = subprocess.Popen(["sleep", "30"])
    try:
        for unit in ("app-kuwai\\x2dshell-1.scope", "app-org.freedesktop.portal.Desktop-2.scope"):
            world.unit(unit, 0, [p.pid])
            out = end_unit(world, unit)
            assert out["ok"] is False and "session" in out["why"], unit
        assert p.poll() is None
    finally:
        reap([p])


def test_a_unit_holding_the_launcher_is_refused(world):
    holder = subprocess.Popen([sys.executable, "-c", (
        "import subprocess, sys, json\n"
        "r = subprocess.run([sys.argv[1], '--end-unit', 'app-me-1.scope', '--cgroup-root', sys.argv[2]], capture_output=True, text=True)\n"
        "print(r.stdout)\n"), str(PROCS), str(world.cg)], stdout=subprocess.PIPE, text=True)
    try:
        world.unit("app-me-1.scope", 0, [holder.pid])
        out = json.loads(holder.communicate(timeout=10)[0])
        assert out["ok"] is False and "launcher" in out["why"]
    finally:
        reap([holder])


def test_what_is_not_an_app_unit_is_never_touched(world):
    p = subprocess.Popen(["sleep", "30"])
    try:
        world.unit("voxtype.service", 0, [p.pid])
        for name in ("voxtype.service", "../../init.scope", "app-x/../y.scope", ""):
            assert end_unit(world, name)["ok"] is False
        assert p.poll() is None
    finally:
        reap([p])


def test_a_unit_that_is_already_gone_is_not_an_error(world):
    assert end_unit(world, "app-nothing-9.scope") == {"ok": True, "why": "already gone"}
