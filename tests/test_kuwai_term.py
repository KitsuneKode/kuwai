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
