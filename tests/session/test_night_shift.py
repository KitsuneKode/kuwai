"""Night Shift's switch works when the schedule is off: it starts hyprsunset itself.

The switch spoke to hyprsunset over hyprctl, but only the night_light schedule
started the daemon; with the schedule off the switch did nothing and said it
was on. Now a warm setting starts hyprsunset.service and retries, and a failure
puts the switch back to off.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "shell/services/Display.qml").read_text()


def script():
    m = re.search(r"warm\.command = \[\"sh\", \"-c\", ('[^']*'\s*\+\s*'[^']*')", SRC)
    assert m, "the warm command is a script with the temperature as an argument"
    return "".join(re.findall(r"'([^']*)'", m.group(1)))


def run(tmp_path, daemon_starts):
    bin_ = tmp_path / "bin"
    bin_.mkdir(exist_ok=True)
    sock = tmp_path / "up"
    log = tmp_path / "log"
    (bin_ / "hyprctl").write_text(f'#!/bin/sh\necho "hyprctl $*" >> {log}\n[ -e {sock} ]\n')
    (bin_ / "systemctl").write_text(f'#!/bin/sh\necho "systemctl $*" >> {log}\n' + (f"touch {sock}\n" if daemon_starts else "exit 1\n"))
    (bin_ / "sleep").write_text("#!/bin/sh\n")
    for f in bin_.iterdir():
        f.chmod(0o755)
    r = subprocess.run(["sh", "-c", script(), "sh", "4200"], env={"PATH": f"{bin_}:/usr/bin:/bin"}, timeout=20)
    return r.returncode, log.read_text()


def test_it_starts_hyprsunset_when_it_isnt_running(tmp_path):
    rc, log = run(tmp_path, daemon_starts=True)
    assert rc == 0
    assert "systemctl --user start hyprsunset.service" in log
    assert log.strip().splitlines()[-1] == "hyprctl hyprsunset temperature 4200"


def test_a_failure_is_reported_so_the_switch_goes_back_to_off(tmp_path):
    rc, _ = run(tmp_path, daemon_starts=False)
    assert rc != 0
    assert "onExited: code => { if (code !== 0) root.temperature = 6500; }" in SRC
