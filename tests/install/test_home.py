import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(home, *args):
    env = {"HOME": str(home), "XDG_STATE_HOME": str(home / ".local/state"), "KUWAI_HOME_SRC": str(ROOT / "home"), "PATH": os.environ["PATH"]}
    return subprocess.run([str(ROOT / "bin/kuwai-home"), *args], env=env, capture_output=True, text=True, check=True).stdout


def test_links_what_kuwai_owns_and_keeps_what_was_there(tmp_path):
    cfg = tmp_path / ".config/fastfetch/config.jsonc"
    cfg.parent.mkdir(parents=True)
    cfg.write_text('{"logo": "hyde"}')
    assert "linked .config/fastfetch/config.jsonc" in run(tmp_path)
    assert cfg.is_symlink() and cfg.resolve() == (ROOT / "home/.config/fastfetch/config.jsonc").resolve()
    assert "already linked" in run(tmp_path)
    state = tmp_path / ".local/state/kuwai"
    subprocess.run(["python3", str(ROOT / "bin/kuwai_install.py"), "--state", str(state), "restore"], check=True, capture_output=True)
    assert not cfg.is_symlink() and cfg.read_text() == '{"logo": "hyde"}'


def test_dry_run_changes_nothing(tmp_path):
    out = run(tmp_path, "--dry-run")
    assert "would link" in out and not (tmp_path / ".config").exists()


def test_the_fastfetch_config_needs_no_hyde_and_runs_nothing():
    text = (ROOT / "home/.config/fastfetch/config.jsonc").read_text()
    assert "hyde" not in text.lower() and '"command"' not in text and "splash" not in text
    assert '"type": "kitty"' in text and "kuwai-fetch --logo" in text


def test_links_follow_xdg_config_home(tmp_path):
    xdg = tmp_path / "elsewhere"
    env = {"HOME": str(tmp_path), "XDG_CONFIG_HOME": str(xdg), "XDG_STATE_HOME": str(tmp_path / ".local/state"),
           "KUWAI_HOME_SRC": str(ROOT / "home"), "PATH": os.environ["PATH"]}
    subprocess.run([str(ROOT / "bin/kuwai-home")], env=env, capture_output=True, text=True, check=True)
    assert (xdg / "fastfetch/config.jsonc").is_symlink()
    assert not (tmp_path / ".config").exists()
