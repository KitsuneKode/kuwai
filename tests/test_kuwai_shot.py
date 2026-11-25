"""Screenshot names must survive concurrent captures and cancelled selection."""
from pathlib import Path
import os
import subprocess
import pytest

ROOT = Path(__file__).resolve().parents[1]

@pytest.fixture
def capture(tmp_path):
    tools = tmp_path / 'tools'
    tools.mkdir()
    commands = {
        'date': '#!/bin/sh\necho 20261118_010000\n',
        'hyprctl': '#!/bin/sh\ncase "$*" in *monitors*) echo \'[{"activeWorkspace":{"id":1},"specialWorkspace":{"id":0}}]\';; *) echo \'[]\';; esac\n',
        'slurp': '#!/bin/sh\n[ "${CANCEL:-0}" = 1 ] && exit 1\necho "10,10 100x100"\n',
        'grim': '#!/usr/bin/python3\nimport os,sys,time\nfrom pathlib import Path\ntime.sleep(.1)\nPath(sys.argv[-1]).write_text(os.environ["CAPTURE_TEXT"])\n',
        'wl-copy': '#!/bin/sh\ncat >/dev/null\n',
    }
    for name, source in commands.items():
        p=tools/name; p.write_text(source); p.chmod(0o755)
    env=dict(os.environ, HOME=str(tmp_path), XDG_PICTURES_DIR=str(tmp_path/'pictures with spaces'), PATH=f'{tools}:/usr/bin:/bin')
    return env, tmp_path/'pictures with spaces/Screenshots'


def test_concurrent_same_second_screenshots_do_not_overwrite_each_other(capture):
    env, directory = capture
    runs=[subprocess.Popen([str(ROOT/'bin/kuwai-shot'),'quick'],env=dict(env,CAPTURE_TEXT=text),stdout=subprocess.PIPE,stderr=subprocess.PIPE) for text in ('first','second')]
    for run in runs:
        _,error=run.communicate(timeout=5)
        assert run.returncode==0,error
    files=list(directory.glob('*.png'))
    assert len(files)==2
    assert sorted(p.read_text() for p in files)==['first','second']


def test_cancelled_capture_leaves_no_empty_screenshot(capture):
    env, directory = capture
    result=subprocess.run([str(ROOT/'bin/kuwai-shot'),'quick'],env=dict(env,CANCEL='1'),capture_output=True,timeout=5)
    assert result.returncode==0,result.stderr
    assert not list(directory.glob('*.png'))


@pytest.mark.parametrize('mode,want', [('monitor', ['shot', '-o', 'DP-2']), ('all', ['shot'])])
def test_whole_screen_modes_need_only_grim(capture, tmp_path, mode, want):
    env, directory = capture
    tools = tmp_path / 'tools'
    (tools / 'hyprctl').write_text('#!/bin/sh\necho \'[{"name":"eDP-1","focused":false},{"name":"DP-2","focused":true}]\'\n')
    (tools / 'grim').write_text('#!/usr/bin/python3\nimport sys\nfrom pathlib import Path\nPath(sys.argv[-1]).write_text(" ".join(["shot"] + sys.argv[1:-1]))\n')
    (tools / 'satty').write_text('#!/bin/sh\nexit 0\n')
    for t in ('hyprctl', 'grim', 'satty'):
        (tools / t).chmod(0o755)
    r = subprocess.run([str(ROOT / 'bin/kuwai-shot'), mode], env=env, capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, r.stderr
    files = list(directory.glob('*.png'))
    assert len(files) == 1
    assert files[0].read_text().split() == want
