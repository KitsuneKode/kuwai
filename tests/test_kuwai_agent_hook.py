"""Tests for bin/kuwai-agent-hook (Cursor Desktop, Devin, and generic hooks)."""
from __future__ import annotations

import json
import os
import stat
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "kuwai-agent-hook"


def run_hook(args: list[str], env: dict[str, str], stdin_data: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(BIN), *args],
        input=stdin_data,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def make_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["XDG_STATE_HOME"] = str(tmp_path / "state")
    env.pop("DEVIN_PROJECT_DIR", None)
    env.pop("DEVIN_SESSION_ID", None)
    for k in ("CURSOR_TRACE_ID", "CURSOR_VERSION", "T3CODE_THREAD_ID"):
        env.pop(k, None)
    return env


def test_cursor_hook_lifecycle_and_atomic_index(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    start_payload = json.dumps({
        "hook_event_name": "sessionStart",
        "conversation_id": "conv-42",
        "workspace_roots": ["/home/user/Projects/kuwai"],
        "prompt": "Fix the island limit carousel",
        "model": "claude-opus-5-5",
    })
    res = run_hook(["--agent", "cursor"], env, start_payload)
    assert res.returncode == 0

    state_dir = tmp_path / "state" / "kuwai" / "desktop-agents"
    index_file = tmp_path / "state" / "kuwai" / "desktop-agents.json"
    assert state_dir.is_dir()
    assert stat.S_IMODE(state_dir.stat().st_mode) == 0o700
    assert index_file.is_file()
    assert stat.S_IMODE(index_file.stat().st_mode) == 0o600

    idx = json.loads(index_file.read_text(encoding="utf-8"))
    assert idx["version"] == 1
    assert len(idx["agents"]) == 1
    row = idx["agents"][0]
    assert row["id"] == "cursor-conv-42"
    assert row["agent"] == "cursor"
    assert row["state"] == "working"
    assert row["project"] == "kuwai"
    assert row["title"] == "Fix the island limit carousel"
    assert row["window_class"] == "^(cursor|Cursor)$"

    stop_payload = json.dumps({"hook_event_name": "stop", "conversation_id": "conv-42"})
    assert run_hook(["--agent", "cursor"], env, stop_payload).returncode == 0
    idx = json.loads(index_file.read_text(encoding="utf-8"))
    assert idx["agents"][0]["state"] == "done"
    assert idx["agents"][0]["title"] == "Fix the island limit carousel"

    end_payload = json.dumps({"hook_event_name": "sessionEnd", "conversation_id": "conv-42"})
    assert run_hook(["--agent", "cursor"], env, end_payload).returncode == 0
    idx = json.loads(index_file.read_text(encoding="utf-8"))
    assert idx["agents"] == []


def test_devin_permission_and_dismiss(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    env["DEVIN_PROJECT_DIR"] = "/tmp/my-repo"
    payload = json.dumps({
        "hook_event_name": "PermissionRequest",
        "session_id": "dev-99",
        "tool_name": "Bash",
        "command": "rm -rf build/",
    })
    assert run_hook([], env, payload).returncode == 0

    listed = run_hook(["list"], env)
    assert listed.returncode == 0
    rows = json.loads(listed.stdout)
    assert len(rows) == 1
    assert rows[0]["agent"] == "devin"
    assert rows[0]["state"] == "waiting"
    assert rows[0]["ask"] == "approval"
    assert rows[0]["project"] == "my-repo"
    assert rows[0]["question"] == "rm -rf build/"

    assert run_hook(["dismiss", rows[0]["id"]], env).returncode == 0
    assert json.loads(run_hook(["list"], env).stdout) == []


def test_ttl_pruning_and_safe_ids(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    assert run_hook(["--agent", "cursor", "--session", "../../evil/id", "--state", "working"], env).returncode == 0
    d = tmp_path / "state" / "kuwai" / "desktop-agents"
    files = list(d.glob("*.json"))
    assert len(files) == 1
    assert ".." not in files[0].name

    stale = d / "cursor-old.json"
    stale.write_text(json.dumps({
        "id": "cursor-old",
        "agent": "cursor",
        "state": "working",
        "updated_at": time.time() - 5000,
        "ttl": 60,
    }), encoding="utf-8")

    rows = json.loads(run_hook(["list"], env).stdout)
    assert all(r["id"] != "cursor-old" for r in rows)
    assert not stale.exists()


def test_install_hooks_preserves_existing_and_is_idempotent(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    cursor_hooks = tmp_path / "cursor-hooks.json"
    cursor_hooks.write_text(json.dumps({
        "version": 1,
        "hooks": {
            "sessionStart": [{"command": "bash '/home/user/.cursor/herdr-agent-state.sh' session"}],
        },
    }), encoding="utf-8")
    devin_cfg = tmp_path / "devin-config.json"
    devin_cfg.write_text(json.dumps({"theme": "dark", "hooks": {}}), encoding="utf-8")

    args = ["install-hooks", "--cursor", "--devin", "--cursor-path", str(cursor_hooks), "--devin-path", str(devin_cfg)]
    assert run_hook(args, env).returncode == 0
    assert run_hook(args, env).returncode == 0

    c = json.loads(cursor_hooks.read_text(encoding="utf-8"))
    starts = c["hooks"]["sessionStart"]
    assert len(starts) == 2
    assert "herdr-agent-state.sh" in starts[0]["command"]
    assert "kuwai-agent-hook" in starts[1]["command"]
    assert "stop" in c["hooks"]

    d = json.loads(devin_cfg.read_text(encoding="utf-8"))
    assert d["theme"] == "dark"
    assert len(d["hooks"]["PermissionRequest"]) == 1
    assert "kuwai-agent-hook" in d["hooks"]["PermissionRequest"][0]["hooks"][0]["command"]


def test_malformed_stdin_never_fails_hook(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    res = run_hook(["--agent", "cursor", "--event", "sessionStart"], env, "{not valid json")
    assert res.returncode == 0


def _rows(env: dict[str, str]) -> list[dict]:
    return json.loads(run_hook(["list"], env).stdout)


def test_a_claude_hook_fired_by_cursor_or_devin_is_not_a_second_agent(tmp_path: Path) -> None:
    payload = json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": "s-1", "cwd": "/p/kuwai"})
    for extra, body in (
        ({"CURSOR_VERSION": "2.1.0"}, payload),
        ({"CURSOR_TRACE_ID": "abc"}, payload),
        ({}, json.dumps({"hook_event_name": "Stop", "session_id": "s-1", "cursor_version": "2.1.0"})),
        ({"DEVIN_PROJECT_DIR": "/p/kuwai"}, payload),
        ({"DEVIN_SESSION_ID": "d-1"}, payload),
    ):
        env = make_env(tmp_path) | extra
        assert run_hook(["--agent", "claude"], env, body).returncode == 0
        assert _rows(env) == [], extra


def test_the_native_cursor_and_devin_hooks_still_report(tmp_path: Path) -> None:
    env = make_env(tmp_path) | {"CURSOR_VERSION": "2.1.0"}
    run_hook(["--agent", "cursor", "--event", "sessionStart"], env, json.dumps({"conversation_id": "c-1"}))
    env = make_env(tmp_path) | {"DEVIN_PROJECT_DIR": "/p/kuwai"}
    run_hook(["--agent", "devin", "--event", "SessionStart"], env, json.dumps({"session_id": "d-1"}))
    assert sorted(r["agent"] for r in _rows(env)) == ["cursor", "devin"]


def test_an_agent_t3_started_is_left_to_t3(tmp_path: Path) -> None:
    env = make_env(tmp_path) | {"T3CODE_THREAD_ID": "thread-1"}
    run_hook(["--agent", "claude", "--event", "UserPromptSubmit"], env, json.dumps({"session_id": "s-2"}))
    assert _rows(env) == []



def test_a_hook_inside_kitty_records_its_pane(tmp_path: Path) -> None:
    env = make_env(tmp_path)
    env.update(KITTY_PID="4242", KITTY_WINDOW_ID="7")
    res = run_hook(["--agent", "devin"], env, json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": "s1", "cwd": "/home/user/p", "prompt": "hi"}))
    assert res.returncode == 0, res.stderr
    row = json.loads((tmp_path / "state" / "kuwai" / "desktop-agents.json").read_text())["agents"][0]
    assert row["pane"] == "w4242.7"
    env.pop("KITTY_PID")
    env.pop("KITTY_WINDOW_ID")
    run_hook(["--agent", "devin"], env, json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": "s2", "cwd": "/home/user/q", "prompt": "hi"}))
    rows = {r["id"]: r for r in json.loads((tmp_path / "state" / "kuwai" / "desktop-agents.json").read_text())["agents"]}
    assert [r["pane"] for k, r in rows.items() if r["cwd"] == "/home/user/q"] == [""]
