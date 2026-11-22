"""kuwai on a machine without HyDE (docs/design/WITHOUT-HYDE.md): every place
that reads HyDE's files or runs its commands has a defined fallback.
- kuwai-themes lists nothing (and says why) instead of a traceback, and the
  switches that need HyDE's scripts refuse with the reason;
- lib/hyde.sh decides, and starts plain waybar (or nothing) without hyde-shell;
- the shell's singletons, started offscreen with an empty HOME
  (bin/kuwai-nohyde --strict), log nothing about HyDE and fall back to Theme's
  own accent, no wallpaper, and an emoji list marked missing."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import pytest

ROOT = Path(__file__).resolve().parents[1]


def bare_env(home, path=None):
    return {'PATH': path or '/usr/bin:/bin', 'HOME': str(home), 'LANG': 'C.UTF-8'}


def themes(home, *args):
    return subprocess.run(['python3', str(ROOT / 'bin/kuwai-themes'), *args], capture_output=True, text=True,
                          env=bare_env(home), timeout=30)


def test_themes_list_without_hyde_is_empty_and_says_so(tmp_path):
    r = themes(tmp_path, 'list')
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert d['themes'] == [] and d['wallpapers'] == [] and d['hyde'] is False


@pytest.mark.parametrize('args', [('theme', 'Any'), ('wallpaper', '/etc/hostname'), ('colormode', 'dark')])
def test_switches_without_hyde_refuse_with_the_reason(tmp_path, args):
    r = themes(tmp_path, *args)
    assert r.returncode == 3
    assert "HyDE isn't installed" in r.stderr and 'nothing changed' in r.stderr


def test_themes_with_hyde_marker_reports_it(tmp_path):
    (tmp_path / '.local/lib/hyde').mkdir(parents=True)
    (tmp_path / '.local/lib/hyde/globalcontrol.sh').write_text('# fixture\n')
    (tmp_path / '.config/hyde/themes').mkdir(parents=True)
    d = json.loads(themes(tmp_path, 'list').stdout)
    assert d['hyde'] is True


def sh(home, script, path):
    return subprocess.run([shutil.which('bash'), '-c', f'. "{ROOT}/lib/hyde.sh"; {script}'], capture_output=True, text=True,
                          env=bare_env(home, path), timeout=15)


def fake(tmp_path, *names):
    d = tmp_path / 'bin'
    d.mkdir(exist_ok=True)
    log = tmp_path / 'ran.log'
    for n in names:
        p = d / n
        p.write_text(f'#!/bin/sh\necho "{n} $*" >> "{log}"\n')
        p.chmod(0o755)
    for n in ('pgrep', 'setsid'):
        if n not in names:
            real = shutil.which(n)
            if real:
                (d / n).symlink_to(real)
    return d, log


def test_hyde_here_is_the_scripts_marker(tmp_path):
    assert sh(tmp_path, 'hyde_here', '/usr/bin:/bin').returncode == 1
    (tmp_path / '.local/lib/hyde').mkdir(parents=True)
    (tmp_path / '.local/lib/hyde/globalcontrol.sh').write_text('')
    assert sh(tmp_path, 'hyde_here', '/usr/bin:/bin').returncode == 0


def run_waybar(tmp_path, *names):
    d, log = fake(tmp_path, *names)
    # pgrep finds no waybar: a stub that says so (the real one would see the session's).
    (d / 'pgrep').unlink(missing_ok=True)
    (d / 'pgrep').write_text('#!/bin/sh\nexit 1\n')
    (d / 'pgrep').chmod(0o755)
    # Only the stand-ins on PATH (the real waybar may be installed here).
    r = sh(tmp_path, 'waybar_start', str(d))
    for _ in range(50):
        if log.exists():
            break
        time.sleep(0.05)
    return r, (log.read_text() if log.exists() else '')


def test_waybar_through_hyde_when_it_is_there(tmp_path):
    r, ran = run_waybar(tmp_path, 'hyde-shell', 'waybar')
    assert r.returncode == 0 and 'hyde-shell waybar' in ran


def test_plain_waybar_without_hyde(tmp_path):
    r, ran = run_waybar(tmp_path, 'waybar')
    assert r.returncode == 0 and ran.startswith('waybar')


def test_no_waybar_at_all_says_so(tmp_path):
    r, ran = run_waybar(tmp_path)
    assert r.returncode == 1 and ran == ''


def can_probe():
    if not (shutil.which('qs') and shutil.which('dbus-run-session') and shutil.which('unshare')):
        return False
    return subprocess.run(['unshare', '--map-current-user', '-n', '-p', '-f', '-m', '--mount-proc', 'true'],
                          capture_output=True).returncode == 0


@pytest.mark.skipif(not can_probe(), reason='needs qs, dbus-run-session and user namespaces')
def test_the_shell_without_hyde_is_quiet_and_falls_back(tmp_path):
    rev = os.environ.get('KUWAI_NOHYDE_REV', 'HEAD')
    r = subprocess.run([str(ROOT / 'bin/kuwai-nohyde'), '--strict', rev], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stdout + r.stderr
    out = r.stdout
    assert 'Hyde.present=false' in out and 'Hyde.hasShell=false' in out and 'Hyde.wallpaper=""' in out
    assert 'Theme.accent=#0a84ff' in out                     # Theme's own blue
    assert 'Glyphs.emojiMissing=false' in out and 'emoji=0' not in out
