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
    rows = m.listening(text)
    assert rows == [{"port": 3000, "proc": "node", "project": "shop", "pid": 101, "local": True}]
