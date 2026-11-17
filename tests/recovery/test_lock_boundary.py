"""No live locking: every session command resolves to a temporary stub."""
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]

def run_lock(tmp_path, shell_ready):
    stubs=tmp_path/'bin'; stubs.mkdir()
    for name,body in {
        'qs': 'case "$*" in *"call lock state"*) echo locked;; *) exit '+('0' if shell_ready else '1')+';; esac',
        'pidof':'exit 0',  # A process can persist without acquiring the lock.
        'hyprlock':'exit 0', 'setsid':'exit 0', 'sleep':'exit 0'
    }.items():
        p=stubs/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
    env=dict(os.environ,PATH=str(stubs)+':/usr/bin:/bin',HOME=str(tmp_path),XDG_CONFIG_HOME=str(tmp_path/'config'))
    return subprocess.run([str(ROOT/'bin/rice'),'lock','--wait'],env=env,capture_output=True,text=True,timeout=3)


def test_wait_does_not_certify_a_living_fallback_process_as_a_ready_lock(tmp_path):
    result=run_lock(tmp_path,False)
    assert result.returncode != 0
    assert 'readiness' in result.stderr


def test_wait_accepts_the_shell_lock_acknowledgement(tmp_path):
    result=run_lock(tmp_path,True)
    assert result.returncode == 0,result.stderr
