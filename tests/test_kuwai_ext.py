"""kuwai-ext: launcher providers you register, capsules any script can raise; both bounded."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / "bin/kuwai-ext"


def run(env, *args):
    return subprocess.run([str(EXT), *args], env=env, capture_output=True, text=True, timeout=20)


def world(tmp_path):
    env = {**os.environ, "HOME": str(tmp_path), "XDG_CONFIG_HOME": str(tmp_path / "config"), "XDG_RUNTIME_DIR": str(tmp_path / "run")}
    prov = tmp_path / "config/kuwai/providers"
    prov.mkdir(parents=True)
    tool = tmp_path / "search"
    tool.write_text("#!/bin/sh\nfor i in $(seq 1 30); do printf '{\"title\": \"%s %s\", \"url\": \"https://example.invalid/%s\"}\\n' \"$1\" $i $i; done\n"
                    "echo '{\"title\": \"bad url\", \"url\": \"javascript:alert(1)\"}'\n")
    tool.chmod(0o755)
    (prov / "web.json").write_text(json.dumps({"prefix": "w", "title": "Web", "command": [str(tool)]}))
    return env, prov, tool


def test_a_provider_answers_bounded_and_checked(tmp_path):
    env, prov, tool = world(tmp_path)
    assert json.loads(run(env, "providers").stdout) == [{"name": "web", "prefix": "w", "title": "Web", "glyph": ""}]
    rows = json.loads(run(env, "query", "web", "cats").stdout)
    assert len(rows) == 20 and rows[0] == {"title": "cats 1", "sub": "", "glyph": "", "url": "https://example.invalid/1"}


def test_a_provider_others_could_change_is_not_loaded(tmp_path):
    env, prov, tool = world(tmp_path)
    tool.chmod(0o777)
    assert json.loads(run(env, "providers").stdout) == []
    tool.chmod(0o755)
    (prov / "web.json").write_text(json.dumps({"prefix": "w", "command": ["relative-tool"]}))
    assert json.loads(run(env, "providers").stdout) == []


def test_capsules_are_bounded_private_and_expire(tmp_path):
    env, _, _ = world(tmp_path)
    assert run(env, "capsule", "set", "deploy", "--text", "Deploy 3/5", "--tone", "green", "--run", "notify-send", "hi").returncode == 0
    caps = json.loads(run(env, "capsule", "list").stdout)
    assert caps["deploy"]["text"] == "Deploy 3/5" and caps["deploy"]["run"] == ["notify-send", "hi"]
    f = tmp_path / "run/kuwai/capsules.json"
    assert f.stat().st_mode & 0o777 == 0o600
    assert run(env, "capsule", "set", "x", "--text", "y", "--url", "javascript:1").returncode == 2
    for i in range(10):
        run(env, "capsule", "set", f"c{i}", "--text", str(i))
    assert len(json.loads(run(env, "capsule", "list").stdout)) == 8
    run(env, "capsule", "set", "brief", "--text", "gone soon", "--ttl", "5")
    data = json.loads(f.read_text())
    data["brief"]["until"] = 0
    f.write_text(json.dumps(data))
    assert "brief" not in json.loads(run(env, "capsule", "list").stdout)
    run(env, "capsule", "clear", "deploy")
    assert "deploy" not in json.loads(run(env, "capsule", "list").stdout)
