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


def stat_text(pid, name, ppid, start, ticks=0, rss_pages=0):
    rest = ["S", str(ppid)] + ["0"] * 20
    rest[11] = str(ticks)
    rest[19] = str(start)
    rest[21] = str(rss_pages)
    return f"{pid} ({name}) " + " ".join(rest) + "\n"


def process(proc, pid, name, ppid, start, cmd, cwd, ticks=0, rss_pages=0):
    p = proc / str(pid)
    (p / "fd").mkdir(parents=True)
    (p / "stat").write_text(stat_text(pid, name, ppid, start, ticks, rss_pages))
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
         "age": 100, "agent": "Codex", "parentApp": "", "memBytes": 0, "host": "127.0.0.1", "local": True, "cpu": 0.0}
    ]
    assert m.ipv6("00000000000000000000000001000000") == "::1"


def test_daemon_allowlist_keeps_listeners_outside_home(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("100 0\n")
    for pid, name, cmd in [(501, "postgres", ["postgres"]), (502, "redis-server", ["redis-server"]), (503, "docker-proxy", ["docker-proxy"])]:
        process(proc, pid, name, 1, 1000, [cmd[0]], Path("/var/lib") / name)
        sock(proc, pid, 3, 700 + pid)
    net(proc, "tcp", [
        tcp_line("0100007F", 5432, 1201),
        tcp_line("0100007F", 6379, 1202),
        tcp_line("00000000", 8081, 1203),
    ])
    net(proc, "tcp6", [])
    rows = m.scan(str(proc))
    assert [(r["port"], r["proc"], r["host"]) for r in rows] == [(5432, "postgres", "127.0.0.1"), (6379, "redis-server", "127.0.0.1"), (8081, "docker-proxy", "0.0.0.0")]


def test_pss_is_proportional_memory_and_rss_is_the_fallback(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("100 0\n")
    process(proc, 101, "node", 1, 1000, ["node", "server.js"], proj, rss_pages=512)
    (proc / "101" / "smaps_rollup").write_text("Rss: 4096 kB\nPss: 2048 kB\n")
    sock(proc, 101, 3, 111)
    process(proc, 102, "node", 1, 1000, ["node", "worker.js"], proj, rss_pages=512)
    sock(proc, 102, 3, 112)
    net(proc, "tcp", [tcp_line("0100007F", 3000, 111), tcp_line("0100007F", 3001, 112)])
    net(proc, "tcp6", [])
    rows = m.scan(str(proc))
    assert rows[0]["memBytes"] == 2048 * 1024
    assert rows[1]["memBytes"] == 512 * m.PAGE


def test_parent_app_names_the_terminal_the_server_runs_inside(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("100 0\n")
    process(proc, 77, "kitty", 1, 500, ["kitty"], tmp_path)
    process(proc, 101, "node", 77, 1000, ["node", "server.js"], proj)
    sock(proc, 101, 3, 111)
    net(proc, "tcp", [tcp_line("0100007F", 3000, 111)])
    net(proc, "tcp6", [])
    rows = m.scan(str(proc))
    assert rows[0]["parentApp"] == "Kitty"


def test_parent_app_falls_back_to_the_gui_scope_without_its_instance_number(tmp_path, monkeypatch):
    m = module()
    monkeypatch.setattr(m, "HOME", str(tmp_path))
    proj = tmp_path / "shop"
    (proj / ".git").mkdir(parents=True)
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("100 0\n")
    process(proc, 101, "node", 1, 1000, ["node", "server.js"], proj)
    (proc / "101" / "cgroup").write_text("0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-com.t3tools.T3Code-7010.scope\n")
    sock(proc, 101, 3, 111)
    net(proc, "tcp", [tcp_line("0100007F", 3000, 111)])
    net(proc, "tcp6", [])
    rows = m.scan(str(proc))
    assert rows[0]["parentApp"] == "T3Code"


def test_cpu_comes_from_proc_samples_without_a_blocking_sleep(tmp_path):
    source = (ROOT / "bin/kuwai-ports").read_text()
    assert "time.sleep" not in source


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
