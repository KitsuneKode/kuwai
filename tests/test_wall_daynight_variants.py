"""Day/night wallpaper variants: wallpapers.tsv column validation and kuwai-look/kuwai-themes variant lookup."""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("kuwai_wallcheck", str(ROOT / "bin/kuwai-wallcheck"))
spec = importlib.util.spec_from_loader("kuwai_wallcheck", loader)
wc = importlib.util.module_from_spec(spec)
loader.exec_module(wc)


def look_env(tmp_path):
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(tmp_path / "home"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
    }


def test_wallcheck_accepts_day_night_variant_and_rejects_unknown_variant(tmp_path):
    t = tmp_path / "solar"
    t.mkdir()
    (t / "theme.toml").write_text('name = "Solar"\naccent = "#66c7ff"\n')
    (t / "wallpapers.tsv").write_text(
        "01-dawn\thttps://example.invalid/dawn.jpg\tsha256:" + "a" * 64 + "\tPD\tNASA\thttps://commons.wikimedia.org/wiki/File:Dawn\tday\n"
        "02-dusk\thttps://example.invalid/dusk.jpg\tsha256:" + "b" * 64 + "\tPD\tNASA\thttps://commons.wikimedia.org/wiki/File:Dusk\tnight\n"
        "03-bad\thttps://example.invalid/bad.jpg\tsha256:" + "c" * 64 + "\tPD\tNASA\thttps://commons.wikimedia.org/wiki/File:Bad\ttwilight\n"
    )
    problems = wc.check_tsv(t)
    assert len(problems) == 1
    assert "03-bad" in problems[0] and "twilight" in problems[0]


def test_kuwai_look_resolves_day_and_night_variants_from_wallpapers_tsv(tmp_path):
    env = look_env(tmp_path)
    theme_walls = tmp_path / "state/kuwai/wallpapers/earthlight"
    theme_walls.mkdir(parents=True)
    day_img = theme_walls / "11-sunrise-aurora-europe.jpg"
    night_img = theme_walls / "01-france-italy-border.jpg"
    Image.new("RGB", (32, 18), (220, 140, 80)).save(day_img)
    Image.new("RGB", (32, 18), (12, 16, 28)).save(night_img)

    r_theme = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), "theme", "earthlight", "--no-apply"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r_theme.returncode == 0, r_theme.stderr

    r_day = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), "variant", "day"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r_day.returncode == 0, r_day.stderr
    assert json.loads(r_day.stdout)["path"] == str(day_img.resolve())

    r_night = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), "variant", "night"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r_night.returncode == 0, r_night.stderr
    assert json.loads(r_night.stdout)["path"] == str(night_img.resolve())

    listed = json.loads(
        subprocess.run(
            [sys.executable, str(ROOT / "bin/kuwai-look"), "list"],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout
    )
    by_name = {w["name"]: w["variant"] for w in listed["wallpapers"]}
    assert by_name["11-sunrise-aurora-europe"] == "day"
    assert by_name["01-france-italy-border"] == "night"
