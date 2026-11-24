import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_the_icon_tiles_match_their_marks():
    r = subprocess.run([str(ROOT / "bin/kuwai-brand-tiles"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout
