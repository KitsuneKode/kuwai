"""A run says what happened, phase by phase: a half that worked is not reported as nothing."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def m(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader("outcome_updater", str(ROOT / "bin/kuwai-update"))
    spec = importlib.util.spec_from_loader("outcome_updater", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    for name in ("LOG_DIR", "RUNTIME", "CACHE", "AUR_DIR"):
        monkeypatch.setattr(mod, name, str(tmp_path / name.lower()))
    monkeypatch.setattr(mod, "EVENTS", str(tmp_path / "events.jsonl"))
    monkeypatch.setattr(mod, "APPROVED", str(tmp_path / "approved.json"))
    monkeypatch.setattr(mod, "TRUSTED", str(tmp_path / "trusted.json"))
    monkeypatch.setattr(mod.os, "statvfs", lambda p: SimpleNamespace(f_bavail=10 ** 9, f_frsize=4096))
    monkeypatch.setattr(mod, "sh", lambda cmd, **kw: SimpleNamespace(stdout="", returncode=0))
    monkeypatch.setattr(mod.shutil, "which", lambda x: None)
    mod.calls = []

    class FakeRoot:
        def __init__(self, R):
            self.helper, self.p, self.prompts, self.transaction = True, True, 1, ["linux 7.3-1"]

        def open(self, ops=()):
            mod.opened = list(ops)
            return 0

        def run(self, op, **kw):
            mod.calls.append(op)
            return mod.answers.get(op, 0)

        def close(self):
            pass
    monkeypatch.setattr(mod, "Root", FakeRoot)

    def done():
        evs = [json.loads(l) for l in open(mod.EVENTS)]
        return [e for e in evs if e["e"] == "done"][-1], [e for e in evs if e["e"] == "error"]
    mod.done = done
    return mod


def test_upgrade_ok_then_deps_fail_is_partial_not_nothing(m):
    m.missing_deps = lambda d: (["meson"], [], True)
    m.clone = lambda pkg: ("/nowhere", "a" * 40)
    m.prepare_recipe = lambda d, pkg, head: d
    m.save(m.TRUSTED, ["fixture"])
    m.answers = {"deps": 1}
    assert m.run_locked(["--repo", "--aur", "fixture"]) == 1
    done, errors = m.done()
    assert m.calls == ["upgrade", "deps"], "upgrade and its build deps are separate, recorded steps"
    assert m.opened == ["upgrade", "deps", "install"], "the password prompt names every operation the run may do, and no other"
    assert done["repo"] is True and done["deps"] is False and done["partial"] is True
    assert [p["id"] for p in done["phases"]] == ["repo", "deps"]
    assert done["phases"][0]["transaction"] == ["linux 7.3-1"]
    assert any(s["pkg"] == "fixture" for s in done["skipped"])
    assert "Arch packages are updated" in errors[-1]["msg"]
    assert not any("half-installed" in e["msg"] for e in errors)


def test_cache_is_pruned_only_when_asked(m):
    m.answers = {}
    m.run_locked(["--repo"])
    assert "clean-cache" not in m.calls
    m.calls.clear()
    m.run_locked(["--repo", "--prune-cache"])
    assert m.calls == ["upgrade", "clean-cache"]
    m.answers = {"clean-cache": 1}
    m.run_locked(["--repo", "--prune-cache"])
    done, _ = m.done()
    assert done["pruned"] is False and done["ok"] is True


def test_check_names_what_pacman_adds_beyond_the_list(m, tmp_path, monkeypatch):
    db = tmp_path / "db"
    (db / "sync").mkdir(parents=True)
    monkeypatch.setenv("CHECKUPDATES_DB", str(db))
    monkeypatch.setattr(m, "sh", lambda cmd, **kw: SimpleNamespace(returncode=0, stdout="linux 7.3-1\nnew-dep 1.0-1\n", stderr=""))
    assert m.resolved_extra({"linux"}) == [{"name": "new-dep", "new": "1.0-1"}]


def test_held_packages_are_left_alone(m, tmp_path, monkeypatch):
    monkeypatch.setattr(m, "HELD", str(tmp_path / "held.json"))
    m.save(m.HELD, {"linux-lts": {"version": "6.12-1", "at": 1}, "-bad": {}, "fixture": {"version": "1", "at": 1}})
    seen = []

    class Holding(m.Root):
        def __init__(self, R):
            self.helper, self.p, self.prompts, self.transaction = True, True, 1, []

        def run(self, op, **kw):
            seen.append((op, kw.get("hold")))
            return 0
    monkeypatch.setattr(m, "Root", Holding)
    m.answers = {}
    m.save(m.TRUSTED, ["fixture"])
    m.run_locked(["--repo", "--aur", "fixture"])
    assert seen[0] == ("upgrade", ["fixture", "linux-lts"]), "every update ignores what you hold, and nothing that isn't a name"
    done, _ = m.done()
    assert not done["built"], "a held AUR package isn't built"


def test_hold_remembers_the_version_you_had(m, tmp_path, monkeypatch):
    monkeypatch.setattr(m, "HELD", str(tmp_path / "held.json"))
    monkeypatch.setattr(m, "sh", lambda cmd, **kw: SimpleNamespace(stdout="linux-lts 6.12.9-1\n", returncode=0))
    assert m.hold("linux-lts", True)["linux-lts"]["version"] == "6.12.9-1"
    assert m.hold("linux-lts", False) == {}
