"""bin/kuwai-agent-models: the model a pane runs, and how full its context is."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-agent-models"


def run(home, *args):
    env = {"PATH": os.environ.get("PATH", ""), "HOME": str(home)}
    out = subprocess.run(["python3", str(BIN), *args], env=env, capture_output=True, text=True, timeout=30, check=True)
    return json.loads(out.stdout)


def claude_log(home, cwd, used, model="claude-opus-5-5"):
    d = home / ".claude" / "projects" / cwd.replace("/", "-")
    d.mkdir(parents=True)
    rows = [
        {"type": "assistant", "message": {"model": model, "usage": {"input_tokens": 1, "cache_read_input_tokens": 10}}},
        {"type": "assistant", "isSidechain": True, "message": {"model": model, "usage": {"input_tokens": 999999}}},
        {"type": "assistant", "message": {"model": model, "usage": {"input_tokens": 2, "cache_creation_input_tokens": 1000,
                                                                   "cache_read_input_tokens": used - 1002, "output_tokens": 5}}, "effort": "high"},
        {"type": "assistant", "isSidechain": True, "message": {"model": model, "usage": {"input_tokens": 7}}},
        {"type": "assistant", "message": {"role": "assistant", "model": model, "content": [{"type": "text", "text": "All 12 tests pass."}]}},
        {"type": "assistant", "isSidechain": True, "message": {"role": "assistant", "content": [{"type": "text", "text": "a subagent"}]}},
    ]
    (d / "s.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")


def test_claude_past_200k_is_the_1m_window(tmp_path):
    claude_log(tmp_path, "/w/big", 256000)
    got = run(tmp_path, "claude:/w/big")["claude:/w/big"]
    assert got == {"model": "claude-opus-5-5", "effort": "high", "context": 256000, "window": 1000000, "reply": "All 12 tests pass.", "steps": []}


def test_claude_under_200k_window_unknown(tmp_path):
    claude_log(tmp_path, "/w/small", 150000)
    got = run(tmp_path, "claude:/w/small")["claude:/w/small"]
    assert got["context"] == 150000 and got["window"] == 0


def test_codex_says_its_window(tmp_path):
    d = tmp_path / ".codex" / "sessions" / "2026" / "11" / "22"
    d.mkdir(parents=True)
    rows = [
        {"type": "session_meta", "payload": {"cwd": "/w/x", "model": "gpt-6.1-sol", "model_context_window": 475000}},
        {"type": "event_msg", "payload": {"type": "token_count", "info": {"last_token_usage": {"input_tokens": 400000}}}},
        {"type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Done: the tooltip stays."}]}},
    ]
    (d / "r.jsonl").write_text("\n".join(json.dumps(r, separators=(",", ":")) for r in rows) + "\n")
    got = run(tmp_path, "codex:/w/x")["codex:/w/x"]
    assert got["model"] == "gpt-6.1-sol" and got["context"] == 400000 and got["window"] == 475000
    assert got["reply"] == "Done: the tooltip stays."


def test_steps_are_plain_words_without_command_lines(tmp_path):
    cwd = "/p/shop"
    d = tmp_path / ".claude" / "projects" / cwd.replace("/", "-")
    d.mkdir(parents=True)
    tool = lambda name, inp, side=False: {"type": "assistant", "isSidechain": side, "message": {"role": "assistant", "model": "claude-opus-5-5",
                                          "content": [{"type": "tool_use", "name": name, "input": inp}]}}
    rows = [
        tool("Read", {"file_path": "/p/shop/a.ts"}),
        tool("Bash", {"command": "curl -H 'Authorization: Bearer s3cret' https://x"}),
        tool("Read", {"file_path": "/p/shop/hidden.ts"}, side=True),
        tool("Edit", {"file_path": "/p/shop/src/Theme.qml", "old_string": "x", "new_string": "y"}),
        tool("Bash", {"command": "bun test", "description": "Run the shell tests"}),
        {"type": "assistant", "message": {"role": "assistant", "model": "claude-opus-5-5", "usage": {"input_tokens": 5}}},
    ]
    (d / "s.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    steps = run(tmp_path, "claude:" + cwd)["claude:" + cwd]["steps"]
    assert steps == ["Run curl", "Edit Theme.qml", "Run the shell tests"]
    assert not any("s3cret" in s for s in steps)
