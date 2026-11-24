"""Installer regressions exercise install.sh, using only temporary homes and tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
UNITS = ('kuwai-auth.service', 'kuwai-clipboard.service', 'kuwai-feeds.service')


@pytest.fixture
def install_env(tmp_path):
    repo = tmp_path / 'repo'
    repo.mkdir()
    shutil.copy2(ROOT / 'install.sh', repo / 'install.sh')
    (repo / 'bin').mkdir()
    helper = ROOT / 'bin/kuwai_install.py'
    if helper.exists():
        shutil.copy2(helper, repo / 'bin/kuwai_install.py')
    shutil.copy2(ROOT / 'bin/kuwai-home', repo / 'bin/kuwai-home')
    shutil.copytree(ROOT / 'home', repo / 'home')
    if (ROOT / 'packages').is_dir():
        shutil.copytree(ROOT / 'packages', repo / 'packages')
    (repo / 'hypr/templates').mkdir(parents=True)
    (repo / 'hypr/templates/hyprland.lua').write_text('-- installed entry\n')
    (repo / 'systemd').mkdir()
    for unit in UNITS:
        (repo / 'systemd' / unit).write_text('[Unit]\nDescription=fixture\n')
    home = tmp_path / 'home'
    home.mkdir()
    stable = home / '.local/share/kuwai'
    (stable / 'hypr').mkdir(parents=True)
    (stable / 'hypr/init.lua').write_text('-- fixture\n')
    tools = tmp_path / 'tools'
    tools.mkdir()
    for name in ('Hyprland', 'qs', 'cliphist', 'wl-copy', 'jq', 'grim', 'slurp',
                 'brightnessctl', 'pw-play', 'wpctl', 'notify-send', 'curl',
                 'setpriv', 'gdbus', 'luac', 'playerctl', 'git', 'file', 'fc-list'):
        p = tools / name
        p.write_text('#!/bin/sh\nexit 0\n')
        p.chmod(0o755)
    for name in ('kuwai', 'kuwai-doctor'):
        p = repo / 'bin' / name
        p.write_text('#!/bin/sh\nexit 0\n')
        p.chmod(0o755)
    service_state = tmp_path / 'services.json'
    service_state.write_text(json.dumps({u: 'disabled' for u in UNITS}))
    systemctl = tools / 'systemctl'
    systemctl.write_text(f'''#!{sys.executable}
import json, os, sys
p = os.environ['TEST_SERVICES']
s = json.load(open(p))
a = [v for v in sys.argv[1:] if not v.startswith('--')]
if a[0] == 'is-enabled':
    print(s.get(a[1], 'disabled'))
    sys.exit(0 if s.get(a[1]) == 'enabled' else 1)
if a[0] in ('enable', 'disable'):
    s[a[1]] = 'enabled' if a[0] == 'enable' else 'disabled'
    with open(p, 'w') as f: json.dump(s, f)
''')
    systemctl.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=str(tools) + ':' + os.environ['PATH'],
               TEST_SERVICES=str(service_state), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_DATA_HOME=str(home / '.local/share'), XDG_STATE_HOME=str(home / '.local/state'))

    class Install:
        cfg = home / '.config'
        entry = cfg / 'hypr/hyprland.lua'

        def run(self, *args):
            result = subprocess.run(['bash', str(repo / 'install.sh'), *args], env=env,
                                    text=True, capture_output=True)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout + result.stderr

    inst = Install()
    inst.home, inst.repo, inst.env, inst.services = home, repo, env, service_state
    return inst


def test_install_replaces_symlink_without_touching_target_and_restores_link(install_env):
    i = install_env
    original = i.home / 'dotfiles.lua'
    original.write_text('-- my original\n')
    i.entry.parent.mkdir(parents=True)
    i.entry.symlink_to(original)
    i.run()
    assert original.read_text() == '-- my original\n'
    assert not i.entry.is_symlink()
    i.run('--uninstall')
    assert i.entry.is_symlink()
    assert i.entry.readlink() == original


def test_reinstall_restores_first_regular_original(install_env):
    i = install_env
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- first original\n')
    i.run()
    (i.repo / 'hypr/templates/hyprland.lua').write_text('-- upgraded entry\n')
    i.run()
    i.run('--uninstall')
    assert i.entry.read_text() == '-- first original\n'


def test_absent_owned_paths_removed_and_user_settings_kept(install_env):
    i = install_env
    i.run()
    (i.cfg / 'hypr/user.lua').write_text('-- custom settings\n')
    i.run('--uninstall')
    assert not i.entry.exists()
    assert not any((i.cfg / 'systemd/user' / u).is_symlink() for u in UNITS)
    assert (i.cfg / 'hypr/user.lua').read_text() == '-- custom settings\n'


def test_uninstall_preserves_user_edits_as_conflict(install_env):
    i = install_env
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- first original\n')
    i.run()
    i.entry.write_text('-- subsequent user edit\n')
    output = i.run('--uninstall')
    assert i.entry.read_text() == '-- subsequent user edit\n'
    assert 'conflict' in output.lower()


def test_original_unit_enablement_survives_reinstall(install_env):
    i = install_env
    i.services.write_text(json.dumps({UNITS[0]: 'enabled', UNITS[1]: 'disabled', UNITS[2]: 'enabled'}))
    i.run()
    i.run()
    i.run('--uninstall')
    recorded = json.loads(i.services.read_text())
    # What you had survives both installs exactly...
    assert {u: recorded.get(u) for u in UNITS[:3]} == {UNITS[0]: 'enabled', UNITS[1]: 'disabled', UNITS[2]: 'enabled'}
    # ...and a unit the record hadn't seen (kuwai-backup.* came later) is kept
    # as it was before installing: not there, so disabled.
    assert all(v == 'disabled' for u, v in recorded.items() if u not in UNITS[:3]), recorded


def test_custom_xdg_paths_restore_originals(install_env):
    i = install_env
    i.cfg = i.home.parent / 'custom config'
    i.entry = i.cfg / 'hypr/hyprland.lua'
    i.env['XDG_CONFIG_HOME'] = str(i.cfg)
    i.env['XDG_STATE_HOME'] = str(i.home.parent / 'custom state')
    i.env['XDG_DATA_HOME'] = str(i.home.parent / 'custom data')
    stable = Path(i.env['XDG_DATA_HOME']) / 'kuwai/hypr'
    stable.mkdir(parents=True)
    (stable / 'init.lua').write_text('-- fixture\n')
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- custom original\n')
    i.run()
    i.run('--uninstall')
    assert i.entry.read_text() == '-- custom original\n'


def test_dry_run_writes_nothing(install_env):
    i = install_env
    def snapshot():
        return {str(p): (p.readlink() if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in i.home.parent.rglob('*')}
    before = snapshot()
    i.run('--dry-run')
    i.run('--uninstall', '--dry-run')
    assert snapshot() == before


def _legacy_backup(i, stamp, content):
    """What the previous installer left: <state>/backup/<time>/ with a MANIFEST of $HOME-relative paths."""
    d = Path(i.env['XDG_STATE_HOME']) / 'kuwai/backup' / stamp
    rel = i.entry.relative_to(i.home)
    (d / rel).parent.mkdir(parents=True)
    (d / rel).write_text(content)
    (d / 'MANIFEST').write_text(f'{rel}\n')


def test_upgrade_from_legacy_backups_restores_the_oldest(install_env):
    i = install_env
    _legacy_backup(i, '20260101-000000', '-- the real original\n')
    _legacy_backup(i, '20260601-000000', '-- an earlier kuwai entry\n')
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- an earlier kuwai entry, v2\n')
    i.run()
    i.run('--uninstall')
    assert i.entry.read_text() == '-- the real original\n'


def test_uninstall_with_only_legacy_backups(install_env):
    i = install_env
    _legacy_backup(i, '20260101-000000', '-- the real original\n')
    _legacy_backup(i, '20260601-000000', '-- an earlier kuwai entry\n')
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- whatever kuwai left\n')
    i.run('--uninstall')
    assert i.entry.read_text() == '-- the real original\n'


def _fonts(install_env, families):
    tools = Path(install_env.env['PATH'].split(':')[0])
    stub = tools / 'fc-list'
    stub.write_text('#!/bin/sh\ncat <<"EOF"\n' + '\n'.join(families) + '\nEOF\n')
    stub.chmod(0o755)
    return install_env.run('--dry-run')


def test_fonts_inter_is_the_face_and_needs_no_aur(install_env):
    out = _fonts(install_env, ['Inter', 'Inter Display', 'Symbols Nerd Font Mono,Symbols Nerd Font'])
    assert '✓ font: Inter' in out and '✓ font: Symbols Nerd Font' in out
    assert 'AUR' not in out and 'apple-fonts' not in out
    assert 'used instead of Inter if you install it yourself' in out


def test_fonts_missing_inter_is_offered_from_the_repos_without_stopping(install_env):
    out = _fonts(install_env, ['DejaVu Sans'])
    assert 'missing font: Inter (package inter-font' in out
    assert 'sudo pacman -S --needed' in out and 'inter-font' in out


def test_fonts_sf_pro_stands_in_for_inter_when_installed(install_env):
    out = _fonts(install_env, ['SF Pro Text', 'SF Pro Display', 'SF Pro Rounded', 'Symbols Nerd Font'])
    assert 'missing font: Inter' not in out
    assert 'SF Pro (found: the shell uses it instead of Inter)' in out


def _without_python(install_env):
    """A PATH with the fixture's tools and every system command but python."""
    nopy = install_env.home.parent / 'nopython'
    nopy.mkdir()
    for d in ('/usr/bin', '/bin'):
        for name in os.listdir(d) if os.path.isdir(d) else []:
            if name.startswith('python') or (nopy / name).is_symlink() or (nopy / name).exists():
                continue
            (nopy / name).symlink_to(os.path.join(d, name))
    tools = install_env.env['PATH'].split(':')[0]
    return {'PATH': tools + ':' + str(nopy)}


# A machine where the packages were never installed has no python3 (found
# in a fresh Arch container, 2026-11-21: uninstall died with exit 127).
def test_uninstall_without_python_and_nothing_installed_says_so(install_env):
    env = dict(install_env.env, **_without_python(install_env))
    r = subprocess.run(['bash', str(install_env.repo / 'install.sh'), '--uninstall'], env=env, text=True, capture_output=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert 'Nothing to put back' in r.stdout


# Installing from a text console or SSH, before any desktop session (seen in a
# clean container, 2026-11-21): no user bus, and install failed at its last
# step after doing everything else. It links the services and says how to
# enable them from the session instead.
def test_install_without_a_user_session_links_and_says_how_to_enable(install_env):
    tools = Path(install_env.env['PATH'].split(':')[0])
    (tools / 'systemctl').write_text('#!/bin/sh\necho "Failed to connect to user scope bus" >&2\nexit 1\n')
    out = install_env.run()
    assert 'no user session' in out and 'systemctl --user enable' in out
    assert (install_env.home / '.config/systemd/user/kuwai-auth.service').is_symlink()


def test_the_glyph_font_is_the_package_that_has_it():
    # ttf-nerd-fonts-symbols-mono is "Symbols Nerd Font Mono"; the shell asks for "Symbols Nerd Font".
    text = (ROOT / 'packages/fonts.txt').read_text()
    assert 'Symbols Nerd Font:ttf-nerd-fonts-symbols' in text
    assert 'Theme.fontGlyph' not in text
    assert '"Symbols Nerd Font"' in (ROOT / 'shell/config/Theme.qml').read_text()


def test_install_no_services_skips_unit_links(install_env):
    out = install_env.run('--no-services')
    assert 'skipped (--no-services)' in out
    assert not any((install_env.cfg / 'systemd/user' / u).exists() for u in UNITS)


def test_install_print_missing_lists_missing_packages_only(install_env):
    core = install_env.repo / 'packages/core.txt'
    core.write_text(core.read_text() + 'kuwai-no-such-bin-xyz:kuwai-missing-pkg\n')
    out = install_env.run('--print-missing')
    assert 'kuwai-missing-pkg' in out.splitlines()
