"""Recording commands must not signal stale PIDs or lose paths with spaces."""
import json
import os
from pathlib import Path
import signal
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def recorder(tmp_path):
    tools = tmp_path / 'tools'
    tools.mkdir()
    state = tmp_path / 'state/kuwai/recording'
    state.parent.mkdir(parents=True)
    marker = tmp_path / 'started'
    inputs = tmp_path / 'ffmpeg-inputs'
    helper = tools / 'gpu-screen-recorder'
    helper.write_text('''#!/usr/bin/python3
import json, os, signal, sys
from pathlib import Path
if os.environ.get('FAIL_START'): sys.exit(1)
with open(os.environ['REC_TEST_STARTED'], 'a') as f: f.write(str(os.getpid()) + '\\n')
path = Path(sys.argv[sys.argv.index('-o') + 1])
path.write_bytes(b'recording')
def stop(*_):
    path.write_bytes(b'finalized')
    sys.exit(0)
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
while True: signal.pause()
''')
    helper.chmod(0o755)
    ffmpeg = tools / 'ffmpeg'
    ffmpeg.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
Path(os.environ['REC_TEST_INPUTS']).write_text(json.dumps(sys.argv[sys.argv.index('-i') + 1]))
Path(sys.argv[-1]).write_bytes(b'thumbnail')
''')
    ffmpeg.chmod(0o755)
    hypr = tools / 'hyprctl'
    hypr.write_text('#!/bin/sh\nprintf \'[{"name":"DP-1","focused":true}]\'\n')
    hypr.chmod(0o755)
    notify = tools / 'notify-send'
    notify.write_text('#!/bin/sh\nexit 0\n')
    notify.chmod(0o755)
    env = dict(os.environ, PATH=f'{tools}:/usr/bin:/bin', HOME=str(tmp_path),
               XDG_STATE_HOME=str(state.parent.parent), XDG_VIDEOS_DIR=str(tmp_path / 'videos with spaces'),
               REC_TEST_STARTED=str(marker), REC_TEST_INPUTS=str(inputs))
    def run(*args):
        return subprocess.run([str(ROOT / 'bin/kuwai-rec'), *args], env=env,
                              capture_output=True, text=True, timeout=8)
    yield run, state, marker, inputs, env
    if marker.exists():
        for pid in marker.read_text().splitlines():
            try: os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError: pass


def test_stale_state_never_signals_an_unrelated_live_process(recorder, tmp_path):
    run, state, _, _, _ = recorder
    process = subprocess.Popen(['/usr/bin/sleep', '30'])
    try:
        state.write_text(f'{process.pid} 123 {tmp_path}/old.mp4 DP-1\n')
        result = run('stop')
        assert result.returncode == 0, result.stderr
        assert process.poll() is None
        assert not state.with_name('recording-saved').exists()
    finally:
        process.terminate()
        process.wait(timeout=3)


@pytest.mark.parametrize('args', [('DP-1', 'unknown', '60'), ('DP-1', 'none', '0'),
                                  ('DP-1', 'none', 'abc'), ('--help', 'none', '60')])
def test_invalid_recording_options_are_rejected_before_launch(recorder, args):
    run, _, marker, _, _ = recorder
    result = run('start', *args)
    assert result.returncode != 0
    assert not marker.exists()


def test_stop_uses_the_complete_path_and_publishes_a_finalized_recording(recorder):
    run, state, _, inputs, _ = recorder
    started = run('start', 'DP-1', 'none', '30')
    assert started.returncode == 0, started.stderr
    stopped = run('stop')
    assert stopped.returncode == 0, stopped.stderr
    path = Path(json.loads(inputs.read_text()))
    assert path.read_bytes() == b'finalized'
    assert 'videos with spaces' in str(path)
    fields = state.with_name('recording-saved').read_text().rstrip('\n').split('\t')
    assert fields[2] == str(path)
    assert not state.exists()


def test_concurrent_starts_launch_only_one_recorder(recorder):
    _, _, marker, _, env = recorder
    commands = [subprocess.Popen([str(ROOT / 'bin/kuwai-rec'), 'start', 'DP-1', 'none', '30'],
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
    for command in commands:
        stdout, stderr = command.communicate(timeout=5)
        assert command.returncode == 0, stderr
    assert len(marker.read_text().splitlines()) == 1


def test_dead_recorder_state_is_cleared_without_claiming_it_was_saved(recorder):
    run, state, marker, _, _ = recorder
    assert run('start', 'DP-1', 'none', '30').returncode == 0
    os.kill(int(marker.read_text().strip()), signal.SIGKILL)
    result = run('status')
    assert result.stdout.strip() == 'idle'
    assert not state.exists()
    assert not state.with_name('recording-saved').exists()


def test_failed_state_publication_stops_our_new_recorder(recorder):
    run, state, marker, _, env = recorder
    tool = Path(env['PATH'].split(':')[0]) / 'mv'
    tool.write_text('#!/bin/sh\nexit 1\n')
    tool.chmod(0o755)
    result = run('start', 'DP-1', 'none', '30')
    assert result.returncode != 0
    assert not state.exists()
    pid = int(marker.read_text().strip())
    # A zombie is terminated; it is reaped by the fixture's process owner.
    stat = Path(f'/proc/{pid}/stat')
    import time
    for _ in range(30):
        if not stat.exists() or stat.read_text().split(') ', 1)[1].startswith('Z'): break
        time.sleep(0.05)
    else:
        pytest.fail('state publication failed but the recorder kept running')
