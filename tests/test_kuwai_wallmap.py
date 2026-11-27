"""bin/kuwai-wallmap on a machine that has never made a map: the cache folder doesn't exist yet.

The cut-out model saves its mask into the cache before the map is built; with no folder there the
save failed, every picture read as "no subject", and the wallpaper change never drew a subject."""
import os
import stat
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def test_first_map_on_a_fresh_cache(tmp_path):
    data, cache = tmp_path / "data", tmp_path / "cache"
    venv_bin = data / "kuwai-data/cutout/venv/bin"
    venv_bin.mkdir(parents=True)
    # A stand-in for the model's python: argv = -I -c SCRIPT PICTURE OUT; it writes a mask to OUT
    # (a centred white block) the way the real one does, and fails if OUT's folder isn't there.
    mask = tmp_path / "mask.png"
    m = np.zeros((90, 160), dtype=np.uint8)
    m[20:70, 50:110] = 255
    Image.fromarray(m, "L").save(mask)
    py = venv_bin / "python"
    py.write_text(f'#!/bin/sh\ncp "{mask}" "$5"\n')
    py.chmod(py.stat().st_mode | stat.S_IXUSR)
    picture = tmp_path / "wall.png"
    Image.new("RGB", (1600, 900), (20, 20, 30)).save(picture)

    env = {**os.environ, "XDG_DATA_HOME": str(data), "XDG_CACHE_HOME": str(cache), "KUWAI_WALLMAP_ROOM_KB": "0"}
    r = subprocess.run([sys.executable, str(ROOT / "bin/kuwai-wallmap"), str(picture)], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    out = Path(r.stdout.strip())
    assert out.exists() and out.parent == cache / "kuwai/wallmaps"
    # and the second time it is the cached one
    again = subprocess.run([sys.executable, str(ROOT / "bin/kuwai-wallmap"), "--cached", str(picture)], env=env, capture_output=True, text=True, timeout=60)
    assert again.returncode == 0 and Path(again.stdout.strip()) == out


def test_without_the_model_a_miss_says_so_and_nothing_is_started(tmp_path):
    picture = tmp_path / "wall.png"
    picture.write_bytes(b"\x89PNG\r\n\x1a\n")
    env = dict(os.environ, HOME=str(tmp_path), XDG_DATA_HOME=str(tmp_path / "data"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    r = subprocess.run([sys.executable, str(ROOT / "bin/kuwai-wallmap"), "--cached", str(picture)], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 2, "WallFx starts a background map only on a miss with the model there (exit 1)"
    assert "if (code === 1 && root.phase" in (ROOT / "shell/services/WallFx.qml").read_text()


def test_the_cut_out_runs_alone_in_its_own_capped_scope_and_only_with_room():
    src = (Path(__file__).resolve().parents[1] / "bin/kuwai-wallmap").read_text()
    assert "fcntl.LOCK_EX | fcntl.LOCK_NB" in src, "a second cut-out while one runs is skipped, never stacked (two filled 24 GB on 2026-11-27)"
    assert '"systemd-run", "--user", "--scope"' in src and '"MemoryMax=" + CUTOUT_MEMORY' in src and '"MemorySwapMax=0"' in src
    assert "if available_kb() < CUTOUT_ROOM:" in src
    assert "o.enable_cpu_mem_arena = False" in src
