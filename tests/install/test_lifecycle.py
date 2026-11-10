"""Installer regressions exercise install.sh, using only temporary homes and tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
UNITS = ('rice-auth.service', 'rice-clipboard.service', 'rice-feeds.service')


@pytest.fixture
def install_env(tmp_path):
    repo = tmp_path / 'repo'
    repo.mkdir()
    shutil.copy2(ROOT / 'install.sh', repo / 'install.sh')
    (repo / 'bin').mkdir()
    helper = ROOT / 'bin/rice_install.py'
    if helper.exists():
        shutil.copy2(helper, repo / 'bin/rice_install.py')
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
                 'setpriv', 'gdbus', 'luac', 'playerctl', 'git', 'fc-list'):
        p = tools / name
        p.write_text('#!/bin/sh\nexit 0\n')
        p.chmod(0o755)
    for name in ('kuwai', 'rice-doctor'):
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
    # ...and a unit the record hadn't seen (rice-backup.* came later) is kept
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
