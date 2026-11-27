"""bin/kuwai-icons: the mid-session icon fallback the shell asks.

Qt never rescans a theme in-process, so a freshly installed app's icon only
exists on disk. These probe the helper the shell shells out to: real files in
the right places are found in the right order, and anything off the
freedesktop name rules — or a symlink escaping the directory searched — is
not.
"""
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / "bin/kuwai-icons"


def run(names, env):
    return subprocess.run([sys.executable, str(HELPER), "resolve"] + names, capture_output=True, text=True, env=env)


def xdg(tmp_path, home="home", dirs=("sys",)):
    h = tmp_path / home
    h.mkdir()
    ds = []
    for d in dirs:
        (tmp_path / d).mkdir()
        ds.append(str(tmp_path / d))
    return {"XDG_DATA_HOME": str(h), "XDG_DATA_DIRS": ":".join(ds), "PATH": os.environ.get("PATH", "")}, h, [tmp_path / d for d in dirs]


def put(base, size, name, ext="png"):
    d = base / "icons/hicolor" / size / "apps"
    d.mkdir(parents=True, exist_ok=True)
    f = d / (name + "." + ext)
    f.write_bytes(b"x")
    return f


def found(out):
    return dict(line.split("\t") for line in out.stdout.strip().splitlines() if "\t" in line)


def test_hicolor_256_only_like_ardia(tmp_path):
    env, home, _ = xdg(tmp_path)
    f = put(home, "256x256", "ardia")
    assert found(run(["ardia"], env))["ardia"] == str(f)


def test_scalable_svg_wins_over_fixed_png(tmp_path):
    env, home, _ = xdg(tmp_path)
    put(home, "256x256", "app")
    svg = put(home, "scalable", "app", "svg")
    assert found(run(["app"], env))["app"] == str(svg)


def test_largest_fixed_size_wins(tmp_path):
    env, home, _ = xdg(tmp_path)
    put(home, "48x48", "app")
    big = put(home, "512x512", "app")
    assert found(run(["app"], env))["app"] == str(big)


def test_pixmaps_is_the_last_resort(tmp_path):
    env, home, _ = xdg(tmp_path)
    pix = home / "pixmaps"
    pix.mkdir()
    f = pix / "old.png"
    f.write_bytes(b"x")
    assert found(run(["old"], env))["old"] == str(f)
    h = put(home, "16x16", "old")
    assert found(run(["old"], env))["old"] == str(h)


def test_home_beats_system_and_unknown_is_silent(tmp_path):
    env, home, sysdirs = xdg(tmp_path)
    mine = put(home, "48x48", "app")
    put(sysdirs[0], "256x256", "app")
    out = found(run(["app", "missing-xyz"], env))
    assert out["app"] == str(mine) and "missing-xyz" not in out


def test_names_off_the_charset_are_never_probed(tmp_path):
    env, home, _ = xdg(tmp_path)
    put(home, "256x256", "app")
    evil = home / "icons/hicolor/256x256/apps" / "evil.png"
    evil.write_bytes(b"x")
    r = run(["../evil", "a/b", "..", "name with space", "x" * 129, ""], env)
    assert r.stdout.strip() == "" and r.returncode == 0


def test_symlink_escaping_the_directory_is_rejected(tmp_path):
    env, home, _ = xdg(tmp_path)
    outside = tmp_path / "secret.png"
    outside.write_bytes(b"x")
    d = home / "icons/hicolor/256x256/apps"
    d.mkdir(parents=True)
    (d / "evil.png").symlink_to(outside)
    assert "evil" not in found(run(["evil"], env))


def test_symlink_staying_inside_is_fine(tmp_path):
    env, home, _ = xdg(tmp_path)
    real = put(home, "256x256", "real")
    d = home / "icons/hicolor/256x256/apps"
    (d / "alias.png").symlink_to(real)
    assert found(run(["alias"], env))["alias"] == str(real)
