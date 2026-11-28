"""bin/kuwai-dictation, against fake voxtype, shuush and systemctl on PATH: what Settings → Dictation reads,
the only choices it may change, and a restart that never cuts a take short."""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "kuwai-dictation"

STATUS = {"alt": "idle", "model": "/home/x/.local/share/voxtype/models/parakeet-unified-en-0.6b-fp16/", "backend": "GPU (Vulkan)"}
CONFIG = {"engine": "parakeet", "audio.warm_mic_secs": 3, "audio.release_tail_ms": 400, "audio.queue_dictations": True,
          "output.preedit": True, "parakeet.idle_unload_secs": 120, "parakeet.on_demand_loading": False}
DOCTOR = {"checks": [{"id": "llm_ready", "status": "ok"}]}
LEARN = {"total_rules": 43, "by_source": {"seed": 32, "user fix": 4, "edit-watch": 0, "accepted hint": 1, "auto": 6, "junk": 9},
         "pending_fixes": 6, "pending_vocab": 1, "vocab": {"global": 55}}
LATENCY = {"overall": {"metrics": {"release_to_done_ms": {"n": 12, "p50": 610, "p90": 1180, "p95": 1400}}}}


def fake(path, name, body):
    p = path / name
    p.write_text("#!/bin/sh\n" + body)
    p.chmod(0o755)


def answers(path, name, table):
    """A fake whose answer to `NAME ARGS…` is table[ARGS joined by space], else exit 2; every call is logged."""
    data = path / (name + ".json")
    data.write_text(json.dumps(table))
    fake(path, name, f'echo "$*" >> "{path}/{name}.calls"\n'
                     f'exec python3 -c \'import json,sys; t=json.load(open(sys.argv[1])); k=" ".join(sys.argv[2:]); '
                     f'v=t.get(k); sys.exit(2) if v is None else print(v if isinstance(v,str) else json.dumps(v))\' "{data}" "$@"\n')


@pytest.fixture
def env(tmp_path):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    run = tmp_path / "run"
    (run / "voxtype").mkdir(parents=True)
    (run / "voxtype" / "state").write_text("idle\n")
    cfg = tmp_path / "config"
    (cfg / "voxtype").mkdir(parents=True)
    tools = tmp_path / "tools"
    tools.mkdir()
    (tools / "python3").symlink_to(shutil.which("python3") or sys.executable)
    fake(bin_, "systemctl", f'echo "$*" >> "{bin_}/systemctl.calls"\n')
    e = {"PATH": f"{bin_}:{tools}", "HOME": str(tmp_path), "XDG_RUNTIME_DIR": str(run), "XDG_CONFIG_HOME": str(cfg)}
    return {"bin": bin_, "run": run, "cfg": cfg, "env": e}


def voxtype(env, status=STATUS, config=CONFIG, sets=("ok",)):
    table = {"status --format json --extended": status, "config get --json": config}
    for key, values in {"audio.warm_mic_secs": ("0", "3", "5"), "audio.release_tail_ms": ("0", "200", "400", "600"),
                        "audio.queue_dictations": ("true", "false"), "output.preedit": ("true", "false")}.items():
        for v in values:
            table[f"config set {key} {v}"] = "ok"
    answers(env["bin"], "voxtype", table)


def shuush(env, doctor=DOCTOR, learn=LEARN, latency=LATENCY, reliability=None):
    table = {"doctor --json": doctor, "learn stats --json": learn, "stats latency --json": latency}
    if reliability is not None:
        table["stats reliability --json"] = reliability
    answers(env["bin"], "shuush", table)


def run(env, *args):
    out = subprocess.run([str(HELPER), *args], env=env["env"], capture_output=True, text=True, timeout=30)
    return out.returncode, json.loads(out.stdout) if out.stdout.strip() else None


def calls(env, name):
    p = env["bin"] / (name + ".calls")
    return p.read_text().splitlines() if p.exists() else []


def test_read_reports_engine_choices_last_take_and_shuush(env):
    voxtype(env)
    shuush(env, reliability={"overall": {"delivered": 97, "total": 100}})
    (env["cfg"] / "voxtype" / "postprocess.env").write_text('PP_LOCAL_MODEL="qwen3:4b"\nPP_ORDER="groq groq2 openrouter"\n')
    now = int(time.time() * 1000)
    (env["run"] / "voxtype" / "outcome.json").write_text(json.dumps({"outcome": "ok", "at_ms": now - 30_000, "chars": 157, "limit_reached": False}))
    code, r = run(env, "read")
    assert code == 0
    v = r["voxtype"]
    assert v["installed"] and v["running"] and v["answered"]
    assert (v["engine"], v["model"], v["gpu"], v["state"]) == ("parakeet", "parakeet-unified-en-0.6b-fp16", True, "idle")
    assert (v["model_state"], v["unload_after"]) == ("loaded", 120)
    assert v["config"] == {"warm": 3, "tail": 400, "queue": True, "preedit": True}
    assert r["last"] == {"outcome": "ok", "at": now - 30_000, "chars": 157, "limit": False}
    s = r["shuush"]
    assert s["order"] == ["groq", "groq2", "openrouter"] and s["offline"] is False and s["cleanup_ready"] is True
    assert s["learn"]["by_source"] == {"seed": 32, "auto": 6, "user fix": 4, "accepted hint": 1, "edit-watch": 0}
    assert (s["learn"]["pending_fixes"], s["learn"]["pending_vocab"], s["learn"]["vocab"]) == (6, 1, 55)
    assert s["speed"] == {"n": 12, "p50": 610, "p90": 1180}
    assert s["delivered"] == {"n": 100, "rate": 0.97}


def test_missing_engine_and_cleanup_are_said_not_guessed(env):
    code, r = run(env, "read")
    assert code == 0
    assert r["voxtype"] == {"installed": False} and r["shuush"] == {"installed": False} and r["last"] is None


def test_a_stopped_daemon_and_an_old_take_mean_set_aside(env):
    voxtype(env, status={"alt": "stopped"})
    shuush(env, latency={"overall": {"metrics": {"release_to_done_ms": None}}})
    (env["run"] / "voxtype" / "state").write_text("stopped\n")
    code, r = run(env, "read")
    assert r["voxtype"]["running"] is False and r["voxtype"]["model_state"] == ""
    assert r["shuush"]["speed"] is None and r["shuush"]["delivered"] is None
    voxtype(env)
    (env["run"] / "voxtype" / "state").write_text("idle\n")
    (env["run"] / "voxtype" / "outcome.json").write_text(json.dumps({"outcome": "ok", "at_ms": 1000, "chars": 5}))
    assert run(env, "read")[1]["voxtype"]["model_state"] == "unloaded"


def test_offline_order_and_default_order_come_from_shuushs_env(env):
    voxtype(env)
    shuush(env)
    assert run(env, "read")[1]["shuush"]["order"] == ["local", "groq"]
    (env["cfg"] / "voxtype" / "postprocess.env").write_text("export PP_ORDER='local'  # offline\n")
    s = run(env, "read")[1]["shuush"]
    assert s["order"] == ["local"] and s["offline"] is True


def test_garbage_from_the_tools_is_never_passed_on(env):
    fake(env["bin"], "voxtype", 'echo "not json"\n')
    fake(env["bin"], "shuush", "exit 1\n")
    (env["run"] / "voxtype" / "outcome.json").write_text('{"outcome": "<b>rm -rf</b>", "at_ms": 1}')
    (env["run"] / "voxtype" / "state").write_text("$(reboot)\n")
    (env["cfg"] / "voxtype" / "postprocess.env").write_text('PP_ORDER="groq ../../etc $(x) local"\n')
    code, r = run(env, "read")
    assert code == 0
    assert r["voxtype"]["answered"] is False and r["voxtype"]["state"] == "" and r["last"] is None
    assert r["shuush"]["order"] == ["groq", "local"] and r["shuush"]["learn"] is None


@pytest.mark.parametrize("name,value,key,sent", [
    ("warm", "5", "audio.warm_mic_secs", "5"),
    ("tail", "0", "audio.release_tail_ms", "0"),
    ("queue", "off", "audio.queue_dictations", "false"),
    ("preedit", "on", "output.preedit", "true"),
])
def test_set_passes_one_allowed_key_and_value_as_arguments(env, name, value, key, sent):
    voxtype(env)
    code, r = run(env, "set", name, value)
    assert code == 0 and r["ok"] is True
    assert calls(env, "voxtype") == [f"config set {key} {sent}"]


@pytest.mark.parametrize("name,value", [("warm", "7"), ("tail", "1000"), ("queue", "maybe"), ("engine", "whisper"),
                                         ("hotkey.key", "F1"), ("warm", "3; rm -rf ~"), ("preedit", "")])
def test_set_refuses_anything_else_without_calling_voxtype(env, name, value):
    voxtype(env)
    code, r = run(env, "set", name, value)
    assert code == 1 and r["ok"] is False
    assert calls(env, "voxtype") == []


def test_set_reports_a_refusal_from_voxtype(env):
    fake(env["bin"], "voxtype", "exit 2\n")
    code, r = run(env, "set", "warm", "5")
    assert code == 1 and r == {"ok": False, "why": "failed", "name": "warm", "value": "5"}


def test_restart_only_while_idle(env):
    code, r = run(env, "restart")
    assert code == 0 and r == {"restarted": True, "state": "idle", "why": ""}
    assert calls(env, "systemctl") == ["--user try-restart voxtype.service"]


@pytest.mark.parametrize("state", ["recording", "streaming", "transcribing"])
def test_restart_waits_for_a_take_in_progress(env, state):
    (env["run"] / "voxtype" / "state").write_text(state + "\n")
    code, r = run(env, "restart")
    assert code == 0 and r == {"restarted": False, "state": state}
    assert calls(env, "systemctl") == []


def test_restart_leaves_a_stopped_daemon_alone(env):
    os.remove(env["run"] / "voxtype" / "state")
    assert run(env, "restart")[1] == {"restarted": False, "state": "stopped"}
    (env["run"] / "voxtype" / "state").write_text("stopped")
    assert run(env, "restart")[1] == {"restarted": False, "state": "stopped"}
    assert calls(env, "systemctl") == []


def test_restart_says_when_systemd_refuses(env):
    fake(env["bin"], "systemctl", "exit 5\n")
    code, r = run(env, "restart")
    assert code == 1 and r == {"restarted": False, "state": "idle", "why": "failed"}


def test_unknown_commands_print_the_usage(env):
    out = subprocess.run([str(HELPER), "record"], env=env["env"], capture_output=True, text=True, timeout=10)
    assert out.returncode == 2 and out.stdout == "" and "kuwai-dictation read" in out.stderr
