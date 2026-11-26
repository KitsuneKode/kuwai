"""bin/kuwai-update-root: hostile requests are refused before anything is touched.

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
    loader = importlib.machinery.SourceFileLoader("kuwai_update_root", str(ROOT / "bin" / "kuwai-update-root"))
    spec = importlib.util.spec_from_loader("kuwai_update_root", loader)
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
    {"path": "/etc/kuwai-no-such-file-for-tests", "action": "keep"},   # no .pacnew
])
def test_pacnew_refuses(ur, item):
    with pytest.raises((ValueError, FileNotFoundError)):
        ur.pacnew_one(item.get("path"), item.get("action"))


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
        ur.pacnew_one(str(path), "take")
    assert (elsewhere / "shadow").read_text() == "target"
    assert (elsewhere / "shadow.pacnew").read_text() == "planted"


def test_pacnew_refuses_a_linked_target(ur, etc, monkeypatch):
    d, elsewhere = etc
    (d / "app.conf").symlink_to(elsewhere / "shadow")
    (d / "app.conf.pacnew").write_text("new default")
    monkeypatch.setattr(ur.os, "lstat", lambda p, _real=os.lstat: _as_root(_real(p)) if str(p).endswith(".pacnew") else _real(p))
    with pytest.raises(ValueError, match="not a regular file"):
        ur.pacnew_one(str(d / "app.conf"), "take")
    assert (elsewhere / "shadow").read_text() == "target"


def test_pacnew_batch_reports_each_file_and_backs_up_uniquely(ur, etc, monkeypatch, tmp_path):
    d, _ = etc
    saved = tmp_path / "backups"
    saved.mkdir(mode=0o700)
    monkeypatch.setattr(ur, "backup_dir", lambda: str(saved))
    monkeypatch.setattr(ur.os, "lstat", lambda p, _real=os.lstat: _as_root(_real(p)) if str(p).endswith(".pacnew") else _real(p))
    monkeypatch.setattr(ur.os, "chown", lambda *a: None)
    said = []
    monkeypatch.setattr(ur, "say", lambda **m: said.append(m))
    for name in ("a.conf", "b.conf"):
        (d / name).write_text("yours " + name)
        (d / (name + ".pacnew")).write_text("new " + name)
    rc = ur.pacnew({"items": [{"path": str(d / "a.conf"), "action": "take"},
                              {"path": str(d / "missing.conf"), "action": "keep"},
                              {"path": str(d / "b.conf"), "action": "take"}]})
    assert rc == 1
    items = [m["item"] for m in said if "item" in m]
    assert [i["ok"] for i in items] == [True, False, True], "one refusal doesn't stop the rest"
    assert (d / "a.conf").read_text() == "new a.conf" and (d / "b.conf").read_text() == "new b.conf"
    copies = sorted(p.read_text() for p in saved.iterdir())
    assert copies == ["yours a.conf", "yours b.conf"]
    assert all(p.stat().st_mode & 0o777 == 0o600 for p in saved.iterdir())
    (d / "a.conf.pacnew").write_text("newer")
    assert ur.pacnew({"items": [{"path": str(d / "a.conf"), "action": "take"}]}) == 0
    assert len(list(saved.iterdir())) == 3, "a second take never overwrites the first backup"


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


def sha(data):
    import hashlib
    return hashlib.sha256(data).hexdigest()


def entry(path, data=b"x"):
    return {"path": str(path), "sha256": sha(data)}


def test_files_only_your_package_files_with_their_digest(ur, tmp_path):
    home = str(tmp_path)
    uid = os.getuid()
    pkg = tmp_path / "foo-1.0-1-x86_64.pkg.tar.zst"
    pkg.write_bytes(b"x")
    assert ur.files({"files": [entry(pkg)]}, home, uid) == [(str(pkg), sha(b"x"))]
    other = tmp_path / "notes.txt"
    other.write_text("x")
    link = tmp_path / "bar-1.0-1-x86_64.pkg.tar.zst"
    link.symlink_to(pkg)
    for bad in ([entry(other)], [entry(link)], [entry("/etc/passwd")], [entry(str(pkg) + "/../notes.txt")], [],
                [str(pkg)], [{"path": str(pkg)}], [{"path": str(pkg), "sha256": "nothex"}]):
        with pytest.raises((ValueError, FileNotFoundError, NotADirectoryError)):
            ur.files({"files": bad}, home, uid)
    with pytest.raises(ValueError):
        ur.files({"files": [entry(pkg)]}, home, uid + 1)


@pytest.mark.parametrize("keep", [-1, 6, "2", True, False, None, 1.5])
def test_clean_cache_refuses_invalid_keep(ur, keep):
    with pytest.raises(ValueError):
        ur.clean_cache({"keep": keep})


def test_clean_cache_runs_paccache_with_bounded_keep(ur, monkeypatch):
    ran = []
    monkeypatch.setattr(ur.os.path, "isfile", lambda p: p == ur.PACCACHE)
    monkeypatch.setattr(ur, "run_tool", lambda cmd: (ran.append(cmd) or 0))
    assert ur.clean_cache({"keep": 2}) == 0
    assert ran == [[ur.PACCACHE, "-rk2"], [ur.PACCACHE, "-ruk0"]]


def test_taken_copies_what_was_checked_and_refuses_a_link(ur, tmp_path):
    uid = os.getuid()
    pkg = tmp_path / "foo-1.0-1-x86_64.pkg.tar.zst"
    pkg.write_bytes(b"the real package")
    into = tmp_path / "root-only"
    into.mkdir(mode=0o700)
    (copy,) = ur.taken([(str(pkg), sha(b"the real package"))], str(into), uid)
    pkg.write_bytes(b"swapped afterwards")
    assert open(copy, "rb").read() == b"the real package"
    again = tmp_path / "again"
    again.mkdir(mode=0o700)
    with pytest.raises(ValueError):
        ur.taken([(str(pkg), sha(b"the real package"))], str(again), uid)
    assert list(again.iterdir()) == []
    assert os.stat(copy).st_mode & 0o777 == 0o600
    link = tmp_path / "bar-1.0-1-x86_64.pkg.tar.zst"
    link.symlink_to(pkg)
    with pytest.raises(OSError):
        ur.taken([(str(link), sha(b"x"))], str(into), uid)
    with pytest.raises(ValueError):
        ur.taken([(str(pkg), sha(b"swapped afterwards"))], str(tmp_path / "other"), uid + 1)


@pytest.mark.parametrize("hold", [["-Syu"], ["linux,glibc"], ["a b"], "linux"])
def test_held_names_are_package_names_only(ur, hold):
    with pytest.raises(ValueError):
        ur.names({"hold": hold}, "hold")


def test_held_packages_stay_out_of_the_plan_and_the_upgrade(ur, monkeypatch):
    ran, printed = [], []
    monkeypatch.setattr(ur, "pacman", lambda args: ran.append(args) or 0)
    monkeypatch.setattr(ur.subprocess, "run", lambda cmd, **kw: printed.append(cmd) or type("R", (), {"stdout": "linux 7.3-1\n"})())
    monkeypatch.setattr(ur, "say", lambda **kw: None)
    ignore = ["--ignore", ",".join(ur.names({"hold": ["nvidia-dkms", "linux"]}, "hold"))]
    assert ur.resolved(ignore) == ["linux 7.3-1"]
    assert printed[0][1:4] == ["-Su", "--ignore", "nvidia-dkms,linux"]
