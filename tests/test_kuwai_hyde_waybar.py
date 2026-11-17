"""bin/kuwai-hyde-waybar: HyDE's Waybar template out of every theme (and back), in HyDE's own config."""
import os
import subprocess
import tomllib
from pathlib import Path

BIN = Path(__file__).resolve().parents[1] / "bin" / "kuwai-hyde-waybar"

BASE = """# HyDE's config
[hyprland]
terminal = "kitty"  # keep me

[waybar]
font = "JetBrainsMono Nerd Font"
"""


def run(home: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([str(BIN), *args], env={**os.environ, "XDG_CONFIG_HOME": str(home)},
                          capture_output=True, text=True, timeout=10)


def conf(home: Path) -> Path:
    return home / "hyde" / "config.toml"


def setup(tmp_path: Path, text: str = BASE) -> Path:
    (tmp_path / "hyde").mkdir()
    conf(tmp_path).write_text(text)
    return tmp_path


def test_off_adds_the_skip_once_and_keeps_the_rest(tmp_path):
    home = setup(tmp_path)
    assert run(home, "off").returncode == 0
    assert run(home, "off").returncode == 0
    text = conf(home).read_text()
    data = tomllib.loads(text)
    assert data["wallbash"]["skip_template"] == ["waybar"]
    assert data["hyprland"]["terminal"] == "kitty" and "# keep me" in text and text.startswith("# HyDE's config")
    assert run(home, "status").stdout.strip() == "off"


def test_on_takes_it_out_and_keeps_other_skips(tmp_path):
    home = setup(tmp_path, BASE + '\n[wallbash]\nskip_template = ["rofi", "waybar"]\n')
    assert run(home, "on").returncode == 0
    assert tomllib.loads(conf(home).read_text())["wallbash"]["skip_template"] == ["rofi"]
    assert run(home, "status").stdout.strip() == "on"


def test_an_existing_section_without_the_key(tmp_path):
    home = setup(tmp_path, BASE + "\n[wallbash]\n# nothing yet\n\n[other]\nx = 1\n")
    run(home, "off")
    data = tomllib.loads(conf(home).read_text())
    assert data["wallbash"]["skip_template"] == ["waybar"] and data["other"]["x"] == 1


def test_no_hyde_nothing_written(tmp_path):
    assert run(tmp_path, "off").returncode == 0
    assert not conf(tmp_path).exists()


def test_a_config_it_cannot_parse_is_left_alone(tmp_path):
    bad = "[wallbash\nskip_template = [\n"
    home = setup(tmp_path, bad)
    run(home, "off")
    assert conf(home).read_text() == bad
