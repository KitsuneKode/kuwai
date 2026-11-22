import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a4c40000000049454e44ae426082")


def env(tmp):
    stub = tmp / "stub"
    stub.mkdir(exist_ok=True)
    (stub / "awww").write_text('#!/bin/sh\necho "$*" >> "$AWWW_LOG"\n')
    (stub / "awww").chmod(0o755)
    return {"HOME": str(tmp), "XDG_STATE_HOME": str(tmp / "state"), "AWWW_LOG": str(tmp / "awww.log"), "PATH": f"{stub}:{os.environ['PATH']}"}


def wall(tmp, *args):
    return subprocess.run([str(ROOT / "bin/kuwai-wall"), *args], env=env(tmp), capture_output=True, text=True)


def test_set_draws_it_and_keeps_it_for_the_next_login(tmp_path):
    img = tmp_path / "sea.png"
    img.write_bytes(PNG)
    assert wall(tmp_path, "set", str(img)).returncode == 0
    assert (tmp_path / "state/kuwai/wallpaper").resolve() == img.resolve()
    log = (tmp_path / "awww.log").read_text()
    assert f"img {img}" in log
    (tmp_path / "awww.log").unlink()
    assert wall(tmp_path, "restore").returncode == 0
    assert "img" in (tmp_path / "awww.log").read_text()


def test_not_an_image_or_nothing_kept(tmp_path):
    txt = tmp_path / "notes.txt"
    txt.write_text("hello")
    r = wall(tmp_path, "set", str(txt))
    assert r.returncode != 0 and "not an image" in r.stderr
    assert not (tmp_path / "state/kuwai/wallpaper").exists()
    assert wall(tmp_path, "restore").returncode == 0 and not (tmp_path / "awww.log").exists()
