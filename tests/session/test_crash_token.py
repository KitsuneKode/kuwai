"""A crash card is the crash alert's only when it carries the alert's one-time token.

Any app (a website's notification, a sandboxed app) could send the
x-kuwai-crash hint, and the card's Diagnose briefs the assistant with its body.
kuwai-crash-alert writes a fresh token to a file only you can read and sends
it in the hint; the shell trusts the card only when the two match.
"""
import os
import shutil
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_the_alert_sends_the_token_it_keeps_privately(tmp_path):
    fake = tmp_path / "kuwai" / "bin"
    fake.mkdir(parents=True)
    shutil.copy(ROOT / "bin/kuwai-crash-alert", fake / "kuwai-crash-alert")
    (fake / "kuwai-notify").write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$OUT"\n')
    (fake / "kuwai-notify").chmod(0o755)
    run = tmp_path / "run"
    run.mkdir(mode=0o700)
    out = tmp_path / "args"
    r = subprocess.run([str(fake / "kuwai-crash-alert"), "the brief"], capture_output=True, text=True, timeout=20,
                       env={**os.environ, "XDG_RUNTIME_DIR": str(run), "OUT": str(out)})
    assert r.returncode == 0, r.stderr
    token_file = run / "kuwai" / "crash-token"
    token = token_file.read_text()
    assert len(token) == 32 and stat.S_IMODE(token_file.stat().st_mode) == 0o600
    assert f"x-kuwai-crash={token}" in out.read_text().splitlines()


def test_the_shell_matches_only_that_token():
    src = (ROOT / "shell/services/NotifAdapters.qml").read_text()
    assert 'n.hints["x-kuwai-crash"] === Crashes.token' in src
    assert "Crashes.token.length >= 32" in src
