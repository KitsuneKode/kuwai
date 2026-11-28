"""bin/kuwai-job: a deletion runs outside the shell and its state is a file, so it survives the shell
and nothing runs twice. Only fake commands run here; nothing real is touched."""
import json
import os
import signal
import stat
import subprocess
import sys
import textwrap
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
JOB = ROOT / "bin" / "kuwai-job"


@pytest.fixture
def world(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    env = {"HOME": str(home), "PATH": f"{fakebin}:{os.environ['PATH']}", "XDG_STATE_HOME": str(tmp_path / "state"),
           "PYTHONDONTWRITEBYTECODE": "1"}
    return tmp_path, fakebin, env


def job(env, *args, timeout=20):
    r = subprocess.run([sys.executable, str(JOB), *args], capture_output=True, text=True, env=env, timeout=timeout)
    return r.returncode, (json.loads(r.stdout) if r.stdout.strip() else None)


def deleter(tmp_path, files=6, pause=0.25):
    victims = tmp_path / "victims"
    victims.mkdir(exist_ok=True)
    for i in range(files):
        (victims / f"f{i}").write_text("x")
    log = tmp_path / "runs.log"
    script = tmp_path / "slow-delete"
    script.write_text(textwrap.dedent(f"""\
        #!{sys.executable}
        import json, os, sys, time
        open({str(log)!r}, "a").write("run\\n")
        freed = 0
        for n in sorted(os.listdir({str(victims)!r})):
            os.unlink(os.path.join({str(victims)!r}, n))
            freed += 1
            time.sleep({pause})
        print("noise")
        print(json.dumps({{"ok": True, "freed": freed}}))
        """))
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script, victims, log


def wait_for(pred, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        if pred():
            return True
        time.sleep(0.05)
    return False


def fake_systemd_run(fakebin, record):
    path = fakebin / "systemd-run"
    path.write_text(textwrap.dedent(f"""\
        #!/bin/sh
        printf '%s\\n' "$@" > {record}
        while [ "$1" != "--" ]; do shift; done
        shift
        setsid "$@" </dev/null >/dev/null 2>&1 &
        exit 0
        """))
    path.chmod(0o755)


def test_nothing_yet_is_none(world):
    _, _, env = world
    assert job(env, "status", "storage")[1] == {"state": "none", "kind": "storage"}


def test_a_run_leaves_its_result_in_a_file(world):
    tmp, _, env = world
    script, victims, log = deleter(tmp, files=3, pause=0.05)
    rc, out = job(env, "start", "storage", "pip", "--", str(script))
    assert rc == 0 and out["ok"] is True
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    s = job(env, "status", "storage")[1]
    assert s["label"] == "pip" and s["code"] == 0 and s["result"] == {"ok": True, "freed": 3} and s["seen"] is False
    assert list(victims.iterdir()) == []
    assert job(env, "ack", "storage")[1]["seen"] is True
    assert job(env, "status", "storage")[1]["seen"] is True
    assert log.read_text() == "run\n"


def test_it_is_running_while_it_runs_and_the_panel_can_ask_again(world):
    tmp, _, env = world
    script, victims, _ = deleter(tmp, files=8, pause=0.3)
    job(env, "start", "storage", "uv", "--", str(script))
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "running")
    assert len(list(victims.iterdir())) > 0
    for _ in range(3):
        assert job(env, "status", "storage")[1]["state"] in ("queued", "running")
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")


def test_a_second_start_while_one_runs_is_refused_and_nothing_deletes_twice(world):
    tmp, _, env = world
    script, victims, log = deleter(tmp, files=6, pause=0.3)
    assert job(env, "start", "storage", "pip", "--", str(script))[1]["ok"] is True
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "running")
    rc, again = job(env, "start", "storage", "pip", "--", str(script))
    assert rc == 1 and again == {"ok": False, "busy": True}
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    for _ in range(3):
        job(env, "status", "storage")
    assert log.read_text() == "run\n"


def test_two_runners_racing_for_one_kind_run_it_once(world):
    tmp, _, env = world
    script, _, log = deleter(tmp, files=4, pause=0.2)
    cmd = [sys.executable, str(JOB), "run", "cleanup", "x", "id1", "--", str(script)]
    a = subprocess.Popen(cmd, env=env)
    assert wait_for(lambda: log.exists())
    b = subprocess.run([*cmd[:5], "id2", *cmd[6:]], env=env)
    assert b.returncode == 3
    assert a.wait(timeout=20) == 0
    assert log.read_text() == "run\n"
    assert job(env, "status", "cleanup")[1]["id"] == "id1"


def test_kinds_do_not_block_each_other(world):
    tmp, _, env = world
    script, _, log = deleter(tmp, files=4, pause=0.2)
    job(env, "start", "storage", "a", "--", str(script))
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "running")
    assert job(env, "start", "cleanup", "b", "--", "/bin/true")[1]["ok"] is True


def test_a_deletion_goes_on_when_the_process_that_started_it_is_killed(world):
    tmp, fakebin, env = world
    record = tmp / "systemd-run.args"
    fake_systemd_run(fakebin, record)
    script, victims, log = deleter(tmp, files=10, pause=0.3)
    launcher = tmp / "fake-shell"
    launcher.write_text(textwrap.dedent(f"""\
        import subprocess, sys, time
        subprocess.run([sys.executable, {str(JOB)!r}, "start", "storage", "a label; with $odd 'chars'", "--", {str(script)!r}], check=True)
        time.sleep(600)
        """))
    shell = subprocess.Popen([sys.executable, str(launcher)], env={**env, "KUWAI_SHELL_UNIT": "1"}, start_new_session=True)
    try:
        assert wait_for(lambda: log.exists() and len(list(victims.iterdir())) < 10)
        os.killpg(shell.pid, signal.SIGKILL)
        shell.wait(timeout=5)
        left = len(list(victims.iterdir()))
        assert left > 0
        assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
        assert list(victims.iterdir()) == []
        s = job(env, "status", "storage")[1]
        assert s["result"] == {"ok": True, "freed": 10} and s["label"] == "a label; with $odd 'chars'"
        assert log.read_text() == "run\n"
    finally:
        if shell.poll() is None:
            os.killpg(shell.pid, signal.SIGKILL)


def test_inside_the_shells_unit_it_goes_to_systemd_with_values_as_arguments(world):
    tmp, fakebin, env = world
    record = tmp / "systemd-run.args"
    fake_systemd_run(fakebin, record)
    script, _, _ = deleter(tmp, files=1, pause=0.01)
    env = {**env, "KUWAI_SHELL_UNIT": "1", "SWEEP_CONFIG_DIR": "/sweep config$HOME"}
    assert job(env, "start", "cleanup", "trash:a b; rm -rf /", "--", str(script), "x y")[1]["ok"] is True
    assert wait_for(lambda: record.exists() and job(env, "status", "cleanup")[1]["state"] == "done")
    args = record.read_text().splitlines()
    assert args[:4] == ["--user", "--collect", "--quiet", "--expand-environment=no"]
    assert any(a.startswith("--unit=kuwai-job-cleanup-") for a in args)
    assert "--slice=app.slice" in args and f"--setenv=PATH={env['PATH']}" in args
    assert f"--setenv=HOME={env['HOME']}" in args and f"--setenv=SWEEP_CONFIG_DIR={env['SWEEP_CONFIG_DIR']}" in args
    assert "--property=Type=exec" in args
    assert "--property=StandardOutput=null" in args and "--property=StandardError=null" in args
    tail = args[args.index("--") + 1:]
    assert tail[2:5] == ["run", "cleanup", "trash:a b; rm -rf /"] and tail[-3:] == ["--", str(script), "x y"]


def test_systemd_failure_falls_back_to_one_detached_process_and_says_so(world):
    tmp, fakebin, env = world
    fakebin.joinpath("systemd-run").write_text("#!/bin/sh\nexit 1\n")
    fakebin.joinpath("systemd-run").chmod(0o755)
    script, victims, _ = deleter(tmp, files=2, pause=0.03)
    env = {**env, "KUWAI_SHELL_UNIT": "1"}
    r = subprocess.run([sys.executable, str(JOB), "start", "storage", "pip", "--", str(script)],
                       capture_output=True, text=True, env=env, timeout=20)
    assert r.returncode == 0 and json.loads(r.stdout)["ok"] is True
    assert "systemd-run could not start" in r.stderr and "detached process" in r.stderr
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    assert list(victims.iterdir()) == []


def test_without_systemd_run_the_fallback_is_detached_and_says_so(world):
    tmp, fakebin, env = world
    script, victims, _ = deleter(tmp, files=2, pause=0.03)
    env = {**env, "KUWAI_SHELL_UNIT": "1", "PATH": str(fakebin)}
    r = subprocess.run([sys.executable, str(JOB), "start", "storage", "pip", "--", str(script)],
                       capture_output=True, text=True, env=env, timeout=20)
    assert r.returncode == 0 and json.loads(r.stdout)["ok"] is True
    assert "systemd-run is unavailable" in r.stderr and "detached process" in r.stderr
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    assert list(victims.iterdir()) == []


def load_job_module(monkeypatch, env):
    from importlib.machinery import SourceFileLoader
    import importlib.util
    monkeypatch.setenv("XDG_STATE_HOME", env["XDG_STATE_HOME"])
    loader = SourceFileLoader("kuwai_job_under_test", str(JOB))
    spec = importlib.util.spec_from_loader("kuwai_job_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_a_queued_run_is_busy_even_before_the_runner_takes_the_lock(world, monkeypatch):
    _, _, env = world
    m = load_job_module(monkeypatch, env)
    monkeypatch.setattr(m.transient, "launch", lambda *a, **kw: pytest.fail("the queued run must not be started twice"))
    m.write_state("storage", {"id": "q", "kind": "storage", "label": "pip", "state": "queued",
                              "started": int(time.time()), "seen": False})
    assert m.start("storage", "pip", ["/bin/true"]) == {"ok": False, "busy": True}


def test_a_stale_queued_run_can_be_started_again(world, monkeypatch):
    _, _, env = world
    m = load_job_module(monkeypatch, env)
    launches = []
    monkeypatch.setattr(m.transient, "launch", lambda *a, **kw: launches.append(a) or "detached")
    m.write_state("storage", {"id": "q", "kind": "storage", "label": "pip", "state": "queued",
                              "started": int(time.time() - m.QUEUE_GRACE_S - 1), "seen": False})
    out = m.start("storage", "pip", ["/bin/true"])
    assert out["ok"] is True and len(launches) == 1
    assert m.read_state("storage")["state"] == "queued" and m.read_state("storage")["id"] != "q"


def test_two_starts_at_the_same_time_run_the_deletion_once(world):
    tmp, _, env = world
    script, victims, log = deleter(tmp, files=6, pause=0.25)
    cmd = [sys.executable, str(JOB), "start", "storage", "pip", "--", str(script)]
    a = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    b = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    results = []
    for p in (a, b):
        out, _ = p.communicate(timeout=20)
        results.append((p.returncode, json.loads(out)))
    assert sorted(rc for rc, _ in results) == [0, 1]
    assert sum(1 for _, out in results if out.get("ok") is True) == 1
    assert sum(1 for _, out in results if out == {"ok": False, "busy": True}) == 1
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    assert list(victims.iterdir()) == [] and log.read_text() == "run\n"


def test_outside_the_unit_it_is_a_detached_process_not_systemd(world):
    tmp, fakebin, env = world
    record = tmp / "systemd-run.args"
    fake_systemd_run(fakebin, record)
    script, _, _ = deleter(tmp, files=1, pause=0.01)
    job(env, "start", "storage", "a", "--", str(script))
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    assert not record.exists()


def test_a_runner_that_dies_is_lost_not_running_for_ever(world):
    tmp, _, env = world
    script, _, _ = deleter(tmp, files=40, pause=0.5)
    p = subprocess.Popen([sys.executable, str(JOB), "run", "storage", "x", "id9", "--", str(script)], env=env, start_new_session=True)
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "running")
    os.killpg(p.pid, signal.SIGKILL)
    p.wait(timeout=5)
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "lost")
    assert job(env, "ack", "storage")[1]["seen"] is True


def test_a_start_that_never_became_a_runner_is_lost_after_a_moment(world, tmp_path):
    _, _, env = world
    from importlib.machinery import SourceFileLoader
    import importlib.util
    loader = SourceFileLoader("kuwai_job", str(JOB))
    spec = importlib.util.spec_from_loader("kuwai_job", loader)
    m = importlib.util.module_from_spec(spec)
    os.environ["XDG_STATE_HOME"] = env["XDG_STATE_HOME"]
    loader.exec_module(m)
    m.write_state("storage", {"id": "q", "kind": "storage", "label": "a", "state": "queued", "started": 1000, "seen": False})
    assert m.status("storage", now=1005)["state"] == "queued"
    assert m.status("storage", now=1000 + m.QUEUE_GRACE_S + 1)["state"] == "lost"


def test_a_command_that_prints_nothing_still_has_a_code(world):
    _, _, env = world
    job(env, "start", "storage", "a", "--", "/bin/false")
    assert wait_for(lambda: job(env, "status", "storage")[1]["state"] == "done")
    s = job(env, "status", "storage")[1]
    assert s["code"] == 1 and s["result"] is None


def test_it_refuses_what_it_does_not_understand(world):
    _, _, env = world
    assert job(env, "start", "Bad Kind", "a", "--", "/bin/true")[0] == 2
    assert job(env, "start", "storage", "a")[0] == 2
    assert job(env, "status", "../x")[0] == 2
