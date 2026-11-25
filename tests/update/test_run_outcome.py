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

        def open(self):
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
