"""Dynamic names must reach Hyprland as values, never executable Lua."""
import json
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def dispatch(tmp_path):
    tool = tmp_path / 'hyprctl'
    log = tmp_path / 'dispatch.json'
    tool.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
if sys.argv[1] == 'repl':
    print('__LUA__' if os.environ.get('LUA_MODE', '1') == '1' else 'unknown request')
else:
    Path(os.environ['DISPATCH_LOG']).write_text(json.dumps(sys.argv[1:]))
''')
    tool.chmod(0o755)
    def run(function, *arguments, lua=True):
        log.unlink(missing_ok=True)
        env = dict(os.environ, PATH=f'{tmp_path}:/usr/bin:/bin', DISPATCH_LOG=str(log), LUA_MODE='1' if lua else '0')
        result = subprocess.run(['bash', '-c', 'source "$1"; shift; "$@"', 'test',
                                 str(ROOT / 'lib/dispatch.sh'), function, *arguments],
                                env=env, capture_output=True, text=True)
        return result, json.loads(log.read_text()) if log.exists() else None
    return run


@pytest.mark.parametrize('value', ["plain", "display'quoted", 'a"b\\c', 'x]==]y',
                                  'line1\nline2', "x'}); error('injected') --", '日本語'])
@pytest.mark.parametrize('function', ['d_focus_monitor', 'd_workspace', 'd_exec_float', 'd_layoutmsg'])
def test_lua_string_arguments_round_trip_without_execution(dispatch, function, value):
    result, args = dispatch(function, value)
    assert result.returncode == 0, result.stderr
    assert args[0] == 'dispatch'
    check = '''local captured
hl = { dsp = {
 focus = function(v) captured = v.monitor or v.workspace; return {} end,
 exec_cmd = function(v) captured = v; return {} end,
 layout = function(v) captured = v; return {} end
}, dispatch = function(_) end }
hl.dispatch(''' + args[1] + ''')
assert(captured == os.getenv('EXPECTED'), 'argument changed')
'''
    verified = subprocess.run(['lua', '-e', check], env=dict(os.environ, EXPECTED=value), capture_output=True, text=True)
    assert verified.returncode == 0, verified.stderr


@pytest.mark.parametrize('function', ['d_move_pixel', 'd_resize_pixel'])
def test_invalid_numeric_arguments_never_reach_dispatch(dispatch, function):
    result, args = dispatch(function, '0x123', '0});error("injected");--', '12')
    assert result.returncode != 0
    assert args is None


def test_classic_dispatch_keeps_dynamic_names_as_one_argument(dispatch):
    name = "a workspace ' with spaces"
    result, args = dispatch('d_workspace', name, lua=False)
    assert result.returncode == 0
    assert args == ['dispatch', 'workspace', name]
