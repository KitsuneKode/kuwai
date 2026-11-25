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
