"""Regression tests for non-glass full-screen layer namespaces staying outside ^kuwai-.*$ blur."""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def extract_namespaces(relpath):
    text = (REPO / relpath).read_text(encoding="utf-8")
    return re.findall(r'WlrLayershell\.namespace:\s*"([^"]+)"', text)


def test_fullscreen_non_glass_surfaces_use_dotted_kuwai_namespace():
    expected = {
        "shell-saver/shell.qml": "kuwai.saver-film",
        "shell/modules/screensaver/Screensaver.qml": "kuwai.screensaver",
        "shell/modules/wallpaper/LiveWallpaper.qml": "kuwai.wallpaper",
        "shell/services/WallFx.qml": "kuwai.wallfx",
        "shell/modules/lock/Lock.qml": "kuwai.fade",
    }
    for path, ns in expected.items():
        found = extract_namespaces(path)
        assert ns in found, f"{path}: expected {ns}, got {found}"
        assert not any(n.startswith("kuwai-") for n in found), f"{path}: hyphenated namespace gets blurred by kuwai-glass: {found}"


def test_hypr_rules_cover_dotted_saver_and_fade_namespaces():
    rules = (REPO / "hypr/kuwai/rules.lua").read_text(encoding="utf-8")
    assert "screensaver|saver-film|fade" in rules
