"""kuwai-cleanup trash: each skill by its own path; a folder outside the skills folders keeps
its files unless asked; the undo journal keeps every batch and what couldn't go back."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def world(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader("kuwai_cleanup", str(ROOT / "bin/kuwai-cleanup"))
    spec = importlib.util.spec_from_loader("kuwai_cleanup", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    home = tmp_path / "home"
    store, claude = home / ".agents/skills", home / ".claude/skills"
    for d in (store, claude):
        d.mkdir(parents=True)
    monkeypatch.setattr(m, "AGENT_DIRS", [claude, store])
    monkeypatch.setattr(m, "STATE", tmp_path / "state")
    monkeypatch.setattr(m, "JOURNAL", tmp_path / "state/cleanup-undo.json")
    monkeypatch.setattr(m, "CACHE", tmp_path / "cache")
    trash = tmp_path / "trash"
    trash.mkdir()

    def fake_trash(path):
        p = Path(path)
        dest = trash / p.name
        p.rename(dest)
        return True
    monkeypatch.setattr(m, "gio_trash", fake_trash)

    def skill(where, name):
        d = where / name
        d.mkdir(parents=True)
        (d / "SKILL.md").write_text(f"---\nname: {name}\ndescription: d\n---\n")
        return d
    return m, home, store, claude, trash, skill


def test_one_copy_by_path_leaves_its_namesake(world, capsys):
    m, home, store, claude, trash, skill = world
    a, b = skill(store, "dup"), skill(claude, "dup")
    assert m.trash_skills([str(a.resolve())]) == 0
    assert not a.exists() and b.exists()
    assert m.trash_skills(["dup"]) == 1, "a bare name is not a path"


def test_an_external_target_loses_only_its_links(world, tmp_path):
    m, home, store, claude, trash, skill = world
    checkout = skill(tmp_path / "Projects/mine", "dev-skill")
    (claude / "dev-skill").symlink_to(checkout)
    assert m.trash_skills([str(checkout.resolve())]) == 0
    assert checkout.is_dir(), "your checkout stays"
    assert not (claude / "dev-skill").exists()
    rec = json.loads(m.JOURNAL.read_text())
    assert rec[-1]["moved"][0]["kind"] == "unlink"
    assert m.restore() == 0
    assert (claude / "dev-skill").is_symlink()


def test_restore_keeps_what_it_could_not_put_back_and_earlier_batches(world, monkeypatch):
    m, home, store, claude, trash, skill = world
    one, two = skill(store, "one"), skill(store, "two")
    m.trash_skills([str(one.resolve())])
    m.trash_skills([str(two.resolve())])
    monkeypatch.setattr(m.subprocess, "run", lambda *a, **k: type("R", (), {"stdout": "", "returncode": 1})())
    assert m.restore() == 1
    b = m.batches()
    assert len(b) == 2 and b[-1]["moved"][0]["path"].endswith("two"), "the failed batch stays to retry"
