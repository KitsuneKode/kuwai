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
        (repo / 'systemd' / unit).write_text('[Unit]\nDescription=fixture\n[Install]\nWantedBy=default.target\n')
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
    for line in (ROOT / 'packages/core.txt').read_text().splitlines():
        cmd = line.split(':', 1)[0].strip()
        if cmd and not line.startswith('#') and not shutil.which(cmd) and not (tools / cmd).exists():
            (tools / cmd).write_text('#!/bin/sh\nexit 0\n')
            (tools / cmd).chmod(0o755)
    (tools / 'pacman').write_text('#!/bin/sh\n[ "$1" = -Q ] && exit 0\nexit 1\n')
    (tools / 'pacman').chmod(0o755)
    (tools / 'fc-list').write_text('#!/bin/sh\nprintf "Inter\\nSymbols Nerd Font\\n"\n')
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
if a[0] == 'show-environment' and os.environ.get('TEST_NO_BUS'):
    sys.exit(1)
if a[0] == 'enable' and a[1] == os.environ.get('TEST_FAIL_ENABLE'):
    sys.exit(1)
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
        entry = cfg / 'kuwai/hypr/hyprland.lua'

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
    (i.cfg / 'kuwai/hypr/user.lua').write_text('-- custom settings\n')
    i.run('--uninstall')
    assert not i.entry.exists()
    assert not any((i.cfg / 'systemd/user' / u).is_symlink() for u in UNITS)
    assert (i.cfg / 'kuwai/hypr/user.lua').read_text() == '-- custom settings\n'


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
    i.entry = i.cfg / 'kuwai/hypr/hyprland.lua'
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


def _doctor_fails(i):
    p = i.repo / 'bin/kuwai-doctor'
    p.write_text('#!/bin/sh\necho "session check failed"\nexit 1\n')
    p.chmod(0o755)
    for k in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        i.env.pop(k, None)


def test_a_headless_install_succeeds_and_leaves_the_session_checks_for_login(install_env):
    i = install_env
    _doctor_fails(i)
    out = i.run()
    assert 'session check failed' not in out
    assert 'kuwai doctor' in out


def test_inside_the_session_a_failing_check_still_fails_the_install(install_env):
    i = install_env
    _doctor_fails(i)
    i.env['HYPRLAND_INSTANCE_SIGNATURE'] = 'fixture'
    r = subprocess.run(['bash', str(i.repo / 'install.sh')], env=i.env, text=True, capture_output=True)
    assert r.returncode != 0


def test_a_path_no_legacy_backup_knew_keeps_its_current_file(install_env):
    i = install_env
    d = Path(i.env['XDG_STATE_HOME']) / 'kuwai/backup/20260101-000000'
    (d / '.config/waybar').mkdir(parents=True)
    (d / '.config/waybar/config').write_text('{}\n')
    (d / 'MANIFEST').write_text('.config/waybar/config\n')
    i.entry.parent.mkdir(parents=True)
    i.entry.write_text('-- mine, never managed by the old installer\n')
    i.run()
    i.run('--uninstall')
    assert i.entry.read_text() == '-- mine, never managed by the old installer\n'


def test_reinstall_keeps_your_edit_and_leaves_the_new_entry_beside_it(install_env):
    i = install_env
    i.run()
    i.entry.write_text('-- installed entry\n-- my edit\n')
    (i.repo / 'hypr/templates/hyprland.lua').write_text('-- upgraded entry\n')
    out = i.run()
    assert i.entry.read_text() == '-- installed entry\n-- my edit\n'
    assert (i.entry.parent / 'hyprland.lua.kuwai-new').read_text() == '-- upgraded entry\n'
    assert 'hyprland.lua.kuwai-new' in out


def test_a_hyprland_lua_kuwai_did_not_write_is_never_touched(install_env):
    i = install_env
    own = i.cfg / 'hypr/hyprland.lua'
    own.parent.mkdir(parents=True)
    own.write_text('-- omarchy\n')
    (i.cfg / 'hypr/monitors.lua').write_text('-- omarchy monitors\n')
    out = i.run()
    assert own.read_text() == '-- omarchy\n'
    assert (i.cfg / 'hypr/monitors.lua').read_text() == '-- omarchy monitors\n'
    assert i.entry.read_text() == '-- installed entry\n'
    assert (i.cfg / 'kuwai/hypr/monitors.lua').exists() and (i.cfg / 'kuwai/hypr/user.lua').exists()
    assert 'not Kuwai' in out
    i.run('--uninstall')
    assert own.read_text() == '-- omarchy\n'
    assert not i.entry.exists()


def test_untouched_stubs_go_with_uninstall(install_env):
    i = install_env
    i.run()
    i.run('--uninstall')
    assert not (i.cfg / 'kuwai/hypr/monitors.lua').exists()
    assert not (i.cfg / 'kuwai/hypr/user.lua').exists()


def test_an_older_install_keeps_its_layout_until_asked(install_env):
    i = install_env
    old = i.cfg / 'hypr/hyprland.lua'
    old.parent.mkdir(parents=True)
    old.write_text('-- KUWAI_ROOT an older kuwai entry\n')
    out = i.run()
    assert old.read_text() == '-- installed entry\n'
    assert not i.entry.exists()
    assert '--separate-session' in out


def _old_installer_wrote(i, original):
    old = i.cfg / 'hypr/hyprland.lua'
    old.parent.mkdir(parents=True)
    old.write_text(original)
    orig = [sys.executable, str(i.repo / 'bin/kuwai_install.py'), '--state', str(Path(i.env['XDG_STATE_HOME']) / 'kuwai')]
    subprocess.run([*orig, 'remember', str(old)], env=i.env, check=True)
    old.write_text('-- installed entry\n')
    subprocess.run([*orig, 'installed', str(old)], env=i.env, check=True)
    (i.cfg / 'hypr/user.lua').write_text('-- my binds\n')
    return old


def test_separate_session_gives_hypr_back(install_env):
    i = install_env
    old = _old_installer_wrote(i, '-- omarchy\n')
    i.run()
    assert old.read_text() == '-- installed entry\n' and not i.entry.exists()
    i.run('--separate-session')
    assert old.read_text() == '-- omarchy\n'
    assert i.entry.read_text() == '-- installed entry\n'
    assert (i.cfg / 'kuwai/hypr/user.lua').read_text() == '-- my binds\n'
    assert (i.cfg / 'hypr/user.lua').read_text() == '-- my binds\n'
    i.run()
    assert old.read_text() == '-- omarchy\n'
    i.run('--uninstall')
    assert old.read_text() == '-- omarchy\n'
    assert not i.entry.exists()


def test_the_login_entry_is_offered_without_a_terminal(install_env):
    i = install_env
    (i.repo / 'system').mkdir()
    shutil.copy2(ROOT / 'system/session', i.repo / 'system/session')
    shutil.copy2(ROOT / 'system/kuwai.desktop', i.repo / 'system/kuwai.desktop')
    shutil.copy2(ROOT / 'system/release.sh', i.repo / 'system/release.sh')
    shutil.copy2(ROOT / 'bin/kuwai-session', i.repo / 'bin/kuwai-session')
    i.env['KUWAI_SYSROOT'] = str(i.home.parent / 'sysroot')
    out = i.run()
    assert "root's checked copy of a signed release" in out and 'kuwai setup' in out
    assert 'sudo ' + str(i.repo / 'system/session') + ' --trust-clone' in out
    subprocess.run([str(i.repo / 'system/session'), '--trust-clone'], env=i.env, check=True, capture_output=True)
    assert '"Kuwai" is on the login screen' in i.run()


def test_uninstall_never_touches_units_kuwai_did_not_record(install_env):
    i = install_env
    i.services.write_text(json.dumps({u: 'enabled' for u in UNITS}))
    i.run('--uninstall')
    assert json.loads(i.services.read_text()) == {u: 'enabled' for u in UNITS}


def test_a_unit_without_an_install_section_is_not_enabled(install_env):
    i = install_env
    (i.repo / 'systemd/kuwai-shell.service').write_text('[Unit]\nDescription=static\n')
    i.run()
    s = json.loads(i.services.read_text())
    assert s.get('kuwai-shell.service') != 'enabled'
    assert s['kuwai-auth.service'] == 'enabled'


def test_collectors_start_only_when_asked_and_the_answer_is_kept(install_env):
    i = install_env
    i.run()
    s = json.loads(i.services.read_text())
    assert s.get('kuwai-clipboard.service') != 'enabled' and s.get('kuwai-feeds.service') != 'enabled'
    conf = i.home / '.config/kuwai/collect.conf'
    assert conf.read_text().split() == ['clipboard=off', 'feeds=off']
    i.run('--clipboard')
    assert json.loads(i.services.read_text())['kuwai-clipboard.service'] == 'enabled'
    i.run()
    assert 'clipboard=on' in conf.read_text().split(), 'a later run keeps the earlier answer'
    assert json.loads(i.services.read_text()).get('kuwai-feeds.service') != 'enabled'



def test_offline_install_reads_enablement_from_the_links(install_env):
    i = install_env
    wants = i.cfg / 'systemd/user/default.target.wants'
    wants.mkdir(parents=True)
    (wants / UNITS[0]).symlink_to('/nowhere')
    i.env['TEST_NO_BUS'] = '1'
    i.run()
    rec = json.loads((Path(i.env['XDG_STATE_HOME']) / 'kuwai/original/manifest.json').read_text())
    assert rec['units'][UNITS[0]] == 'enabled' and rec['units'][UNITS[1]] == 'disabled'


def test_a_failed_unit_restore_keeps_the_record_to_retry(install_env):
    i = install_env
    i.services.write_text(json.dumps({UNITS[0]: 'enabled'}))
    i.run()
    i.env['TEST_FAIL_ENABLE'] = UNITS[0]
    r = subprocess.run(['bash', str(i.repo / 'install.sh'), '--uninstall'], env=i.env, text=True, capture_output=True)
    assert r.returncode != 0 and 'again' in r.stdout
    assert (Path(i.env['XDG_STATE_HOME']) / 'kuwai/original/manifest.json').exists()
    del i.env['TEST_FAIL_ENABLE']
    i.run('--uninstall')
    assert json.loads(i.services.read_text())[UNITS[0]] == 'enabled'
    assert not i.entry.exists()


def test_a_planted_link_never_redirects_a_new_config(install_env, tmp_path):
    i = install_env
    target = tmp_path / 'outside' / 'victim'
    target.parent.mkdir()
    d = i.home / '.config/kuwai/hypr'
    d.mkdir(parents=True, exist_ok=True)
    (d / 'monitors.lua').symlink_to(target)
    i.run()
    assert not target.exists(), "the empty monitors.lua is never written through a link"


def test_a_fresh_install_without_hyde_gets_a_wallpaper_once(install_env):
    """The VM's first login was a flat grey desktop: no HyDE, so no wallpaper."""
    import hashlib
    digest = hashlib.sha256(b'JPEG').hexdigest()
    themes = install_env.repo / 'themes/kuwai-night'
    themes.mkdir(parents=True)
    (themes / 'wallpapers.tsv').write_text(f'# name\turl\tpin\n01-night\thttps://example.invalid/night.jpg\tsha256:{digest}\n')
    (themes / 'CREDITS.txt').write_text('credits\n')
    tools = Path(install_env.env['PATH'].split(':')[0])
    (tools / 'curl').write_text('#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf JPEG > "$2"; }; shift; done\n')
    (tools / 'file').write_text('#!/bin/sh\necho image/jpeg\n')
    state = install_env.home / '.local/state/kuwai'
    out = install_env.run()
    assert "Kuwai Night's wallpaper (01-night)" in out
    assert (state / 'wallpaper').resolve() == (state / 'wallpapers/01-night.jpg').resolve()
    assert (state / 'wallpapers/CREDITS.txt').exists()
    again = install_env.run()
    assert 'yours, kept' in again


def test_a_wallpaper_that_isnt_an_image_is_not_used(install_env):
    import hashlib
    digest = hashlib.sha256(b'<html>').hexdigest()
    themes = install_env.repo / 'themes/kuwai-night'
    themes.mkdir(parents=True)
    (themes / 'wallpapers.tsv').write_text(f'01-night\thttps://example.invalid/night.jpg\tsha256:{digest}\n')
    (themes / 'CREDITS.txt').write_text('credits\n')
    tools = Path(install_env.env['PATH'].split(':')[0])
    (tools / 'curl').write_text('#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf "<html>" > "$2"; }; shift; done\n')
    (tools / 'file').write_text('#!/bin/sh\necho text/html\n')
    out = install_env.run()
    assert "isn't an image" in out
    assert not (install_env.home / '.local/state/kuwai/wallpaper').exists()


def test_an_unpinned_or_wrong_digest_default_wallpaper_is_not_used(install_env):
    themes = install_env.repo / 'themes/kuwai-night'
    themes.mkdir(parents=True)
    (themes / 'wallpapers.tsv').write_text('01-night\thttps://example.invalid/night.jpg\n')
    (themes / 'CREDITS.txt').write_text('credits\n')
    tools = Path(install_env.env['PATH'].split(':')[0])
    (tools / 'curl').write_text('#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf JPEG > "$2"; }; shift; done\n')
    (tools / 'file').write_text('#!/bin/sh\necho image/jpeg\n')
    out = install_env.run()
    assert 'no checksum pin' in out
    assert not (install_env.home / '.local/state/kuwai/wallpaper').exists()

    (themes / 'wallpapers.tsv').write_text('01-night\thttps://example.invalid/night.jpg\tsha256:' + '0' * 64 + '\n')
    out2 = install_env.run()
    assert "isn't the file Kuwai Night lists" in out2
    assert not (install_env.home / '.local/state/kuwai/wallpaper').exists()
