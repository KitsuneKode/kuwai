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
