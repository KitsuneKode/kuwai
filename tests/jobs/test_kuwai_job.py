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
        exec setsid "$@"
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
    env = {**env, "KUWAI_SHELL_UNIT": "1"}
    assert job(env, "start", "cleanup", "trash:a b; rm -rf /", "--", str(script), "x y")[1]["ok"] is True
    assert wait_for(lambda: record.exists() and job(env, "status", "cleanup")[1]["state"] == "done")
    args = record.read_text().splitlines()
    assert args[:3] == ["--user", "--collect", "--quiet"]
    assert any(a.startswith("--unit=kuwai-job-cleanup-") for a in args)
    assert "--slice=app.slice" in args and f"--setenv=PATH={env['PATH']}" in args
    tail = args[args.index("--") + 1:]
    assert tail[2:5] == ["run", "cleanup", "trash:a b; rm -rf /"] and tail[-3:] == ["--", str(script), "x y"]


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
