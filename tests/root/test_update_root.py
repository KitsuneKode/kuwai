"""bin/rice-update-root: hostile requests are refused before anything is touched.

Runs without root: every case here must raise ValueError in validation, so
no file is read, changed or removed.
"""
import importlib.machinery
import importlib.util
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def ur():
    loader = importlib.machinery.SourceFileLoader("rice_update_root", str(ROOT / "bin" / "rice-update-root"))
    spec = importlib.util.spec_from_loader("rice_update_root", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("item", [
    {"path": "/etc/pacman.conf", "action": "delete"},          # unknown action
    {"path": "/etc/pacman.conf", "action": None},
    {"path": "etc/pacman.conf", "action": "keep"},             # relative
    {"path": "/home/x/.bashrc", "action": "take"},             # outside /etc
    {"path": "/etc/../root/.ssh/authorized_keys", "action": "take"},
    {"path": "/etc/./pacman.conf", "action": "take"},
    {"path": "/etc//pacman.conf", "action": "take"},
    {"path": "/etc/pacman.conf\0x", "action": "take"},
    {"path": ["/etc/pacman.conf"], "action": "take"},          # not a string
    {"path": 42, "action": "keep"},
    {"path": "/etc/rice-no-such-file-for-tests", "action": "keep"},   # no .pacnew
])
def test_pacnew_refuses(ur, item):
    with pytest.raises((ValueError, FileNotFoundError)):
        ur.pacnew({"items": [item]})


def test_pacnew_needs_items(ur):
    for req in ({}, {"items": []}, {"items": "nope"}):
        with pytest.raises(ValueError):
            ur.pacnew(req)


@pytest.fixture
def etc(ur, tmp_path, monkeypatch):
    """A stand-in /etc (resolved, so its own path has no link in it)."""
    d = tmp_path.resolve() / "etc"
    d.mkdir()
    monkeypatch.setattr(ur, "ETC", str(d) + "/")
    elsewhere = tmp_path.resolve() / "elsewhere"
    elsewhere.mkdir()
    (elsewhere / "shadow").write_text("target")
    (elsewhere / "shadow.pacnew").write_text("planted")
    return d, elsewhere


@pytest.mark.parametrize("plant", ["pacnew", "parent"])
def test_pacnew_refuses_a_symlink_in_the_way(ur, etc, plant):
    d, elsewhere = etc
    if plant == "pacnew":                                     # X.pacnew is a link to another file
        (d / "app.conf").write_text("yours")
        (d / "app.conf.pacnew").symlink_to(elsewhere / "shadow.pacnew")
        path = d / "app.conf"
    else:                                                     # a folder on the way is a link
        (d / "linked").symlink_to(elsewhere, target_is_directory=True)
        path = d / "linked" / "shadow"
    with pytest.raises(ValueError, match="symlink in the way"):
        ur.pacnew({"items": [{"path": str(path), "action": "take"}]})
    assert (elsewhere / "shadow").read_text() == "target"
    assert (elsewhere / "shadow.pacnew").read_text() == "planted"


def test_pacnew_refuses_a_linked_target(ur, etc, monkeypatch):
    d, elsewhere = etc
    (d / "app.conf").symlink_to(elsewhere / "shadow")
    (d / "app.conf.pacnew").write_text("new default")
    monkeypatch.setattr(ur.os, "lstat", lambda p, _real=os.lstat: _as_root(_real(p)) if str(p).endswith(".pacnew") else _real(p))
    with pytest.raises(ValueError, match="not a regular file"):
        ur.pacnew({"items": [{"path": str(d / "app.conf"), "action": "take"}]})
    assert (elsewhere / "shadow").read_text() == "target"


def _as_root(st):
    """An lstat result as if root owned the file (the tests don't run as root)."""
    return os.stat_result((st.st_mode, st.st_ino, st.st_dev, st.st_nlink, 0, 0, st.st_size,
                           int(st.st_atime), int(st.st_mtime), int(st.st_ctime)))


@pytest.mark.parametrize("deps", [["linux; rm -rf /"], ["-Syu"], ["../x"], [""], "linux", [1]])
def test_names_refuses(ur, deps):
    with pytest.raises(ValueError):
        ur.names({"deps": deps})


def test_names_accepts(ur):
    assert ur.names({"deps": ["linux", "lib32-glibc", "python-pip", "qt6-base"]}) == ["linux", "lib32-glibc", "python-pip", "qt6-base"]


def test_files_only_your_package_files(ur, tmp_path):
    home = str(tmp_path)
    uid = os.getuid()
    pkg = tmp_path / "foo-1.0-1-x86_64.pkg.tar.zst"
    pkg.write_bytes(b"x")
    assert ur.files({"files": [str(pkg)]}, home, uid) == [str(pkg)]
    other = tmp_path / "notes.txt"
    other.write_text("x")
    link = tmp_path / "bar-1.0-1-x86_64.pkg.tar.zst"
    link.symlink_to(pkg)
    for bad in ([str(other)], [str(link)], ["/etc/passwd"], [str(pkg) + "/../notes.txt"], []):
        with pytest.raises((ValueError, FileNotFoundError, NotADirectoryError)):
            ur.files({"files": bad}, home, uid)
    with pytest.raises(ValueError):            # someone else's file
        ur.files({"files": [str(pkg)]}, home, uid + 1)
