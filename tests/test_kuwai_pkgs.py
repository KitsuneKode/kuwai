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
