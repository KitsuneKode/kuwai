"""The shell's long-running children kuwai-check should not call strays."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def pattern():
    m = re.search(r"^expected='(.*)'$", (ROOT / "bin/kuwai-check").read_text(), re.M)
    assert m, "kuwai-check's expected-helper pattern"
    return m.group(1)


def matches(cmd):
    return subprocess.run(["grep", "-qE", pattern()], input=cmd, text=True).returncode == 0


def test_the_lock_osd_brightness_watcher_is_expected():
    assert matches("/usr/bin/python3 /home/u/.local/share/kuwai/lib/brightness/brightness-client.py watch --part osd ")


def test_other_brightness_watchers_are_still_strays():
    assert not matches("/usr/bin/python3 /home/u/.local/share/kuwai/lib/brightness/brightness-client.py watch --part waybar ")
    assert not matches("/usr/bin/python3 /home/u/.local/share/kuwai/lib/brightness/brightness-client.py watch --part osd2 ")
    assert not matches("/usr/bin/python3 /home/u/.local/share/kuwai/lib/brightness/brightness-client.py watch --part osd extra ")
    assert not matches("/usr/bin/python3 /home/u/.local/share/kuwai/lib/brightness/brightness-client.py watch ")
