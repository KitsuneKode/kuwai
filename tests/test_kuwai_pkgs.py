import importlib.machinery
import importlib.util
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def module():
    loader = importlib.machinery.SourceFileLoader("pkgs_fixture", str(ROOT / "bin/kuwai-pkgs"))
    spec = importlib.util.spec_from_loader("pkgs_fixture", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def test_search_reads_pacman_and_marks_installed(monkeypatch):
    m = module()
    out = {("pacman", "-Qq"): "ripgrep\n",
           ("pacman", "-Ss", "--", "rip"): "extra/ripgrep 14.1-1 [installed]\n    Fast grep\nextra/ripgrep-all 0.10-1\n    rg in pdfs\n"}
    monkeypatch.setattr(m, "run", lambda cmd, timeout=6: out.get(tuple(cmd), ""))
    monkeypatch.setattr(m, "aur_search", lambda q, have: [{"name": "ripgrep-git", "repo": "aur", "version": "1", "desc": "", "installed": False, "aur": True},
                                                          {"name": "ripgrep", "repo": "aur", "version": "1", "desc": "", "installed": True, "aur": True}])
    rows = m.search("rip")
    assert [(r["name"], r["repo"], r["installed"]) for r in rows] == [("ripgrep", "extra", True), ("ripgrep-all", "extra", False), ("ripgrep-git", "aur", False)]
    assert m.search("x") == [] and m.search("a;b") == []


def test_install_runs_in_a_terminal_you_can_see(tmp_path):
    log = tmp_path / "argv.json"
    term = tmp_path / "kitty"
    term.write_text(f"#!/usr/bin/python3\nimport json,sys\nopen({str(log)!r},'w').write(json.dumps(sys.argv[1:]))\n")
    term.chmod(0o755)
    env = dict(os.environ, KUWAI_TERMINAL=str(term), PATH=f"{tmp_path}:{os.environ['PATH']}")
    r = subprocess.run([str(ROOT / "bin/kuwai-pkgs"), "install", "ripgrep"], env=env, capture_output=True, text=True, timeout=20)
    assert json.loads(r.stdout)["ok"] is True
    for _ in range(50):
        if log.exists():
            break
        subprocess.run(["sleep", "0.05"])
    argv = json.loads(log.read_text())
    assert argv[-1].count("sudo pacman -S --needed -- ripgrep") == 2
    bad = subprocess.run([str(ROOT / "bin/kuwai-pkgs"), "remove", "x;rm -rf ~"], env=env, capture_output=True, text=True)
    assert bad.returncode == 2


QEI = """Name            : zsh
Version         : 5.9.1-1
Description     : A very advanced and programmable command interpreter (shell) for UNIX
Architecture    : x86_64
URL             : https://www.zsh.org/
Licenses        : custom
Depends On      : pcre2  libcap  gdbm>=1.20
Required By     : None
Installed Size  : 8.00 MiB
Install Date    : Tuesday 10 November 2026 07:37:56 PM
Install Reason  : Explicitly installed

Name            : paru
Version         : 2.1.0-1
Description     : Feature packed AUR helper
URL             : None
Licenses        : GPL-3.0-or-later
Depends On      : git  pacman
Optional Deps   : bat: colored pkgbuild printing
                  devtools: build in chroot
Required By     : kuwai-meta
Installed Size  : 9.50 MiB
Install Date    : Monday 09 November 2026 10:00:00 AM

Name            : -Rf
Version         : 1-1
"""


def test_your_packages_with_details_and_holds(monkeypatch, tmp_path):
    m = module()
    out = {("pacman", "-Qei"): QEI, ("pacman", "-Qqm"): "paru\n"}
    monkeypatch.setattr(m, "run", lambda cmd, timeout=6: out.get(tuple(cmd), ""))
    (tmp_path / "kuwai").mkdir()
    (tmp_path / "kuwai" / "held.json").write_text(json.dumps({"zsh": {"version": "5.9.1-1", "at": 1}}))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    rows = {r["name"]: r for r in m.installed_list()}
    assert sorted(rows) == ["paru", "zsh"], "a name that isn't a package name is never listed"
    z, p = rows["zsh"], rows["paru"]
    assert z["size"] == 8 * 1024 * 1024 and z["depends"] == ["pcre2", "libcap", "gdbm"] and z["requiredBy"] == []
    assert z["held"] is True and z["heldAt"] == "5.9.1-1" and z["aur"] is False and z["url"] == "https://www.zsh.org/"
    assert p["aur"] is True and p["held"] is False and p["url"] == "" and p["requiredBy"] == ["kuwai-meta"]
