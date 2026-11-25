"""Only a pure version bump may be labelled routine; anything else needs a human look."""
import importlib.machinery
import importlib.util
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}

PKGBUILD = """pkgname=fixture
pkgver={ver}
pkgrel=1
source=("https://example.invalid/fixture-$pkgver.tar.gz")
sha256sums=('{sum}')
build() {{
  make
{check}}}
"""
SRCINFO = "pkgbase = fixture\n\tpkgver = {ver}\n\tpkgrel = 1\n"


def g(d, *a):
    return subprocess.run(["git", "-C", str(d), *a], env=GIT_ENV, capture_output=True, text=True, check=True).stdout.strip()


def commit(d, ver, sum_, check="  make check\n", extra=None):
    (d / "PKGBUILD").write_text(PKGBUILD.format(ver=ver, sum=sum_, check=check))
    (d / ".SRCINFO").write_text(SRCINFO.format(ver=ver))
    if extra:
        extra(d)
    g(d, "add", "-A")
    g(d, "commit", "-qm", ver)
    return g(d, "rev-parse", "HEAD")


@pytest.fixture
def world(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader("review_updater", str(ROOT / "bin/kuwai-update"))
    spec = importlib.util.spec_from_loader("review_updater", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    d = tmp_path / "fixture"
    d.mkdir()
    g(d, "init", "-q")
    g(d, "config", "user.email", "t@example.invalid")
    g(d, "config", "user.name", "t")
    base = commit(d, "1.0", "a" * 64)
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", "/dev/null")
    monkeypatch.setattr(m, "installed_version", lambda pkg: "1.0-1")
    state = {}
    monkeypatch.setattr(m, "clone", lambda pkg: (str(d), state["head"]))
    monkeypatch.setattr(m, "baseline", lambda d_, pkg, head: state["base"])
    state["base"] = base

    def review(head, base_override=None):
        state["head"] = head
        if base_override is not None:
            state["base"] = base_override
        return m.review("fixture")
    return d, review


def test_pure_version_bump_is_routine(world):
    d, review = world
    assert review(commit(d, "1.1", "b" * 64))["routine"] is True


def test_dropping_a_build_step_is_not_routine(world):
    d, review = world
    assert review(commit(d, "1.1", "b" * 64, check=""))["routine"] is False


def test_failed_diff_is_not_routine(world):
    d, review = world
    head = commit(d, "1.1", "b" * 64)
    assert review(head, base_override="0" * 40)["routine"] is False


def test_binary_or_mode_change_is_not_routine(world):
    d, review = world

    def blob(d_):
        (d_ / "helper.bin").write_bytes(b"\x00\x01\x02payload")
    assert review(commit(d, "1.1", "b" * 64, extra=blob))["routine"] is False

    def chmod(d_):
        os.chmod(d_ / "helper.bin", 0o755)
    assert review(commit(d, "1.2", "c" * 64, extra=chmod))["routine"] is False


def test_only_a_changed_local_entry_counts_as_installed():
    loader = importlib.machinery.SourceFileLoader("receipt_updater", str(ROOT / "bin/kuwai-update"))
    spec = importlib.util.spec_from_loader("receipt_updater", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    fp = {"version": "1.0-1", "identity": "x", "inode": 1, "mtimeNs": 1, "ctimeNs": 1}
    assert m.newly_installed(fp, dict(fp)) is False, "pacman --needed skipped it: no receipt"
    assert m.newly_installed(fp, {**fp, "identity": "y", "inode": 2}) is True
    assert m.newly_installed(None, fp) is True
    assert m.newly_installed(fp, None) is False


def test_a_number_inside_a_command_is_not_a_version_bump(world):
    d, review = world
    first = commit(d, "1.1", "b" * 64, check="  sleep 1\n")
    second = commit(d, "1.2", "c" * 64, check="  sleep 900\n")
    assert review(second, base_override=first)["routine"] is False


def test_reordered_commands_are_not_routine(world):
    d, review = world
    first = commit(d, "1.1", "b" * 64, check="  make a\n  make b\n")
    second = commit(d, "1.2", "c" * 64, check="  make b\n  make a\n")
    assert review(second, base_override=first)["routine"] is False
    third = commit(d, "1.3", "d" * 64, check="  make b\n  make a\n")
    assert review(third, base_override=second)["routine"] is True
