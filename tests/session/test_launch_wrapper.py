import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
def test_session_wrapper_preserves_exit_and_routes_diagnostics(tmp_path):
 tools=tmp_path/'tools';tools.mkdir();marker=tmp_path/'started'
 start=tools/'start-hyprland';start.write_text('#!/bin/sh\nprintf started > "$TEST_MARKER"\nexit 7\n');start.chmod(0o755)
 cat=tools/'systemd-cat';cat.write_text('#!/bin/sh\nshift 2\nif [ "$#" = 0 ]; then /usr/bin/cat >/dev/null; else exec "$@"; fi\n');cat.chmod(0o755)
 env=dict(os.environ,PATH=str(tools)+':/usr/bin:/bin',TEST_MARKER=str(marker),KUWAI_HANDOFF_ID='synthetic')
 result=subprocess.run(['sh',str(ROOT/'greeter/session-start')],env=env,capture_output=True,text=True)
 assert marker.read_text()=='started'
 assert result.returncode==7
