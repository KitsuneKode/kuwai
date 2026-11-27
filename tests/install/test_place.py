"""install.sh's place: a backup or write that fails stops the install instead of carrying on."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def body(name):
    src = (ROOT / "install.sh").read_text()
    m = re.search(r"^%s\(\) \{.*?^\}" % re.escape(name), src, re.S | re.M)
    return m.group(0)


def run(tmp_path, orig):
    dst = tmp_path / "hyprland.lua"
    dst.write_text("yours\n")
    src = tmp_path / "new.lua"
    src.write_text("kuwai's\n")
    script = "\n".join([
        "set -euo pipefail", "DRY=0",
        "warn() { echo \"warn $*\"; }", "ok() { echo \"ok $*\"; }",
        orig,
        "remember()  { ORIG remember \"$1\"; }", "installed() { ORIG installed \"$1\"; }",
        body("stage"), "stop_install() { printf '  ✗ %s\\n' \"$*\" >&2; exit 1; }", body("place"),
        f'if place "{src}" "{dst}"; then ok placed; fi', "echo carried-on",
    ])
    p = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=10)
    return p, dst.read_text()


def test_a_failed_backup_stops_before_anything_is_replaced(tmp_path):
    p, now = run(tmp_path, 'ORIG() { case $1 in remember) return 1 ;; edited) return 1 ;; *) return 0 ;; esac; }')
    assert p.returncode == 1
    assert "carried-on" not in p.stdout
    assert "back up" in p.stderr
    assert now == "yours\n"


def test_a_kept_edit_is_not_a_failure(tmp_path):
    p, now = run(tmp_path, 'ORIG() { case $1 in edited) return 0 ;; *) return 0 ;; esac; }')
    assert p.returncode == 0 and "carried-on" in p.stdout
    assert now == "yours\n" and (tmp_path / "hyprland.lua.kuwai-new").read_text() == "kuwai's\n"


def test_the_normal_path_installs(tmp_path):
    p, now = run(tmp_path, 'ORIG() { case $1 in edited) return 1 ;; *) return 0 ;; esac; }')
    assert p.returncode == 0 and "ok placed" in p.stdout and now == "kuwai's\n"
