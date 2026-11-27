import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))
from look import packs


@pytest.fixture
def pack_environment(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    for name in ("bin", "themes"):
        (repo / name).mkdir(parents=True)
    (repo / "lib").symlink_to(ROOT / "lib", target_is_directory=True)
    helper = repo / "bin/kuwai-wallpacks"
    shutil.copy2(ROOT / "bin/kuwai-wallpacks", helper)
    data_root = tmp_path / "data"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    monkeypatch.setenv("XDG_DATA_HOME", str(data_root))
    monkeypatch.setenv("PATH", f"{fake_bin}:{os.environ['PATH']}")
    monkeypatch.setenv("PACK_DATA", str(data_root))
    stub = fake_bin / "curl"
    stub.write_text("""#!/usr/bin/env python3
import os
import sys
from pathlib import Path

args = sys.argv[1:]
assert args[0] == "--disable"
assert args[args.index("--proto") + 1] == "=https"
assert "--location" not in args
output = Path(args[args.index("--output") + 1])
root = Path(os.environ["PACK_DATA"]) / "kuwai-data/wallpaper-packs"
assert not list(root.glob("test-pack-*"))
if args[-1].endswith("/two.jpg") and os.getenv("FAKE_CURL") == "interrupt":
    output.write_bytes(b"w")
    sys.exit(18)
output.write_bytes(b"wrong" if os.getenv("FAKE_CURL") == "mismatch" else b"wall!")
""")
    stub.chmod(0o755)

    pack = {"id": "test-pack", "name": "Test pack", "images": [
        {"file": f"{name}.jpg", "name": name, "bytes": 5, "sha256": hashlib.sha256(b"wall!").hexdigest(),
         "url": f"https://upload.wikimedia.org/wikipedia/commons/a/ab/{name}.jpg",
         "page": f"https://commons.wikimedia.org/wiki/File:{name}.jpg", "licence": "PD", "author": "NASA"}
        for name in ("one", "two")
    ]}
    manifest = repo / packs.MANIFEST
    manifest.write_text(json.dumps([pack]))

    def invoke(*args):
        return subprocess.run([str(helper), *args], capture_output=True, text=True, timeout=10)

    return repo, pack, invoke


@pytest.mark.parametrize("failure", ["mismatch", "interrupt"])
def test_pack_visibility_is_atomic_and_download_can_retry(pack_environment, monkeypatch, failure):
    repo, pack, invoke = pack_environment
    assert not json.loads(invoke("list").stdout)[0]["installed"]
    monkeypatch.setenv("FAKE_CURL", failure)
    failed = invoke("download", pack["id"])
    assert failed.returncode == 1
    assert not packs.install_path(pack).exists()
    assert packs.installed_walls(repo) == []
    assert not list(packs.data_dir().glob(".test-pack-*/"))

    monkeypatch.delenv("FAKE_CURL")
    success = invoke("download", pack["id"])
    assert success.returncode == 0, success.stderr
    assert [json.loads(line)["done"] for line in success.stdout.splitlines()] == [0, 1, 2]
    assert json.loads(invoke("list").stdout)[0]["installed"]
    assert [wall["name"] for wall in packs.installed_walls(repo)] == ["one", "two"]
    assert "NASA (PD)" in (packs.install_path(pack) / "CREDITS.txt").read_text()
    assert invoke("download", pack["id"]).returncode == 0


@pytest.mark.parametrize("field,value", [
    ("licence", "personal"),
    ("url", "https://wallhaven.cc/w/unknown"),
    ("url", "http://upload.wikimedia.org/wikipedia/commons/a/ab/one.jpg"),
    ("sha256", "a" * 40),
])
def test_invalid_asset_cannot_be_listed_or_downloaded(pack_environment, field, value):
    repo, pack, invoke = pack_environment
    pack["images"][0][field] = value
    (repo / packs.MANIFEST).write_text(json.dumps([pack]))
    listed = invoke("list")
    assert listed.returncode == 1
    assert listed.stdout == ""
    assert invoke("download", pack["id"]).returncode == 1
    assert not packs.data_dir().exists()
