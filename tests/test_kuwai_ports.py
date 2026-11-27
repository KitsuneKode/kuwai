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


def stat_text(pid, name, ppid, start):
    rest = ["S", str(ppid)] + ["0"] * 17 + [str(start), "0", "0"]
    return f"{pid} ({name}) " + " ".join(rest) + "\n"


def process(proc, pid, name, ppid, start, cmd, cwd):
    p = proc / str(pid)
    (p / "fd").mkdir(parents=True)
    (p / "stat").write_text(stat_text(pid, name, ppid, start))
    (p / "cmdline").write_bytes(b"\0".join(str(x).encode() for x in cmd) + b"\0")
    (p / "cwd").symlink_to(cwd)
    return p


def sock(proc, pid, fd, inode):
    (proc / str(pid) / "fd" / str(fd)).symlink_to(f"socket:[{inode}]")


def tcp_line(local, port, inode, state="0A", remote="00000000:0000"):
    return (f"  0: {local}:{port:04X} {remote} {state} 00000000:00000000 00:00000000 00000000 "
            f"1000 0 {inode} 1 0000000000000000 100 0 0 10 0")


def net(proc, family, rows):
    (proc / "net").mkdir(parents=True, exist_ok=True)
    (proc / "net" / family).write_text("  sl  local_address rem_address st\n" + "\n".join(rows) + "\n")


def test_proc_socket_inodes_name_the_owner_without_ss(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    web = proj / "web"
    web.mkdir()
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("150 0\n")
    process(proc, 77, "codex", 1, 1000, ["codex"], tmp_path)
    node = process(proc, 101, "node", 77, 5000, ["node", "/shop/node_modules/next/dist/bin/next", "dev"], web)
    sock(proc, 101, 25, 111)
    sock(proc, 101, 26, 112)
    process(proc, 202, "caddy", 1, 6000, ["caddy"], Path("/"))
    sock(proc, 202, 5, 222)
    process(proc, 303, "t3code", 1, 7000, ["t3code"], web)
    sock(proc, 303, 7, 333)
    locked = proc / "404" / "fd"
    locked.mkdir(parents=True)
    locked.chmod(0)
    assert node.name == "101"
    net(proc, "tcp", [
        tcp_line("0100007F", 3000, 111),
        tcp_line("00000000", 8080, 222),
        tcp_line("0100007F", 3773, 333),
    ])
    net(proc, "tcp6", [tcp_line("00000000000000000000000001000000", 3000, 112, remote="0" * 32 + ":0000")])

    rows = m.scan(str(proc))
    assert rows == [
        {"port": 3000, "proc": "node", "what": "next dev", "project": "shop", "pid": 101, "start": 5000,
         "age": 100, "agent": "Codex", "local": True}
    ]
    assert m.ipv6("00000000000000000000000001000000") == "::1"


def test_a_wildcard_listener_is_reachable_beyond_localhost(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proj = tmp_path / "site"
    (proj / ".git").mkdir(parents=True)
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("100 0\n")
    process(proc, 101, "python3", 1, 1000, ["python3", "-m", "http.server", "8080"], proj)
    sock(proc, 101, 3, 222)
    net(proc, "tcp", [tcp_line("00000000", 8080, 222)])
    net(proc, "tcp6", [])
    rows = m.scan(str(proc))
    assert len(rows) == 1 and rows[0]["port"] == 8080 and rows[0]["local"] is False


def test_the_implementation_never_calls_ss(tmp_path):
    source = (ROOT / "bin/kuwai-ports").read_text()
    assert "subprocess" not in source
    assert '"ss"' not in source and "'ss'" not in source


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
        mine = []
        for _ in range(50):
            rows = json.loads(subprocess.run([str(ROOT / "bin/kuwai-ports")], capture_output=True, text=True,
                                             env=dict(os.environ, HOME=str(tmp_path))).stdout)
            mine = [r for r in rows if r["port"] == port]
            if mine:
                break
            time.sleep(0.1)
        assert mine and mine[0]["what"] == "python http.server" and mine[0]["agent"] == "Codex"
        assert mine[0]["project"] == "shop" and mine[0]["start"] > 0 and mine[0]["age"] >= 0
        assert mine[0]["local"] is True
    finally:
        p.terminate()
        subprocess.run(["pkill", "-f", "http.server " + str(port)])
