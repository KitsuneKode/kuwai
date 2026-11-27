import importlib.machinery
import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def module():
    loader = importlib.machinery.SourceFileLoader("ports_fixture", str(ROOT / "bin/kuwai-ports"))
    spec = importlib.util.spec_from_loader("ports_fixture", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def test_only_servers_working_in_your_folders(tmp_path, monkeypatch):
    m = module()
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    (proj / "web").mkdir()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    monkeypatch.setattr(m.os, "readlink", lambda p: str(proj / "web") if p == "/proc/101/cwd" else "/")
    text = "\n".join([
        'LISTEN 0 511 127.0.0.1:3000 0.0.0.0:* users:(("node-MainThread",pid=101,fd=25))',
        'LISTEN 0 511 [::1]:3000 [::]:* users:(("node-MainThread",pid=101,fd=26))',
        'LISTEN 0 511 127.0.0.1:3773 0.0.0.0:* users:(("t3code",pid=101,fd=45))',
        'LISTEN 0 511 0.0.0.0:8080 0.0.0.0:* users:(("caddy",pid=202,fd=5))',
        'LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*',
    ])
    monkeypatch.setattr(m, "stat", lambda pid: ("node", 1, 5000))
    monkeypatch.setattr(m, "argv", lambda pid: ["node", "/shop/node_modules/next/dist/bin/next", "dev"])
    monkeypatch.setattr(m, "uptime", lambda: 150.0)
    monkeypatch.setattr(m, "agent", lambda pid: "Codex")
    rows = m.listening(text)
    assert rows == [{"port": 3000, "proc": "node", "what": "next dev", "project": "shop", "pid": 101, "start": 5000,
                     "age": 100, "agent": "Codex", "local": True}]


def test_a_real_server_names_itself_and_the_agent_that_started_it(tmp_path):
    import json, socket, subprocess, time
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    codex = tmp_path / "codex"
    codex.write_text('#!/bin/sh\ncd "$1" && python3 -m http.server "$2" --bind 127.0.0.1 >/dev/null 2>&1\n')
    codex.chmod(0o755)
    p = subprocess.Popen([str(codex), str(proj), str(port)])
    try:
        for _ in range(50):
            rows = json.loads(subprocess.run([str(ROOT / "bin/kuwai-ports")], capture_output=True, text=True,
                                             env=dict(os.environ, HOME=str(tmp_path))).stdout)
            mine = [r for r in rows if r["port"] == port]
            if mine:
                break
            time.sleep(0.1)
        assert mine and mine[0]["what"] == "python http.server" and mine[0]["agent"] == "Codex"
        assert mine[0]["project"] == "shop" and mine[0]["start"] > 0 and mine[0]["age"] >= 0
    finally:
        p.terminate()
        subprocess.run(["pkill", "-f", "http.server " + str(port)])
