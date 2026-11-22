import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def gather(home):
    env = {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"), "PATH": os.environ["PATH"]}
    return subprocess.run([str(ROOT / "bin/kuwai-fetch"), "--gather"], env=env, capture_output=True, text=True, check=True).stdout


def test_one_library_every_fetch_shares(tmp_path):
    cfg = tmp_path / ".config"
    for d in ("fastfetch/logo/pngs", "neofetch/pngs", "neofetch/gifs", "kuwai/fetch", "fastfetch/ascii"):
        (cfg / d).mkdir(parents=True)
    (cfg / "fastfetch/logo/a.png").write_bytes(b"A")
    (cfg / "fastfetch/logo/pngs/a.png").write_bytes(b"A")
    (cfg / "neofetch/pngs/a.png").write_bytes(b"A")
    (cfg / "neofetch/pngs/b.png").write_bytes(b"B")
    (cfg / "kuwai/fetch/a.png").write_bytes(b"other")
    (cfg / "neofetch/gifs/cat.gif").write_bytes(b"G")
    (cfg / "fastfetch/ascii/gojo.txt").write_text("art")
    gather(tmp_path)
    lib = tmp_path / "Pictures/fetch"
    files = sorted(p.name for p in lib.iterdir() if p.is_file())
    assert len(files) == 4 and "b.png" in files and "cat.gif" in files
    assert sum(1 for f in files if f.startswith("a")) == 2
    assert (lib / "ascii/gojo.txt").read_text() == "art"
    for d in ("fastfetch/logo", "neofetch/pngs", "neofetch/gifs", "kuwai/fetch"):
        assert (cfg / d).is_symlink() and (cfg / d).resolve() == lib.resolve()
    assert (cfg / "fastfetch/ascii").resolve() == (lib / "ascii").resolve()
    kept = list((tmp_path / ".local/state/kuwai").glob("fetch-folders-*"))
    assert len(kept) == 1 and (kept[0] / "neofetch-pngs/b.png").exists()
    gather(tmp_path)
    assert sorted(p.name for p in lib.iterdir() if p.is_file()) == files
