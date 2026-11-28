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


def _fake(tmp_path, *names):
    tools = tmp_path / 'tools'
    tools.mkdir(exist_ok=True)
    for name in names:
        tool = tools / name
        tool.write_text('#!/usr/bin/python3\nimport json,os,sys\nprint(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd()}))\n')
        tool.chmod(0o755)
    return tools


def _run(tmp_path, tools, args, terminal=None):
    env = dict(os.environ, HOME=str(tmp_path), PATH=str(tools) + ':/usr/bin:/bin')
    env.pop('KUWAI_TERMINAL', None)
    if terminal:
        env['KUWAI_TERMINAL'] = terminal
    return subprocess.run(['/bin/bash', str(ROOT / 'bin/kuwai-term'), *args], env=env, capture_output=True, text=True)


HOSTILE = ['/opt/sweep/bin/sweep', 'ui', '$(touch pwned)', 'a b;c', "it's", '--view', 'projects']


@pytest.mark.parametrize('terminal,expected', [
    ('kitty', ['--single-instance', '--instance-group=local', '--title', 'sweep', '--directory', '{dir}', *HOSTILE]),
    ('ghostty', ['--working-directory={dir}', '--title=sweep', '-e', *HOSTILE]),
    ('foot', ['--working-directory={dir}', '--title=sweep', *HOSTILE]),
    ('alacritty', ['--working-directory', '{dir}', '--title', 'sweep', '-e', *HOSTILE]),
    ('wezterm', ['start', '--cwd', '{dir}', '--', *HOSTILE]),
    ('konsole', ['--workdir', '{dir}', '-p', 'tabtitle=sweep', '-e', *HOSTILE]),
    ('gnome-terminal', ['--working-directory={dir}', '--title=sweep', '--', *HOSTILE]),
    ('xfce4-terminal', ['--working-directory={dir}', '--title=sweep', '-x', *HOSTILE]),
    ('xterm', ['-T', 'sweep', '-e', *HOSTILE]),
])
def test_a_command_reaches_each_terminal_as_separate_arguments(tmp_path, terminal, expected):
    work = tmp_path / 'work dir'
    work.mkdir()
    tools = _fake(tmp_path, terminal)
    result = _run(tmp_path, tools, ['--title', 'sweep', '--dir', str(work), '--', *HOSTILE], terminal)
    assert result.returncode == 0, result.stderr
    out = json.loads(result.stdout)
    assert out['argv'] == [a.format(dir=work) for a in expected]
    assert not (tmp_path / 'pwned').exists()
    if terminal == 'xterm':
        assert out['cwd'] == str(work)


def test_kitty_waits_for_the_window_when_asked(tmp_path):
    tools = _fake(tmp_path, 'kitty')
    result = _run(tmp_path, tools, ['--wait', '--', '/usr/bin/true'], 'kitty')
    argv = json.loads(result.stdout)['argv']
    assert '--wait-for-single-instance-window-close' in argv
    assert argv[-1] == '/usr/bin/true'


def test_hold_keeps_the_command_as_arguments_after_a_fixed_script(tmp_path):
    tools = _fake(tmp_path, 'foot')
    result = _run(tmp_path, tools, ['--hold', '--', '/usr/bin/false', 'x y'], 'foot')
    argv = json.loads(result.stdout)['argv']
    i = argv.index('bash')
    assert argv[i + 1] == '-c'
    assert argv[i + 3:] == ['kuwai-term', '/usr/bin/false', 'x y']
    assert 'x y' not in argv[i + 2]


def test_a_custom_terminal_is_split_into_words_never_run_through_a_shell(tmp_path):
    tools = _fake(tmp_path, 'myterm')
    result = _run(tmp_path, tools, ['--', '/usr/bin/echo', '$(id)'], 'myterm --class x')
    assert json.loads(result.stdout)['argv'] == ['--class', 'x', '-e', '/usr/bin/echo', '$(id)']


def test_the_old_forms_still_work(tmp_path):
    tools = _fake(tmp_path, 'foot')
    printed = _run(tmp_path, tools, ['--dir'])
    assert printed.returncode == 0 and printed.stdout.strip() == str(tmp_path)
    child = subprocess.Popen(['sleep', '5'], cwd='/usr')
    try:
        by_pid = _run(tmp_path, tools, ['--dir', str(child.pid)])
        assert by_pid.stdout.strip() == '/usr'
        opened = _run(tmp_path, tools, [str(child.pid)], 'foot')
        assert json.loads(opened.stdout)['argv'] == ['--working-directory=/usr']
    finally:
        child.kill()
    assert _run(tmp_path, tools, ['--dir', '999999999']).stdout.strip() == str(tmp_path)


@pytest.mark.parametrize('args', [['--', '-e', 'x'], ['--title'], ['--bogus'], ['--title', 'a\nb', '--', '/bin/true'], ['1', '2']])
def test_malformed_requests_are_refused(tmp_path, args):
    tools = _fake(tmp_path, 'foot')
    result = _run(tmp_path, tools, args, 'foot')
    assert result.returncode == 2
    assert result.stdout == ''


def test_a_missing_folder_is_refused_without_naming_it(tmp_path):
    tools = _fake(tmp_path, 'foot')
    result = _run(tmp_path, tools, ['--dir', str(tmp_path / 'gone'), '--', '/bin/true'], 'foot')
    assert result.returncode == 1 and result.stdout == ''
    assert str(tmp_path) not in result.stderr
