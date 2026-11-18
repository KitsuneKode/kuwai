"""Wallpaper imports publish complete files and recover from unusable GPU encoders."""
import json
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def wall(tmp_path):
    home = tmp_path / 'home'
    library = home / 'Pictures/live-wallpapers'
    library.mkdir(parents=True)
    source = tmp_path / 'source.mp4'
    source.write_bytes(b'input')
    tools = tmp_path / 'tools'
    tools.mkdir()
    scripts = {
        'ffprobe': '#!/bin/sh\n[ "${FAIL_PROBE:-}" != 1 ] || exit 1\nprintf 6.0\n',
        'hyprctl': '#!/bin/sh\nprintf \'[{"height":1080}]\'\n',
        'ffmpeg': '''#!/usr/bin/python3
import os, sys
from pathlib import Path
args = sys.argv[1:]
if '-encoders' in args:
    print('h264_nvenc')
    sys.exit(0)
if os.environ.get('FAIL_ALL') or ('h264_nvenc' in args and os.environ.get('FAIL_GPU')):
    Path(args[-1]).write_bytes(b'incomplete')
    sys.exit(1)
Path(args[-1]).write_bytes(b'encoded')
''',
    }
    for name, content in scripts.items():
        path = tools / name
        path.write_text(content)
        path.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=f'{tools}:/usr/bin:/bin',
               XDG_CACHE_HOME=str(home / '.cache'), XDG_STATE_HOME=str(home / '.state'))
    def run(*args):
        return subprocess.run([str(ROOT / 'bin/kuwai-wall'), *args], env=env, capture_output=True, text=True, timeout=5)
    return run, source, library, env


def test_zero_padded_library_numbers_are_decimal(wall):
    run, source, library, _ = wall
    (library / '08-previous.mp4').touch()
    result = run('add', str(source), 'next', '--no-loop')
    assert result.returncode == 0, result.stderr
    assert (library / '9-next.mp4').read_bytes() == b'encoded'


def test_unusable_nvenc_falls_back_to_software_encoding(wall):
    run, source, library, env = wall
    env['FAIL_GPU'] = '1'
    result = run('add', str(source), 'fallback')
    assert result.returncode == 0, result.stderr
    assert (library / '1-fallback.mp4').read_bytes() == b'encoded'


def test_failed_encoding_does_not_publish_a_partial_wallpaper(wall):
    run, source, library, env = wall
    env['FAIL_ALL'] = '1'
    result = run('add', str(source), 'broken')
    assert result.returncode != 0
    assert not list(library.glob('*.mp4'))


def test_failed_probe_does_not_encode_or_publish(wall):
    run, source, library, env = wall
    env['FAIL_PROBE'] = '1'
    assert run('add', str(source)).returncode != 0
    assert not list(library.glob('*.mp4'))


def test_non_ascii_title_gets_a_nonempty_fallback_name(wall):
    run, source, library, _ = wall
    result = run('add', str(source), '日本語')
    assert result.returncode == 0, result.stderr
    assert (library / '1-wallpaper.mp4').is_file()


def test_json_preserves_newlines_in_filenames(wall):
    run, _, library, _ = wall
    path = library / '1-name\nwith newline.mp4'
    path.touch()
    result = run('json')
    assert result.returncode == 0, result.stderr
    rows = json.loads(result.stdout)
    assert len(rows) == 1
    assert rows[0]['path'] == str(path)


@pytest.mark.skipif(not (Path('/usr/bin/ffmpeg').exists() and Path('/usr/bin/ffprobe').exists()), reason='needs ffmpeg')
@pytest.mark.parametrize('loop', [True, False], ids=['crossfade-loop', 'as-is'])
def test_a_loop_is_made_in_colour_a_gpu_decodes(tmp_path, loop):
    """24 of 30 loops here came out H.264 4:4:4 from a 4:4:4 source: the crossfade renegotiated the
    format after `format=yuv420p`, and no GPU decodes 4:4:4, so they played on the CPU and held far
    more memory (bin/kuwai-livewall `playable` then had to make a copy of each)."""
    home = tmp_path / 'home'
    (home / 'Pictures/live-wallpapers').mkdir(parents=True)
    tools = tmp_path / 'tools'
    tools.mkdir()
    (tools / 'hyprctl').write_text('#!/bin/sh\nprintf \'[{"height":180}]\'\n')
    (tools / 'hyprctl').chmod(0o755)
    src = tmp_path / 'src.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=6',
                    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv444p', str(src)], check=True, timeout=60)
    env = dict(os.environ, HOME=str(home), PATH=f'{tools}:/usr/bin:/bin',
               XDG_CACHE_HOME=str(home / '.cache'), XDG_STATE_HOME=str(home / '.state'))
    args = [str(ROOT / 'bin/kuwai-wall'), 'add', str(src), 'colour'] + ([] if loop else ['--no-loop'])
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stderr
    out = next((home / 'Pictures/live-wallpapers').glob('*-colour.mp4'))
    fmt = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=pix_fmt',
                          '-of', 'csv=p=0', str(out)], capture_output=True, text=True).stdout.strip()
    assert fmt == 'yuv420p'
