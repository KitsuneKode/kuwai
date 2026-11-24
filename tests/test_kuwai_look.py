"""Standalone kuwai-look pipeline, WCAG contrast roles, atomic swap, undo, and Lua consumption."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "lib") not in sys.path:
    sys.path.insert(0, str(ROOT / "lib"))

from look.render import write_generation
from look.roles import build_palette, contrast_ratio


def run_look(env, *args):
    return subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-look"), *args],
        env=env, capture_output=True, text=True, timeout=30,
    )


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


def test_build_palette_enforces_wcag_contrast_in_dark_and_light():
    for mode in ("dark", "light"):
        pal = build_palette(
            {"bg": "#222230", "fg": "#444455", "accent": "#223344", "secondary": "#336655"},
            source={"kind": "wallpaper", "name": "fixture", "wallpaper": "/tmp/a.png", "mode": mode},
            generation="1",
            mode=mode,
        )
        r = pal["role"]
        assert contrast_ratio(r["fg"], r["bg"]) >= 7.0
        assert contrast_ratio(r["fgDim"], r["bg"]) >= 4.5
        assert contrast_ratio(r["accent"], r["bg"]) >= 3.5
        assert contrast_ratio(r["onAccent"], r["accent"]) >= 4.5
        assert len(pal["ansi"]) == 16


def test_write_generation_swaps_atomically_renders_custom_templates_and_prunes(tmp_path):
    look_dir = tmp_path / "look"
    tpl_dir = tmp_path / "templates"
    tpl_dir.mkdir()
    (tpl_dir / "custom.css.tpl").write_text("accent={{ role.accent }} strip={{ role.accent.strip }}\n")

    for i in range(5):
        pal = build_palette(
            {"bg": "#111114", "accent": f"#66{i}7ff"},
            source={"kind": "default", "name": f"g{i}", "wallpaper": "", "mode": "dark"},
            generation=str(100 + i),
            mode="dark",
        )
        gen_dir, state = write_generation(str(look_dir), pal, custom_templates_dir=str(tpl_dir), keep=3)
        os.utime(gen_dir, (1000 + i, 1000 + i))

    cur = look_dir / "current"
    assert cur.is_symlink() and os.readlink(cur) == "gen-104"
    assert (cur / "palette.json").is_file()
    assert (cur / "palette.lua").is_file()
    assert (cur / "kitty.conf").is_file()
    assert (cur / "gtk.css").is_file()
    assert (cur / "qtct.conf").is_file()
    custom = (cur / "custom.css").read_text()
    assert "{{" not in custom and "accent=#" in custom and "strip=" in custom
    gens = [d.name for d in look_dir.iterdir() if d.name.startswith("gen-")]
    assert len(gens) == 3 and "gen-104" in gens


def test_cli_init_theme_mode_and_undo_without_hyde(tmp_path):
    env = look_env(tmp_path)
    r = run_look(env, "init", "--no-apply")
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert d["ok"] is True
    gen1 = d["state"]["generation"]

    r2 = run_look(env, "mode", "light", "--no-apply")
    assert r2.returncode == 0, r2.stderr
    d2 = json.loads(r2.stdout)
    assert d2["palette"]["mode"] == "light"
    assert d2["state"]["previous"] == f"gen-{gen1}"

    r3 = run_look(env, "undo", "--no-apply")
    assert r3.returncode == 0, r3.stderr
    d3 = json.loads(r3.stdout)
    assert d3["palette"]["mode"] == "dark"
    assert d3["state"]["generation"] == gen1

    st = json.loads(run_look(env, "status").stdout)
    assert st["initialized"] is True and st["palette"]["schema"] == 1


def test_hyprland_theme_lua_reads_kuwai_palette_without_hyde(tmp_path):
    env = look_env(tmp_path)
    assert run_look(env, "init", "--no-apply").returncode == 0
    lua_code = f"""
package.path = '{ROOT}/hypr/?.lua;' .. package.path
_G.hl = setmetatable({{ on = function() end, config = function() end }}, {{ __index = function() return function() end end }})
local K = dofile('{ROOT}/hypr/kuwai/core.lua')
assert(K.hyde == false, 'expected no hyde')
package.loaded['kuwai.core'] = K
local T = dofile('{ROOT}/hypr/kuwai/theme.lua')
T.apply()
assert(T.kuwai ~= nil, 'expected kuwai palette loaded')
assert(T.colors.accent ~= nil and T.colors.pry3 == T.colors.accent, 'accent mapped')
assert(T.name == 'Kuwai Night', 'theme name preserved')
print('lua_look_ok')
"""
    r = subprocess.run(["lua", "-e", lua_code], env=env, capture_output=True, text=True, timeout=15)
    assert r.returncode == 0 and "lua_look_ok" in r.stdout, r.stdout + r.stderr


def test_all_shipped_themes_have_native_toml_and_apply_cleanly(tmp_path):
    env = look_env(tmp_path)
    themes = sorted(p for p in (ROOT / "themes").iterdir() if p.is_dir())
    assert len(themes) >= 11
    for theme in themes:
        assert (theme / "theme.toml").is_file(), theme.name
        assert (theme / "palette.toml").is_file(), theme.name
        r = run_look(env, "theme", theme.name, "--no-apply")
        assert r.returncode == 0, f"{theme.name}: {r.stderr}"
        pal = json.loads(r.stdout)["palette"]
        role = pal["role"]
        assert contrast_ratio(role["fg"], role["bg"]) >= 7.0, theme.name
        assert contrast_ratio(role["accent"], role["bg"]) >= 3.5, theme.name
    listed = json.loads(run_look(env, "list").stdout)
    assert len(listed["themes"]) == len(themes)
    assert listed["modes"] == ["theme", "auto", "dark", "light"]
    assert all(t["bg"].startswith("#") and t["accent"].startswith("#") and t["palette"] for t in listed["themes"])


def init_git_repo(repo_dir):
    subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.email", "t@kuwai.test"], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.name", "Kuwai Test"], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init"], check=True)


def test_install_accepts_safe_theme_and_rejects_scripts_and_symlinks(tmp_path):
    env = look_env(tmp_path)

    good = tmp_path / "good-theme"
    good.mkdir()
    (good / "theme.toml").write_text('schema = 1\nslug = "good-theme"\nname = "Good Theme"\n')
    (good / "palette.toml").write_text('[colors]\nbg = "#101218"\nfg = "#f0f2f6"\naccent = "#55ccff"\n')
    init_git_repo(good)

    r = run_look(env, "install", str(good))
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert d["ok"] is True and d["slug"] == "good-theme"
    r_apply = run_look(env, "theme", "good-theme", "--no-apply")
    assert r_apply.returncode == 0, r_apply.stderr

    bad_script = tmp_path / "evil-script"
    bad_script.mkdir()
    (bad_script / "palette.toml").write_text('[colors]\nbg = "#101218"\nfg = "#f0f2f6"\naccent = "#55ccff"\n')
    (bad_script / "install.sh").write_text("#!/bin/sh\necho pwned\n")
    init_git_repo(bad_script)
    r_bad = run_look(env, "install", str(bad_script))
    assert r_bad.returncode != 0 and "rejected" in r_bad.stderr

    bad_link = tmp_path / "evil-link"
    bad_link.mkdir()
    (bad_link / "palette.toml").write_text('[colors]\nbg = "#101218"\nfg = "#f0f2f6"\naccent = "#55ccff"\n')
    (bad_link / "README.md").symlink_to("/etc/passwd")
    init_git_repo(bad_link)
    r_link = run_look(env, "install", str(bad_link))
    assert r_link.returncode != 0 and "symlink" in r_link.stderr


def test_home_app_include_configs_are_portable():
    for rel in (
        "home/.config/kitty/kuwai.conf",
        "home/.config/gtk-3.0/kuwai.css",
        "home/.config/gtk-4.0/kuwai.css",
        "home/.config/qt6ct/kuwai.conf",
    ):
        text = (ROOT / rel).read_text()
        assert "kitsunekode" not in text and "hyde" not in text.lower()
