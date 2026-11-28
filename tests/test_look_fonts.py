import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "lib") not in sys.path:
    sys.path.insert(0, str(ROOT / "lib"))

from look.fonts import render_kitty_fonts, resolve_desktop_fonts, sync_desktop_fonts, upsert_gtk_ini


def test_resolve_prefers_sf_pro_text_and_respects_coding_mono():
    installed = {"SF Pro Text", "SF Pro Rounded", "SF Mono", "MonoLisa", "Dank Mono", "Maple Mono", "Geist"}
    auto = resolve_desktop_fonts({"fontProfile": "sf-rounded", "monoFont": "auto"}, installed)
    assert auto["uiFamily"] == "SF Pro Text"
    assert auto["uiSpec"] == "SF Pro Text 12"
    assert auto["monoFamily"] == "SF Mono"

    ml = resolve_desktop_fonts({"fontProfile": "sf-rounded", "monoFont": "monolisa"}, installed)
    assert ml["monoFamily"] == "MonoLisa"

    dank = resolve_desktop_fonts({"fontProfile": "geist", "monoFont": "dank-mono", "textScale": 1.2}, installed)
    assert dank["uiFamily"] == "Geist"
    assert dank["uiSpec"] == "Geist 14"
    assert dank["monoFamily"] == "Dank Mono"


def test_upsert_gtk_ini_preserves_other_keys(tmp_path):
    ini = tmp_path / "gtk-3.0" / "settings.ini"
    ini.parent.mkdir(parents=True)
    ini.write_text("[Settings]\ngtk-application-prefer-dark-theme=1\ngtk-font-name=Cantarell 11\ngtk-cursor-theme-name=Bibata\n")
    upsert_gtk_ini(ini, "SF Pro Text 12")
    got = ini.read_text()
    assert "gtk-application-prefer-dark-theme=1" in got
    assert "gtk-cursor-theme-name=Bibata" in got
    assert "gtk-font-name=SF Pro Text 12" in got
    assert "Cantarell" not in got


def test_sync_desktop_fonts_writes_gtk_and_kitty_only_in_xdg_sandbox(tmp_path):
    cfg = tmp_path / "config"
    state = tmp_path / "state"
    (cfg / "kuwai").mkdir(parents=True)
    (cfg / "kuwai" / "settings.json").write_text(json.dumps({"fontProfile": "sf-rounded", "monoFont": "maple"}))
    installed = {"SF Pro Text", "Maple Mono", "Geist Mono"}

    dry = sync_desktop_fonts(cfg, state, apply_live=False, dry_run=True, installed=installed)
    assert dry["dryRun"] is True
    assert not (cfg / "gtk-3.0" / "settings.ini").exists()

    res = sync_desktop_fonts(cfg, state, apply_live=False, dry_run=False, installed=installed)
    assert res["ok"] is True
    assert "gtk-font-name=SF Pro Text 12" in (cfg / "gtk-3.0" / "settings.ini").read_text()
    assert "gtk-font-name=SF Pro Text 12" in (cfg / "gtk-4.0" / "settings.ini").read_text()
    kitty = (state / "kuwai" / "look" / "fonts-kitty.conf").read_text()
    assert kitty == render_kitty_fonts("Maple Mono")


def test_cli_sync_fonts_no_apply_json(tmp_path):
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(tmp_path / "home"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
    }
    res = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), "sync-fonts", "--no-apply"],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert res.returncode == 0, res.stderr
    data = json.loads(res.stdout)
    assert data["ok"] is True
    assert (tmp_path / "state" / "kuwai" / "look" / "fonts-kitty.conf").is_file()
