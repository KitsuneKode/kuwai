"""Per-monitor wallpapers: output-identity storage, awww -o targeting, primary-only recolour, and hotplug restore."""
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def paint(path, rgb):
    Image.new("RGB", (64, 36), rgb).save(path)
    return path


def make_env(tmp_path, monitors):
    stub = tmp_path / "stub"
    stub.mkdir(exist_ok=True)
    monitors_file = tmp_path / "monitors.json"
    monitors_file.write_text(json.dumps(monitors))
    awww_log = tmp_path / "awww.log"
    (stub / "hyprctl").write_text(
        '#!/bin/sh\nif [ "$1" = monitors ] && [ "$2" = -j ]; then cat "$FAKE_MONITORS"; exit 0; fi\nexit 0\n'
    )
    (stub / "hyprctl").chmod(0o755)
    (stub / "awww").write_text(
        '#!/bin/sh\nif [ "$1" = query ]; then exit 0; fi\necho "$*" >> "$FAKE_AWWW_LOG"\n'
    )
    (stub / "awww").chmod(0o755)
    (stub / "pkill").write_text("#!/bin/sh\nexit 0\n")
    (stub / "pkill").chmod(0o755)
    env = {
        "PATH": f"{stub}:{os.environ.get('PATH', '/usr/bin:/bin')}",
        "HOME": str(tmp_path / "home"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
        "WALLPAPER_AWWW_TRANSITION_DEFAULT": "none",
        "FAKE_MONITORS": str(monitors_file),
        "FAKE_AWWW_LOG": str(awww_log),
    }
    return env, monitors_file, awww_log


def run_look(env, *args):
    return subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_per_monitor_storage_uses_description_and_colours_follow_primary(tmp_path):
    monitors = [
        {"id": 0, "name": "DP-3", "description": "Acer XV272U V 12345 (DP-3)", "focused": True},
        {"id": 1, "name": "eDP-1", "description": "BOE 0x095F", "focused": False},
    ]
    env, monitors_file, awww_log = make_env(tmp_path, monitors)
    wall_primary = paint(tmp_path / "blue.png", (20, 60, 180))
    wall_secondary = paint(tmp_path / "red.png", (190, 30, 30))

    r1 = run_look(env, "set-wallpaper", str(wall_primary), "--mode", "dark", "--output", "DP-3")
    assert r1.returncode == 0, r1.stderr
    d1 = json.loads(r1.stdout)
    assert d1["output"] == "DP-3"
    assert d1["outputId"] == "Acer XV272U V 12345"
    assert d1["recolored"] is True
    primary_accent = d1["palette"]["role"]["accent"]
    assert f"img -o DP-3 {wall_primary.resolve()} --transition-type none" in awww_log.read_text()

    r2 = run_look(env, "set-wallpaper", str(wall_secondary), "--mode", "dark", "--output", "eDP-1")
    assert r2.returncode == 0, r2.stderr
    d2 = json.loads(r2.stdout)
    assert d2["output"] == "eDP-1"
    assert d2["outputId"] == "BOE 0x095F"
    assert d2["recolored"] is False
    assert f"img -o eDP-1 {wall_secondary.resolve()} --transition-type none" in awww_log.read_text()

    status = json.loads(run_look(env, "status").stdout)
    assert status["palette"]["role"]["accent"] == primary_accent
    assert Path(status["wallpaper"]).resolve() == wall_primary.resolve()

    saved = json.loads((tmp_path / "state/kuwai/wallpapers.json").read_text())
    assert saved["screens"]["Acer XV272U V 12345"] == str(wall_primary.resolve())
    assert saved["screens"]["BOE 0x095F"] == str(wall_secondary.resolve())
    assert "DP-3" not in saved["screens"] and "eDP-1" not in saved["screens"]

    listed = json.loads(run_look(env, "list").stdout)
    assert listed["screenWallpapers"]["DP-3"] == str(wall_primary.resolve())
    assert listed["screenWallpapers"]["eDP-1"] == str(wall_secondary.resolve())

    awww_log.unlink()
    monitors_replugged = [
        {"id": 0, "name": "HDMI-A-1", "description": "Acer XV272U V 12345 (HDMI-A-1)", "focused": True},
        {"id": 1, "name": "eDP-1", "description": "BOE 0x095F", "focused": False},
    ]
    monitors_file.write_text(json.dumps(monitors_replugged))
    r_restore = run_look(env, "restore", "--output", "HDMI-A-1")
    assert r_restore.returncode == 0, r_restore.stderr
    d_restore = json.loads(r_restore.stdout)
    assert len(d_restore["restored"]) == 1
    assert d_restore["restored"][0]["output"] == "HDMI-A-1"
    assert d_restore["restored"][0]["wallpaper"] == str(wall_primary.resolve())
    assert f"img -o HDMI-A-1 {wall_primary.resolve()} --transition-type none" in awww_log.read_text()

    awww_log.unlink()
    r_wall_restore = subprocess.run(
        [str(ROOT / "bin/kuwai-wall"), "restore"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r_wall_restore.returncode == 0, r_wall_restore.stderr
    log_all = awww_log.read_text()
    assert f"img -o HDMI-A-1 {wall_primary.resolve()} --transition-type none" in log_all
    assert f"img -o eDP-1 {wall_secondary.resolve()} --transition-type none" in log_all


def test_global_wallpaper_clears_per_screen_overrides(tmp_path):
    monitors = [
        {"id": 0, "name": "DP-3", "description": "Acer XV272U", "focused": True},
        {"id": 1, "name": "eDP-1", "description": "BOE 0x095F", "focused": False},
    ]
    env, _, awww_log = make_env(tmp_path, monitors)
    wall_a = paint(tmp_path / "a.png", (30, 50, 90))
    wall_b = paint(tmp_path / "b.png", (20, 90, 60))

    assert run_look(env, "set-wallpaper", str(wall_a), "--output", "eDP-1").returncode == 0
    saved1 = json.loads((tmp_path / "state/kuwai/wallpapers.json").read_text())
    assert saved1["screens"]["BOE 0x095F"] == str(wall_a.resolve())

    awww_log.unlink()
    assert run_look(env, "set-wallpaper", str(wall_b)).returncode == 0
    saved2 = json.loads((tmp_path / "state/kuwai/wallpapers.json").read_text())
    assert saved2["default"] == str(wall_b.resolve())
    assert saved2["screens"] == {}
    assert f"img {wall_b.resolve()} --transition-type none" in awww_log.read_text()


def test_focus_switch_preserves_legacy_default_and_does_not_reapply_wallpaper(tmp_path):
    monitors = [
        {"name": "DP-1", "description": "External panel", "focused": True},
        {"name": "eDP-1", "description": "Laptop panel", "focused": False},
    ]
    env, monitors_file, awww_log = make_env(tmp_path, monitors)
    original = paint(tmp_path / "original.png", (20, 60, 180))
    custom = paint(tmp_path / "custom.png", (180, 60, 20))
    link = tmp_path / "state/kuwai/wallpaper"
    link.parent.mkdir(parents=True)
    link.symlink_to(original)
    assert run_look(env, "set-wallpaper", str(custom), "--output", "DP-1").returncode == 0
    assert link.resolve() == custom
    assert run_look(env, "mode", "light", "--no-apply").returncode == 0
    assert link.resolve() == custom

    monitors[0]["focused"] = False
    monitors[1]["focused"] = True
    monitors_file.write_text(json.dumps(monitors))
    awww_log.unlink()
    assert run_look(env, "focus-wallpaper", "--no-apply").returncode == 0
    assert link.resolve() == original
    assert not awww_log.exists()
    assert json.loads(run_look(env, "status").stdout)["wallpaper"] == str(original)


def test_variant_changes_only_outputs_inheriting_the_default(tmp_path):
    monitors = [
        {"name": "DP-1", "description": "External panel", "focused": True},
        {"name": "eDP-1", "description": "Laptop panel", "focused": False},
    ]
    env, _, awww_log = make_env(tmp_path, monitors)
    custom = paint(tmp_path / "custom.png", (20, 50, 80))
    dawn = paint(tmp_path / "dawn.png", (80, 50, 20))
    assert run_look(env, "set-wallpaper", str(custom), "--output", "DP-1").returncode == 0
    assert run_look(env, "apply-variant", str(dawn), "--boundary", "2026-11-28:day").returncode == 0
    assert awww_log.read_text().splitlines()[-1] == f"img -o eDP-1 {dawn} --transition-type none"
    saved = json.loads((tmp_path / "state/kuwai/wallpapers.json").read_text())
    assert saved["default"] == str(dawn)
    assert saved["screens"] == {"External panel": str(custom)}
    assert (tmp_path / "state/kuwai/wallpaper").resolve() == custom

    assert run_look(env, "set-wallpaper", str(custom)).returncode == 0
    awww_log.unlink()
    assert run_look(env, "apply-variant", str(dawn), "--boundary", "2026-11-28:day").returncode == 0
    assert not awww_log.exists()
    assert (tmp_path / "state/kuwai/wallpaper").resolve() == custom
