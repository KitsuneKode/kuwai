"""bin/kuwai-theme install: a theme appears in the Themes panel, with its own palette and wallpapers.

The panel lists a theme only when it has a wall.set (bin/kuwai-themes); HyDE makes one when a theme is
applied, so a theme that was installed but not yet applied used to be invisible."""
import os
import shutil
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def test_install_lists_the_theme_with_its_own_palette(tmp_path):
    repo = tmp_path / "repo"
    (repo / "bin").mkdir(parents=True)
    shutil.copy(ROOT / "bin/kuwai-theme", repo / "bin/kuwai-theme")
    src = repo / "themes/demo-night"
    src.mkdir(parents=True)
    for f in ("hypr.theme", "kitty.theme", "ghostty.theme"):
        (src / f).write_text(f"# {f} of demo-night\n")
    (src / "CREDITS.txt").write_text("credits\n")
    pics = tmp_path / "pics"
    pics.mkdir()
    for n in ("a", "b"):
        Image.new("RGB", (64, 36), (10, 10, 20)).save(pics / f"{n}.png")
    import hashlib
    good = hashlib.sha256((pics / "a.png").read_bytes()).hexdigest()
    (src / "wallpapers.tsv").write_text(f"01-a\thttps://walls.invalid/a.png\t{good}\n"
                                        f"02-b\thttps://walls.invalid/b.png\n"
                                        f"03-c\thttps://walls.invalid/b.png\t{'0' * 64}\n"
                                        f"04-d\thttps://walls.invalid/b.png\tsha1:{hashlib.sha1((pics / 'b.png').read_bytes()).hexdigest()}\n"
                                        f"05-e\thttps://walls.invalid/b.png\tsha1:{'0' * 40}\n")
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    (stubs / "curl").write_text(f"""#!/bin/sh
case "$*" in *"--proto =https"*"--max-filesize"*) ;; *) exit 9 ;; esac
for a; do out=$url; url=$a; done
while [ $# -gt 0 ]; do [ "$1" = -o ] && dest=$2; shift; done
cp "{pics}/$(basename "$url")" "$dest"
""")
    (stubs / "curl").chmod(0o755)

    home = tmp_path / "home"
    home.mkdir()
    env = {"HOME": str(home), "PATH": f"{stubs}:{os.environ['PATH']}"}
    r = subprocess.run(["bash", str(repo / "bin/kuwai-theme"), "install", "demo-night"], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    dest = home / ".config/hyde/themes/Demo Night"
    assert (dest / "kitty.theme").read_text() == "# kitty.theme of demo-night\n"     # its own palette, not a borrowed one
    assert (dest / "ghostty.theme").exists() and (dest / "hypr.theme").exists()
    wall = dest / "wall.set"
    assert wall.is_symlink() and wall.resolve().parent == (dest / "wallpapers").resolve()
    assert wall.resolve().exists()
    walls = sorted(p.name for p in (dest / "wallpapers").glob("*.jpg"))
    assert walls == ["01-a.jpg", "02-b.jpg", "04-d.jpg"], "Commons' sha1: pins are checked as sha1; a file that doesn't match is skipped"
    assert "checksum differs" in r.stderr
    # run again: nothing breaks, nothing is fetched twice
    assert subprocess.run(["bash", str(repo / "bin/kuwai-theme"), "install", "demo-night"], env=env, capture_output=True, text=True, timeout=60).returncode == 0
