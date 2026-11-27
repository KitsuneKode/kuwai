import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_the_icon_tiles_match_their_marks():
    r = subprocess.run([str(ROOT / "bin/kuwai-brand-tiles"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout


def test_no_brand_mark_is_drawn_dark_on_the_dark_capsules():
    import re
    from pathlib import Path
    root = Path(__file__).resolve().parents[1] / "shell/assets/brands"
    dark = []
    for f in sorted(root.glob("*.svg")):
        for c in re.findall(r'fill="#([0-9a-fA-F]{3,6})"', f.read_text()):
            c = "".join(ch * 2 for ch in c) if len(c) == 3 else c
            r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
            if 0.2126 * r + 0.7152 * g + 0.0722 * b < 48:
                dark.append(f"{f.name}: #{c}")
    assert not dark, "a mark this dark vanishes on a capsule (Kiro's was #000): " + ", ".join(dark)
