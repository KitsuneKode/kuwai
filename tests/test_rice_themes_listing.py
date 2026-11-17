"""rice-themes list: hashes what it doesn't know several at once, rewrites its hash cache only when something
was new, and keeps the last listing for the Themes panel's first paint. All in temporary roots."""
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader("themes_listing_fixture", str(ROOT / "bin/rice-themes"))
    spec = importlib.util.spec_from_loader("themes_listing_fixture", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    home = tmp_path / "home"
    themes = home / ".config/hyde/themes"
    thumbs = home / ".cache/hyde/thumbs"
    thumbs.mkdir(parents=True)
    walls = {}
    for i, name in enumerate(["Alpha", "beta", "Gamma"]):
        d = themes / name
        (d / "wallpapers").mkdir(parents=True)
        img = d / "wallpapers" / f"w{i}.png"
        img.write_bytes(bytes([i]) * (300_000 + i))
        (d / "wall.set").symlink_to(img)
        (d / "kitty.theme").write_text(f"background #00000{i}\ncolor4 #1234{i}0\n")
        digest = hashlib.sha1(img.read_bytes()).hexdigest()
        (thumbs / (digest + ".thmb")).write_bytes(b"png")     # present: nothing to make
        walls[name] = (str(img), digest)
    state = home / ".local/state/hyde"
    state.mkdir(parents=True)
    (state / "staterc").write_text('HYDE_THEME="Alpha"\n')
    monkeypatch.setattr(m, "HOME", str(home))
    monkeypatch.setattr(m, "THEMES", str(themes))
    monkeypatch.setattr(m, "THUMBS", str(thumbs))
    monkeypatch.setattr(m, "CACHE", str(home / ".cache/rice/themes.json"))
    monkeypatch.setattr(m, "LAST", str(home / ".cache/rice/themes-list.json"))

    def no_thumbs(*a, **k):
        raise AssertionError("made a thumbnail that already exists")
    monkeypatch.setattr(m.subprocess, "run", no_thumbs)
    return m, home, walls


def test_cold_listing_hashes_in_parallel_to_the_same_names(tmp_path, monkeypatch):
    m, home, walls = load(tmp_path, monkeypatch)
    d = m.listing()
    assert [t["name"] for t in d["themes"]] == ["Alpha", "beta", "Gamma"]
    for t in d["themes"]:
        assert t["thumb"].endswith(walls[t["name"]][1] + ".thmb")
    cache = json.loads((home / ".cache/rice/themes.json").read_text())
    assert sorted(cache.values()) == sorted(h for _, h in walls.values())
    assert [w["name"] for w in d["wallpapers"]] == ["w0"]


def test_warm_listing_leaves_the_cache_file_alone(tmp_path, monkeypatch):
    m, home, _ = load(tmp_path, monkeypatch)
    m.listing()
    cache = home / ".cache/rice/themes.json"
    before = cache.stat().st_mtime_ns
    cache.write_text(cache.read_text())          # same content, a known mtime
    stamp = cache.stat().st_mtime_ns
    m.listing()
    assert cache.stat().st_mtime_ns == stamp and stamp >= before


def test_list_keeps_the_last_listing_for_the_panel(tmp_path, monkeypatch, capsys):
    m, home, _ = load(tmp_path, monkeypatch)
    assert m.main(["list"]) == 0
    printed = capsys.readouterr().out.strip()
    kept = (home / ".cache/rice/themes-list.json").read_text()
    assert json.loads(kept) == json.loads(printed)
    assert json.loads(kept)["current"] == "Alpha"
