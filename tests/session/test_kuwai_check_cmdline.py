"""kuwai-check reads each child's command line after pgrep listed it; a child that exits in
between is skipped quietly, not reported as 'No such file or directory'."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_a_child_gone_before_its_cmdline_is_read_says_nothing():
    lines = [l.strip() for l in (ROOT / "bin/kuwai-check").read_text().splitlines()
             if re.match(r"\s*cmd=\$\(.*/proc/\$c/cmdline", l)]
    assert len(lines) == 1, lines
    r = subprocess.run(["bash", "-c", f"set -u; c=2147483647; {lines[0]}; printf '[%s]' \"$cmd\""],
                       capture_output=True, text=True, timeout=10)
    assert r.stderr == "" and r.stdout == "[]", r.stderr
