"""The themes under themes/: each must be a theme HyDE, the island and the terminals can read.

A palette that fails here reads badly on the screen: the accent is the kitty.theme's blue slot
(shell/config/Theme.qml), so color4 is the island's accent as well as the terminal's blue."""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
THEMES = sorted(p for p in (ROOT / "themes").iterdir() if p.is_dir())
OWN_PALETTE = [p for p in THEMES if (p / "kitty.theme").exists()]
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def lum(h):
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def kitty(path):
    out = {}
    for line in path.read_text().splitlines():
        p = line.split()
        if len(p) == 2 and HEX.match(p[1]) and not line.startswith("#"):
            out[p[0]] = p[1]
    return out


def ghostty(path):
    out, pal = {}, {}
    for line in path.read_text().splitlines():
        m = re.match(r"^palette = (\d+)=(#[0-9a-fA-F]{6})$", line)
        if m:
            pal[int(m[1])] = m[2]
            continue
        m = re.match(r"^([a-z-]+) = (#[0-9a-fA-F]{6})$", line)
        if m:
            out[m[1]] = m[2]
    return out, pal


@pytest.mark.parametrize("theme", THEMES, ids=lambda p: p.name)
def test_every_theme_has_borders_credits_and_wallpapers(theme):
    assert (theme / "hypr.theme").exists()
    assert (theme / "CREDITS.txt").exists()
    names = set()
    for line in (theme / "wallpapers.tsv").read_text().splitlines():
        name, url = line.split("\t")
        assert re.fullmatch(r"[A-Za-z0-9._-]+", name), name
        assert name not in names, f"{name} twice"
        names.add(name)
        assert url.startswith("https://"), url
    assert names, "a theme with no wallpapers"


@pytest.mark.parametrize("theme", THEMES, ids=lambda p: p.name)
def test_theme_leaves_motion_to_kuwai(theme):
    t = (theme / "hypr.theme").read_text()
    assert not re.search(r"^\s*animation", t, re.M), "motion is kuwai's, not the theme's (hypr/kuwai/motion.lua)"


@pytest.mark.parametrize("theme", OWN_PALETTE, ids=lambda p: p.name)
def test_blur_stays_inside_the_budget(theme):
    # hypr/kuwai/look.lua caps passes at 3 whatever a theme says; a theme of ours asks for what it gets.
    for m in re.finditer(r"passes = (\d+)", (theme / "hypr.theme").read_text()):
        assert int(m[1]) <= 3


@pytest.mark.parametrize("theme", OWN_PALETTE, ids=lambda p: p.name)
def test_palette_is_complete_and_readable(theme):
    k = kitty(theme / "kitty.theme")
    for key in ["foreground", "background", "selection_background", "cursor"] + [f"color{i}" for i in range(16)]:
        assert key in k, f"{key} missing"
    bg = k["background"]
    assert contrast(k["foreground"], bg) >= 7
    for i in list(range(1, 8)) + list(range(9, 16)):
        assert contrast(k[f"color{i}"], bg) >= 4.5, f"color{i} is hard to read on the background"
    assert contrast(k["color8"], bg) >= 3, "comments (color8) vanish"
    assert contrast(k["color4"], bg) >= 4.5, "the accent (color4) is the island's colour"
    assert lum(bg) < 0.02, "the island stays near-black; a kuwai theme is a dark one"


@pytest.mark.parametrize("theme", OWN_PALETTE, ids=lambda p: p.name)
def test_ghostty_says_what_kitty_says(theme):
    k = kitty(theme / "kitty.theme")
    g, pal = ghostty(theme / "ghostty.theme")
    assert g["foreground"] == k["foreground"] and g["background"] == k["background"]
    assert g["cursor-color"] == k["cursor"]
    assert {i: pal[i] for i in range(16)} == {i: k[f"color{i}"] for i in range(16)}


@pytest.mark.parametrize("theme", OWN_PALETTE, ids=lambda p: p.name)
def test_accent_leads_the_border(theme):
    k = kitty(theme / "kitty.theme")
    t = (theme / "hypr.theme").read_text()
    accent = k["color4"].lstrip("#").lower()
    assert f"rgba({accent}" in t.lower(), "the active border carries the theme's accent"


def border_colours(theme):
    t = (theme / "hypr.theme").read_text()
    act = re.search(r"col\.active_border = (.+?) #", t)
    ina = re.search(r"col\.inactive_border = rgba\((\w{6})(\w{2})\)", t)
    return act[1], ina


@pytest.mark.parametrize("theme", OWN_PALETTE, ids=lambda p: p.name)
def test_the_focused_window_is_unmistakable_and_the_rest_are_quiet(theme):
    """Focus is shown by contrast between two borders, not by a loud one: the focused window's border is
    two palette colours, both strong; the others get a faint accent hairline; the focused window also
    stands on a coloured shadow and the rest recede a little."""
    k = kitty(theme / "kitty.theme")
    active, inactive = border_colours(theme)
    stops = re.findall(r"rgba\((\w{6})(\w{2})\)", active)
    assert len(stops) == 2 and stops[0][0] != stops[1][0], "a gradient from the accent to a companion"
    palette = {v.lstrip("#").lower() for v in k.values()}
    for rgb, alpha in stops:
        assert rgb.lower() in palette, f"{rgb} is not in the palette"
    assert int(stops[0][1], 16) >= 0xDD and int(stops[1][1], 16) >= 0x80, "both ends of the border must show"
    assert inactive[1].lower() == k["color4"].lstrip("#").lower(), "the others carry the accent's hue"
    assert int(inactive[2], 16) <= 0x30, "…but quietly"
    t = (theme / "hypr.theme").read_text()
    assert re.search(r"border_size = (\d+)", t) and int(re.search(r"border_size = (\d+)", t)[1]) >= 2
    assert "dim_inactive = true" in t and 0.04 <= float(re.search(r"dim_strength = ([\d.]+)", t)[1]) <= 0.12
    assert re.search(r"shadow \{[^}]*color = rgba\(\w{6}[c-f]\w\)", t, re.S), "a deep accent shadow under the focused window"
