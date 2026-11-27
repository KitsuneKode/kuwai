"""The fresh-install test's scripts: they parse, say what they are, refuse to run
where they would do harm, and never reach into the owner's home.

The test itself needs docker or qemu and a long run (tests/fresh/README.md);
this is the part that runs everywhere.
"""
import os
import re
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ["run.sh", "inside.sh", "vm.sh"]


def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=30, **kw)


@pytest.mark.parametrize("name", SCRIPTS)
def test_bash_syntax(name):
    r = run("bash", "-n", os.path.join(HERE, name))
    assert r.returncode == 0, r.stderr


@pytest.mark.parametrize("name", SCRIPTS)
def test_help_exits_zero(name):
    r = run("bash", os.path.join(HERE, name), "--help")
    assert r.returncode == 0, r.stderr
    assert name in r.stdout


def test_inside_refuses_a_normal_machine():
    if os.geteuid() == 0 or os.path.exists("/.dockerenv"):
        pytest.skip("only meaningful as an ordinary user outside a container")
    r = run("bash", os.path.join(HERE, "inside.sh"), "/nonexistent")
    assert r.returncode == 2
    assert "run as root" in r.stderr


@pytest.mark.parametrize("name", SCRIPTS)
def test_host_scripts_never_name_the_owners_state(name):
    if name == "inside.sh":
        pytest.skip("runs in the container, where HOME is the test user's")
    text = open(os.path.join(HERE, name)).read()
    code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    for bad in ("~/.config", "~/.local/share/kuwai", "$HOME/.config", "$HOME/.local", "/run/user/$(id -u)"):
        assert bad not in code, f"{name} reaches into {bad}"


def _code(name):
    text = open(os.path.join(HERE, name)).read()
    return re.sub(r"<<'KUWAI_USAGE'.*?\nKUWAI_USAGE\n", "", text, flags=re.S)


@pytest.mark.parametrize("name,allowed", [
    ("run.sh", ("$VOL:", "/var/cache/pacman/pkg:/hostcache:ro")),
    ("vm.sh", ("kuwai-fresh-pkgcache:", "/var/cache/pacman/pkg:/hostcache:ro", "$CACHE:/w")),
])
def test_docker_gets_only_the_package_cache(name, allowed):
    text = _code(name)
    for m in re.findall(r'(?<!command)\s(?:-v|--volume)\s+"?([^\s"]+)', text):
        assert m.startswith(allowed), f"{name}: unexpected mount {m}"
    assert "--privileged" not in text
