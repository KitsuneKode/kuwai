"""The kuwai login session: its launcher and the sudo step that lists it."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def launch(tmp_path, files):
    home = tmp_path / 'home'
    for rel, text in files.items():
        (home / rel).parent.mkdir(parents=True, exist_ok=True)
        (home / rel).write_text(text)
    tools = tmp_path / 'tools'
    tools.mkdir(exist_ok=True)
    (tools / 'start-hyprland').write_text('#!/bin/sh\necho "start-hyprland $*"\n')
    (tools / 'systemd-cat').write_text('#!/bin/sh\nshift 2\nexec "$@"\n')
    for t in tools.iterdir():
        t.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=f'{tools}:/usr/bin:/bin')
    env.pop('XDG_CONFIG_HOME', None)
    r = subprocess.run([str(ROOT / 'bin/kuwai-session')], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip(), home


def test_the_session_starts_on_kuwais_own_entry(tmp_path):
    out, home = launch(tmp_path, {'.config/kuwai/hypr/hyprland.lua': '-- kuwai\n', '.config/hypr/hyprland.lua': '-- omarchy\n'})
    assert out == f'start-hyprland -- --config {home}/.config/kuwai/hypr/hyprland.lua'


def test_an_older_install_still_starts_from_hypr(tmp_path):
    out, home = launch(tmp_path, {'.config/hypr/hyprland.lua': '-- KUWAI_ROOT entry\n'})
    assert out == f'start-hyprland -- --config {home}/.config/hypr/hyprland.lua'


def test_without_kuwai_hyprland_starts_as_it_is(tmp_path):
    out, _ = launch(tmp_path, {'.config/hypr/hyprland.lua': '-- omarchy\n'})
    assert out == 'start-hyprland'


def run_session(tmp_path, *args):
    env = dict(os.environ, KUWAI_SYSROOT=str(tmp_path / 'root'))
    return subprocess.run([str(ROOT / 'system/session'), *args], env=env, capture_output=True, text=True)


def test_install_check_and_undo(tmp_path):
    entry = tmp_path / 'root/usr/share/wayland-sessions/kuwai.desktop'
    launcher = tmp_path / 'root/usr/local/bin/kuwai-session'
    assert run_session(tmp_path, '--check').returncode == 1
    assert run_session(tmp_path).returncode == 0
    assert 'Exec=/usr/local/bin/kuwai-session' in entry.read_text()
    assert os.access(launcher, os.X_OK)
    assert run_session(tmp_path, '--check').returncode == 0
    assert run_session(tmp_path).returncode == 0
    assert run_session(tmp_path, '--undo').returncode == 0
    assert not entry.exists() and not launcher.exists()


def test_a_file_that_isnt_kuwais_is_never_replaced_or_removed(tmp_path):
    entry = tmp_path / 'root/usr/share/wayland-sessions/kuwai.desktop'
    entry.parent.mkdir(parents=True)
    entry.write_text('[Desktop Entry]\nName=Someone else\n')
    r = run_session(tmp_path)
    assert r.returncode != 0 and "isn't kuwai's" in r.stderr
    run_session(tmp_path, '--undo')
    assert entry.read_text() == '[Desktop Entry]\nName=Someone else\n'


def test_the_greeter_hands_over_to_the_kuwai_session():
    text = (ROOT / 'greeter/session-start').read_text()
    assert '/usr/local/bin/kuwai-session' in text
