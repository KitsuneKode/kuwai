import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def updater():
    loader = importlib.machinery.SourceFileLoader("aur_updater", str(ROOT / "bin/kuwai-update"))
    spec = importlib.util.spec_from_loader("aur_updater", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def fake_path(tmp_path, monkeypatch, names):
    d = tmp_path / "bin"
    d.mkdir()
    for name in names:
        p = d / name
        p.write_text("#!/bin/sh\nexit 0\n")
        p.chmod(0o755)
    monkeypatch.setenv("PATH", str(d))
    return d


def result(stdout="", returncode=0):
    return SimpleNamespace(stdout=stdout, stderr="", returncode=returncode)


def test_paru_is_used_when_it_is_on_path(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, ["paru", "yay"])
    calls = []
    def sh(cmd, **kw):
        calls.append(cmd)
        return result("fixture 1.0-1 -> 1.1-1\n")
    monkeypatch.setattr(updater, "sh", sh)
    rows, helper, read_only = updater.aur_updates()
    assert helper == "paru" and read_only is False
    assert calls == [["paru", "-Qua"]]
    assert rows == [{"name": "fixture", "old": "1.0-1", "new": "1.1-1", "repo": "aur"}]


def test_yay_is_used_when_paru_is_not_on_path(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, ["yay"])
    calls = []
    def sh(cmd, **kw):
        calls.append(cmd)
        return result("fixture 1.0-1 -> 1.1-1\n")
    monkeypatch.setattr(updater, "sh", sh)
    rows, helper, read_only = updater.aur_updates()
    assert helper == "yay" and read_only is False
    assert calls == [["yay", "-Qua"]]
    assert rows[0]["name"] == "fixture"


def test_no_helper_lists_outdated_foreign_packages_read_only(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, [])
    monkeypatch.setattr(updater, "aur_info", lambda names: {
        "newer": {"version": "1.1-1"},
        "same": {"version": "2.0-1"},
        "older": {"version": "1.0-1"},
    })
    def sh(cmd, **kw):
        if cmd == ["pacman", "-Qm"]:
            return result("newer 1.0-1\nsame 2.0-1\nolder 2.0-1\nmissing 1.0-1\n")
        if cmd[0] == "vercmp":
            return result("1" if cmd[1] == "1.1-1" and cmd[2] == "1.0-1" else "-1")
        raise AssertionError(cmd)
    monkeypatch.setattr(updater, "sh", sh)
    rows, helper, read_only = updater.aur_updates()
    assert helper == "" and read_only is True
    assert rows == [{"name": "newer", "old": "1.0-1", "new": "1.1-1", "repo": "aur", "readOnly": True}]


def test_the_helperless_path_never_fails_when_pacman_or_the_network_does(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, [])
    def sh(cmd, **kw):
        raise OSError("synthetic missing command")
    monkeypatch.setattr(updater, "sh", sh)
    monkeypatch.setattr(updater, "aur_info", lambda names: {})
    assert updater.aur_updates() == ([], "", True)


def test_a_command_timeout_in_the_helperless_path_is_not_a_check_failure(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, [])
    def sh(cmd, **kw):
        raise updater.subprocess.TimeoutExpired(cmd, 1)
    monkeypatch.setattr(updater, "sh", sh)
    monkeypatch.setattr(updater, "aur_info", lambda names: {})
    assert updater.aur_updates() == ([], "", True)


def test_helper_output_that_fails_is_an_empty_list_not_an_error(updater, tmp_path, monkeypatch):
    fake_path(tmp_path, monkeypatch, ["yay"])
    monkeypatch.setattr(updater, "sh", lambda cmd, **kw: result("", 1))
    assert updater.aur_updates() == ([], "yay", False)


def test_check_carries_read_only_aur_rows_and_helper_state(updater, monkeypatch):
    rows = [{"name": "newer", "old": "1.0-1", "new": "1.1-1", "repo": "aur", "readOnly": True}]
    monkeypatch.setattr(updater, "sh", lambda cmd, **kw: result("", 2))
    monkeypatch.setattr(updater, "repo_of", lambda names: {})
    monkeypatch.setattr(updater, "resolved_extra", lambda names: [])
    monkeypatch.setattr(updater, "held", lambda: set())
    monkeypatch.setattr(updater, "aur_updates", lambda: (rows, "", True))
    monkeypatch.setattr(updater, "load", lambda path, default: default)
    monkeypatch.setattr(updater, "last_upgrade", lambda: 0)
    monkeypatch.setattr(updater, "news", lambda since: [])
    out = updater.check(False)
    assert out["aur"] == rows
    assert out["aurHelper"] == "" and out["aurReadOnly"] is True
    assert out["aur"][0]["community"] is None
