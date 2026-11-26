"""kuwai-spend counts every Claude and Codex account home, each session once."""
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def line(mid, tokens):
    return json.dumps({"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "requestId": "r" + mid,
                       "message": {"id": mid, "model": "claude-opus-5-5", "usage": {"input_tokens": tokens, "output_tokens": 0}}}) + "\n"


def test_every_claude_home_is_counted(tmp_path):
    for home, mid, n in ((".claude", "m1", 100), (".claude_personal", "m2", 1000)):
        d = tmp_path / home / "projects/p"
        d.mkdir(parents=True)
        (d / "s.jsonl").write_text(line(mid, n))
    (tmp_path / ".codex-shadow").mkdir()
    (tmp_path / ".codex").mkdir()
    (tmp_path / ".codex/sessions").mkdir()
    (tmp_path / ".codex-shadow/sessions").symlink_to(tmp_path / ".codex/sessions")
    env = dict(os.environ, HOME=str(tmp_path), XDG_CACHE_HOME=str(tmp_path / "cache"))
    env.pop("CLAUDE_CONFIG_DIR", None)
    env.pop("CODEX_HOME", None)
    r = subprocess.run(["node", str(ROOT / "bin/kuwai-spend")], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout.splitlines()[0])
    assert out["providers"]["claude"]["today"]["tokens"] == 1100


def test_each_log_keeps_its_session_and_days(tmp_path):
    """So the Spend view can leave out what T3 Code ran (its records count those) and keep the rest."""
    sid = "0a1b2c3d-0000-4000-8000-000000000001"
    d = tmp_path / ".claude" / "projects/p"
    (d / sid / "subagents").mkdir(parents=True)
    (d / f"{sid}.jsonl").write_text(line("m1", 100))
    (d / sid / "subagents" / "agent-1.jsonl").write_text(line("m2", 50))
    env = dict(os.environ, HOME=str(tmp_path), XDG_CACHE_HOME=str(tmp_path / "cache"))
    env.pop("CLAUDE_CONFIG_DIR", None)
    env.pop("CODEX_HOME", None)
    r = subprocess.run(["node", str(ROOT / "bin/kuwai-spend")], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    state = json.loads((tmp_path / "cache/kuwai/spend.json").read_text())
    assert state["version"] == 2
    files = [f for f in state["files"].values() if f.get("days")]
    assert sorted(f["sid"] for f in files) == [sid, sid]
    assert {f["provider"] for f in files} == {"claude"}
    assert sum(sum(day["tokens"] for day in f["days"].values()) for f in files) == 150
