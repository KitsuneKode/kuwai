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
    (src / "wallpapers.tsv").write_text("".join(f"0{i}-{n}\tfile://{pics}/{n}.png\n" for i, n in enumerate("ab", 1)))

    home = tmp_path / "home"
    home.mkdir()
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    r = subprocess.run(["bash", str(repo / "bin/kuwai-theme"), "install", "demo-night"], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    dest = home / ".config/hyde/themes/Demo Night"
    assert (dest / "kitty.theme").read_text() == "# kitty.theme of demo-night\n"     # its own palette, not a borrowed one
    assert (dest / "ghostty.theme").exists() and (dest / "hypr.theme").exists()
    wall = dest / "wall.set"
    assert wall.is_symlink() and wall.resolve().parent == (dest / "wallpapers").resolve()
    assert wall.resolve().exists()
    # run again: nothing breaks, nothing is fetched twice
    assert subprocess.run(["bash", str(repo / "bin/kuwai-theme"), "install", "demo-night"], env=env, capture_output=True, text=True, timeout=60).returncode == 0
