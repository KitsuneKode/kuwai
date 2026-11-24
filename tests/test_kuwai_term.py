import json
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize('terminal,arguments', [('kitty', ['--single-instance', '--instance-group=local', '--directory']),
                                              ('ghostty', []), ('foot', [])])
def test_terminal_launch_does_not_require_nvidia_prime_run(tmp_path, terminal, arguments):
    tools = tmp_path / 'tools'
    tools.mkdir()
    tool = tools / terminal
    tool.write_text('#!/usr/bin/python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
    tool.chmod(0o755)
    env = dict(os.environ, HOME=str(tmp_path), PATH=str(tools), KUWAI_TERMINAL=terminal)
    result = subprocess.run(['/bin/bash', str(ROOT / 'bin/kuwai-term')], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    expected = [*arguments, str(tmp_path)] if terminal == 'kitty' else [f'--working-directory={tmp_path}']
    assert json.loads(result.stdout) == expected


@pytest.mark.parametrize('installed,expected', [(['alacritty'], ['--working-directory', '{home}']),
                                                (['foot', 'xterm'], ['--working-directory={home}']),
                                                (['wezterm'], ['start', '--cwd', '{home}'])])
def test_without_kitty_the_first_installed_terminal_opens(tmp_path, installed, expected):
    tools = tmp_path / 'tools'
    tools.mkdir()
    for name in installed:
        tool = tools / name
        tool.write_text('#!/usr/bin/python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        tool.chmod(0o755)
    env = dict(os.environ, HOME=str(tmp_path), PATH=str(tools))
    env.pop('KUWAI_TERMINAL', None)
    result = subprocess.run(['/bin/bash', str(ROOT / 'bin/kuwai-term')], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == [a.format(home=tmp_path) for a in expected]


def test_with_no_terminal_it_says_so_instead_of_failing_silently(tmp_path):
    tools = tmp_path / 'tools'
    tools.mkdir()
    (tools / 'notify-send').write_text('#!/bin/sh\necho "$@" > "$HOME/said"\n')
    (tools / 'notify-send').chmod(0o755)
    env = dict(os.environ, HOME=str(tmp_path), PATH=str(tools))
    env.pop('KUWAI_TERMINAL', None)
    result = subprocess.run(['/bin/bash', str(ROOT / 'bin/kuwai-term')], env=env, capture_output=True, text=True)
    assert result.returncode == 1
    assert 'No terminal installed' in (tmp_path / 'said').read_text()
