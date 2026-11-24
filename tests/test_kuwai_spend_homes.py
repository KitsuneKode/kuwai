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
