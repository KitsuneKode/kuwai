"""A crash card is the crash alert's only when it carries the alert's one-time token.

Any app (a website's notification, a sandboxed app) could send the
x-kuwai-crash hint, and the card's Diagnose briefs the assistant with its body.
kuwai-crash-alert writes a fresh token to a file only you can read and sends
it in the hint; the shell trusts the card only when the two match.
"""
import os
import re
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
    crashes = (ROOT / "shell/services/Crashes.qml").read_text()
    assert 'h.length < 32) return false' in crashes and "return h === token;" in crashes
    assert "blockLoading: true" in crashes, "the token is read before the card is matched, never after"
    assert "match: n => Crashes.isAlert(n)," in (ROOT / "shell/services/NotifAdapters.qml").read_text()
    notifs = (ROOT / "shell/services/Notifs.qml").read_text()
    assert "if (Crashes.isAlert(n)) {" in notifs, "Diagnose acts on the same check the card was matched by"
    assert '"x-kuwai-crash"] === "1"' not in notifs


def test_the_card_says_what_crashed_and_keeps_the_details_for_diagnose(tmp_path):
    fake = tmp_path / "kuwai" / "bin"
    fake.mkdir(parents=True)
    shutil.copy(ROOT / "bin/kuwai-crash-alert", fake / "kuwai-crash-alert")
    (fake / "kuwai-notify").write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$OUT"\n')
    (fake / "kuwai-notify").chmod(0o755)
    run = tmp_path / "run"
    run.mkdir(mode=0o700)
    out = tmp_path / "args"
    r = subprocess.run([str(fake / "kuwai-crash-alert"), "PID 808 dumped core", "/usr/bin/Xwayland", "6"], capture_output=True,
                       text=True, timeout=20, env={**os.environ, "XDG_RUNTIME_DIR": str(run), "OUT": str(out)})
    assert r.returncode == 0, r.stderr
    args = out.read_text().splitlines()
    assert "Xwayland crashed" in args and "/usr/bin/Xwayland" not in "\n".join(args[-2:])
    assert "x-kuwai-brief=PID 808 dumped core" in args


def test_a_card_with_a_field_its_adapter_leaves_out_is_still_shown():
    src = (ROOT / "shell/services/NotifItem.qml").read_text()
    body = src[src.index("function apply(n, a)"):src.index("severity = a.severity")]
    plain = re.findall(r"^\s*\w+ = a\.\w+;$", body, re.M)
    assert not plain, f"an undefined field throws and drops the whole card (the crash card did): {plain}"
