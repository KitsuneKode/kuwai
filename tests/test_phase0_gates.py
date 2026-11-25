"""Phase 0 hygiene and ratchet regressions for standalone kuwai."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def test_systemd_units_never_fall_back_to_dev_checkout():
    offenders = []
    for unit in sorted((ROOT / "systemd").glob("kuwai-*.service")):
        text = unit.read_text(encoding="utf-8")
        if "Projects/rice" in text:
            offenders.append(unit.name)
    assert offenders == [], f"units still fall back to Projects/rice: {offenders}"


def test_greeter_and_film_have_no_hardcoded_author_name():
    for rel in ("shell/greeter.qml", "shell/film.qml"):
        text = (ROOT / rel).read_text(encoding="utf-8")
        assert '"kitsunekode"' not in text, f"hardcoded username in {rel}"


def test_package_manifests_exist_and_parse():
    core = [l.strip() for l in (ROOT / "packages/core.txt").read_text().splitlines() if l.strip()]
    opt = [l.strip() for l in (ROOT / "packages/optional.txt").read_text().splitlines() if l.strip()]
    fonts = [l.strip() for l in (ROOT / "packages/fonts.txt").read_text().splitlines() if l.strip()]
    assert any(l.endswith(":hyprland") for l in core)
    assert any(l.endswith(":file") for l in core)
    assert ":qt6-multimedia" in core, "LiveWallpaper and ThemePanel import QtMultimedia; without it the shell does not load"
    assert "node:nodejs" in core, "kuwai-usage and kuwai-spend fall back to node when bun is absent"
    assert not any("qt6-multimedia" in l for l in opt)
    assert "awww:awww" in core, "kuwai-wallpaper.service runs awww-daemon: without it there is no wallpaper"
    assert "cmp:diffutils" in core, "install.sh and system/session compare files with cmp; diffutils isn't in base"
    assert any("matugen" in l for l in opt)
    assert any("inter-font" in l for l in fonts)


def test_layers_ratchet_passes():
    r = subprocess.run([sys.executable, str(ROOT / "bin/kuwai-layers"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_hyde_ratchet_passes():
    r = subprocess.run([sys.executable, str(ROOT / "bin/kuwai-hyde-ratchet"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
