"""kuwai-procs --end signals only the process that was listed, not a newer one with its number."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCS = ROOT / "bin/kuwai-procs"


def start_of(pid):
    st = Path(f"/proc/{pid}/stat").read_text()
    return int(st[st.rindex(")") + 2:].split()[19])


def end(*args):
    r = subprocess.run([str(PROCS), "--end", *args], capture_output=True, text=True, timeout=10)
    return json.loads(r.stdout)


def test_a_reused_number_is_refused_and_the_listed_one_ends():
    p = subprocess.Popen(["sleep", "30"])
    try:
        st = start_of(p.pid)
        out = end(str(p.pid), "--start", str(st + 1))
        assert out["ok"] is False and "another one" in out["why"]
        assert p.poll() is None, "the newer process is left alone"
        assert end(str(p.pid), "--start", str(st))["ok"] is True
        assert p.wait(timeout=5) != 0
    finally:
        p.kill()


def test_session_processes_are_never_ended(tmp_path):
    fake = tmp_path / "pipewire"
    fake.write_bytes(Path("/usr/bin/sleep").read_bytes())
    fake.chmod(0o755)
    p = subprocess.Popen([str(fake), "30"])
    try:
        out = end(str(p.pid), "--force")
        assert out["ok"] is False and "session" in out["why"]
        assert p.poll() is None
        rows = json.loads(subprocess.run([str(PROCS), "pipewire"], capture_output=True, text=True, timeout=10).stdout)
        assert any(r["pid"] == p.pid and r["protected"] for r in rows), "the launcher is told, so it doesn't offer End"
    finally:
        p.kill()


def test_a_process_that_ignores_the_request_is_reported_as_still_running():
    p = subprocess.Popen(["sh", "-c", 'trap "" TERM; sleep 30'])
    try:
        out = end(str(p.pid))
        assert out == {"ok": True, "gone": False, "why": "it's still running; force quit ends it"}
        assert p.poll() is None
        assert end(str(p.pid), "--force") == {"ok": True, "gone": True}
    finally:
        p.kill()


def test_the_launcher_that_asked_is_never_ended():
    out = subprocess.run(["sh", "-c", f'"{PROCS}" --end $$'], capture_output=True, text=True, timeout=10)
    assert json.loads(out.stdout) == {"ok": False, "why": "it runs this launcher"}
