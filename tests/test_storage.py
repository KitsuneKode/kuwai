"""kuwai-storage: what fills the disk that a tool rebuilds, cleared only the tool's own way."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin/kuwai-storage"


def run(home, *args, path=None):
    env = {"HOME": str(home), "PATH": path or os.environ["PATH"], "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_DATA_HOME": str(home / ".local/share")}
    r = subprocess.run([str(BIN), *args], capture_output=True, text=True, env=env, timeout=60)
    return json.loads(r.stdout)


def fill(d, mb):
    d.mkdir(parents=True, exist_ok=True)
    (d / "blob").write_bytes(os.urandom(mb << 20))


def test_it_finds_caches_and_tags_what_comes_back(tmp_path):
    fill(tmp_path / ".cache/thumbnails/large", 2)
    fill(tmp_path / ".local/share/Trash/files", 2)
    out = run(tmp_path, "scan", "--fresh")
    got = {i["id"]: i for i in out["items"]}
    assert got["thumbnails"]["clearable"] is True and got["thumbnails"]["tag"] == "comes back"
    assert got["trash"]["clearable"] is False and got["trash"]["tag"] == "check first"
    assert out["disk"]["total"] > out["disk"]["free"] > 0


def test_clearing_thumbnails_never_follows_a_link_out(tmp_path):
    keep = tmp_path / "Pictures"
    fill(keep, 1)
    thumbs = tmp_path / ".cache/thumbnails"
    fill(thumbs / "large", 2)
    (thumbs / "escape").symlink_to(keep)
    out = run(tmp_path, "clear", "thumbnails")
    assert out["ok"] is True and out["freed"] > 0
    assert (keep / "blob").exists(), "a link inside the cache is removed, not what it points at"
    assert thumbs.is_dir() and not any(thumbs.iterdir())


def test_what_needs_a_look_is_never_cleared_from_here(tmp_path):
    fill(tmp_path / ".local/share/Trash/files", 1)
    for kid in ("trash", "pacman", "paru", "../../etc"):
        assert run(tmp_path, "clear", kid)["ok"] is False
    assert (tmp_path / ".local/share/Trash/files/blob").exists()


def test_a_tool_that_isnt_installed_is_said_so(tmp_path):
    fill(tmp_path / ".cache/go-build", 2)
    only = tmp_path / "bin"
    only.mkdir()
    for tool in ("python3", "du", "nice", "ionice"):
        (only / tool).symlink_to(subprocess.run(["sh", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip())
    out = run(tmp_path, "clear", "go", path=str(only))
    assert out == {"ok": False, "why": "Go build cache: its tool isn't installed"}
