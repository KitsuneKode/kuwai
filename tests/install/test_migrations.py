"""bin/kuwai-migrations against a temporary HOME: order, once only, the first
failure stops the run, --dry-run changes nothing, and a write outside the
user's XDG folders is refused by the kernel (Landlock). Plus the shipped
migrations themselves (migrations/)."""
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'bin/kuwai-migrations'
W = 'write-file,remove-dir,remove-file,make-char,make-dir,make-reg,make-sock,make-fifo,make-block,make-sym,refer,truncate'


def landlock():
    try:
        return subprocess.run(['setpriv', '--landlock-access', 'fs:' + W, '--', 'true'], capture_output=True).returncode == 0
    except FileNotFoundError:
        return False


needs_landlock = pytest.mark.skipif(not landlock(), reason='no Landlock here (setpriv or kernel)')


@pytest.fixture
def env(tmp_path):
    home = tmp_path / 'home'
    home.mkdir()
    mig = tmp_path / 'migrations'
    mig.mkdir()
    e = {k: v for k, v in os.environ.items() if not k.startswith('XDG_') and not k.startswith('KUWAI_')}
    e.update(HOME=str(home), KUWAI_MIGRATIONS_DIR=str(mig))
    return {'home': home, 'mig': mig, 'env': e, 'tmp': tmp_path, 'state': home / '.local/state/kuwai'}


def run(env, *args, extra=None):
    e = dict(env['env'])
    e.update(extra or {})
    return subprocess.run([str(RUNNER), *args], capture_output=True, text=True, env=e, timeout=60)


def add(env, name, body):
    (env['mig'] / name).write_text('# what: ' + name + '\n' + body)


def snapshot(root):
    out = {}
    for p in sorted(Path(root).rglob('*')):
        out[str(p.relative_to(root))] = p.read_bytes() if p.is_file() and not p.is_symlink() else ('dir' if p.is_dir() else 'link')
    return out


@needs_landlock
def test_runs_in_number_order_once(env):
    for n in ('0003-b.sh', '0001-a.sh', '0002-c.sh'):
        add(env, n, f'mkdir -p "$XDG_STATE_HOME/kuwai"; echo {n} >> "$XDG_STATE_HOME/kuwai/order.txt"\n')
    (env['mig'] / 'README.md').write_text('not a migration')
    (env['mig'] / 'TEMPLATE.sh').write_text('echo never >> "$XDG_STATE_HOME/kuwai/order.txt"')
    r = run(env)
    assert r.returncode == 0, r.stderr
    order = env['state'] / 'order.txt'
    assert order.read_text().split() == ['0001-a.sh', '0002-c.sh', '0003-b.sh']
    r = run(env)
    assert r.returncode == 0 and 'nothing to do' in r.stdout
    assert order.read_text().split() == ['0001-a.sh', '0002-c.sh', '0003-b.sh']
    listed = run(env, '--list').stdout
    assert listed.count('done') == 3 and 'pending' not in listed
    assert sorted(p.name for p in (env['state'] / 'migrations/done').iterdir()) == ['0001-a.sh', '0002-c.sh', '0003-b.sh']


@needs_landlock
def test_first_failure_stops_and_stays_pending(env):
    add(env, '0001-ok.sh', 'mkdir -p "$XDG_STATE_HOME/kuwai"; touch "$XDG_STATE_HOME/kuwai/one"\n')
    add(env, '0002-bad.sh', 'echo "settings.json is not JSON" >&2; exit 3\n')
    add(env, '0003-later.sh', 'touch "$XDG_STATE_HOME/kuwai/three"\n')
    r = run(env)
    assert r.returncode == 1
    assert '0002-bad failed (exit 3)' in r.stderr and 'the 1 after it' in r.stderr
    assert 'settings.json is not JSON' in r.stderr
    assert (env['state'] / 'one').exists() and not (env['state'] / 'three').exists()
    listed = run(env, '--list').stdout
    assert 'done     0001-ok' in listed and 'pending  0002-bad' in listed and 'pending  0003-later' in listed
    # Fixed: the rest runs, the first doesn't run again.
    add(env, '0002-bad.sh', 'true\n')
    (env['state'] / 'one').unlink()
    r = run(env)
    assert r.returncode == 0, r.stderr
    assert (env['state'] / 'three').exists() and not (env['state'] / 'one').exists()


@needs_landlock
def test_set_e_stops_a_migration_at_its_first_failing_command(env):
    add(env, '0001-x.sh', 'false\nmkdir -p "$XDG_STATE_HOME/kuwai"; touch "$XDG_STATE_HOME/kuwai/after"\n')
    assert run(env).returncode == 1
    assert not (env['state'] / 'after').exists()


@needs_landlock
def test_dry_run_changes_nothing(env):
    add(env, '0001-a.sh', 'mkdir -p "$XDG_CONFIG_HOME/kuwai"; echo x > "$XDG_CONFIG_HOME/kuwai/changed"\n')
    (env['home'] / '.config/kuwai').mkdir(parents=True)
    (env['home'] / '.config/kuwai/settings.json').write_text('{"a": 1}')
    before = snapshot(env['home'])
    r = run(env, '--dry-run')
    assert r.returncode == 0 and '0001-a' in r.stdout and 'would run' in r.stdout
    assert snapshot(env['home']) == before
    r = run(env, '--list')
    assert snapshot(env['home']) == before


@needs_landlock
def test_a_write_outside_the_xdg_folders_is_refused(env):
    outside = env['tmp'] / 'outside'
    outside.mkdir()
    add(env, '0001-escape.sh', f'echo pwned > "{outside}/file"\n')
    add(env, '0002-home.sh', 'echo x > "$HOME/.bashrc"\n')
    r = run(env)
    assert r.returncode == 1 and '0001-escape failed' in r.stderr
    assert not (outside / 'file').exists()
    assert 'Permission denied' in r.stderr
    # In $HOME but not an XDG folder: refused too.
    (env['mig'] / '0001-escape.sh').write_text('true\n')
    r = run(env)
    assert r.returncode == 1 and '0002-home failed' in r.stderr
    assert not (env['home'] / '.bashrc').exists()


@needs_landlock
def test_moving_a_file_out_of_the_folders_is_refused(env):
    target = env['tmp'] / 'outside'
    target.mkdir()
    add(env, '0001-mv.sh', f'mkdir -p "$XDG_DATA_HOME/kuwai"; echo s > "$XDG_DATA_HOME/kuwai/secret"; mv "$XDG_DATA_HOME/kuwai/secret" "{target}/"\n')
    assert run(env).returncode == 1
    assert not (target / 'secret').exists()


def test_an_xdg_folder_outside_home_is_refused(env):
    add(env, '0001-a.sh', 'touch "$XDG_CONFIG_HOME/x"\n')
    r = run(env, extra={'XDG_CONFIG_HOME': str(env['tmp'] / 'elsewhere')})
    assert r.returncode == 2 and 'outside $HOME' in r.stderr
    assert not (env['tmp'] / 'elsewhere').exists()
    r = run(env, extra={'XDG_STATE_HOME': str(env['home']) + '/../escape'})
    assert r.returncode == 2


def test_never_as_root(env, tmp_path):
    fake = tmp_path / 'fakebin'
    fake.mkdir()
    (fake / 'id').write_text('#!/bin/sh\n[ "$1" = -u ] && echo 0 || exec /usr/bin/id "$@"\n')
    (fake / 'id').chmod(0o755)
    add(env, '0001-a.sh', 'true\n')
    r = run(env, extra={'PATH': f"{fake}:{env['env']['PATH']}"})
    assert r.returncode == 2 and 'never as root' in r.stderr
    assert not env['state'].exists()


def test_refuses_before_the_rename_has_moved_the_folders(env):
    (env['home'] / '.local/state/rice').mkdir(parents=True)
    add(env, '0001-a.sh', 'true\n')
    r = run(env)
    assert r.returncode == 2 and 'kuwai-migrate' in r.stderr
    # Moved (rice left as a link, kuwai there): fine.
    (env['home'] / '.local/state/rice').rmdir()
    (env['home'] / '.local/state/kuwai').mkdir()
    (env['home'] / '.local/state/rice').symlink_to('kuwai')
    assert run(env, '--dry-run').returncode == 0


def test_two_migrations_with_one_number_are_refused(env):
    add(env, '0004-a.sh', 'true\n')
    add(env, '0004-b.sh', 'true\n')
    r = run(env)
    assert r.returncode == 2 and 'numbered 0004' in r.stderr


@needs_landlock
def test_a_migration_that_hangs_is_stopped(env):
    add(env, '0001-slow.sh', 'sleep 30\n')
    r = run(env, extra={'KUWAI_MIGRATION_TIMEOUT': '1'})
    assert r.returncode == 1 and 'took over 1s' in r.stderr


@needs_landlock
def test_the_template_runs_and_changes_nothing(env):
    shutil.copy2(ROOT / 'migrations/TEMPLATE.sh', env['mig'] / '0001-template.sh')
    (env['home'] / '.local/state/kuwai').mkdir(parents=True)
    (env['home'] / '.local/state/kuwai/example.json').write_text('{"oldKey": 1}')
    before = snapshot(env['home'] / '.local/state/kuwai')
    r = run(env)
    assert r.returncode == 0, r.stderr
    after = {k: v for k, v in snapshot(env['home'] / '.local/state/kuwai').items() if not k.startswith('migrations')}
    assert after == before


# ── The shipped migrations ──────────────────────────────────────────────────

@pytest.fixture
def shipped(env):
    shutil.rmtree(env['mig'])
    shutil.copytree(ROOT / 'migrations', env['mig'])
    return env


def launcher(env):
    return env['state'] / 'launcher.json'


@needs_landlock
@pytest.mark.parametrize('wrapped', [True, False])
def test_0002_vitals_counts_go_to_system(shipped, wrapped):
    counts = {'action:Vitals': {'n': 3, 't': 200}, 'action:System': {'n': 2, 't': 100}, 'firefox.desktop': {'n': 9, 't': 50}}
    shipped['state'].mkdir(parents=True)
    launcher(shipped).write_text(json.dumps({'counts': counts} if wrapped else counts))
    r = run(shipped)
    assert r.returncode == 0, r.stderr
    d = json.loads(launcher(shipped).read_text())
    c = d['counts'] if wrapped else d
    assert c == {'action:System': {'n': 5, 't': 200}, 'firefox.desktop': {'n': 9, 't': 50}}
    assert 'Vitals' in r.stdout


@needs_landlock
def test_0002_without_system_yet_and_without_a_file(shipped):
    shipped['state'].mkdir(parents=True)
    launcher(shipped).write_text(json.dumps({'counts': {'action:Vitals': {'n': 1, 't': 7}}}))
    assert run(shipped).returncode == 0
    assert json.loads(launcher(shipped).read_text()) == {'counts': {'action:System': {'n': 1, 't': 7}}}
    # Nothing to do on a fresh machine: runs, records, writes no launcher.json.
    fresh = dict(shipped)
    fresh['home'] = shipped['tmp'] / 'fresh'
    fresh['home'].mkdir()
    fresh['env'] = dict(shipped['env'], HOME=str(fresh['home']))
    assert run(fresh).returncode == 0
    assert not (fresh['home'] / '.local/state/kuwai/launcher.json').exists()
    assert (fresh['home'] / '.local/state/kuwai/migrations/done/0002-launcher-vitals-to-system.sh').exists()


@needs_landlock
def test_0002_run_twice_is_a_no_op(shipped, tmp_path):
    shipped['state'].mkdir(parents=True)
    launcher(shipped).write_text(json.dumps({'counts': {'action:Vitals': {'n': 1, 't': 7}, 'action:System': {'n': 1, 't': 9}}}))
    assert run(shipped).returncode == 0
    once = launcher(shipped).read_text()
    shutil.rmtree(shipped['state'] / 'migrations/done')      # its record lost
    assert run(shipped).returncode == 0
    assert launcher(shipped).read_text() == once


def test_list_without_a_state_folder_writes_nothing(shipped):
    r = run(shipped, '--list')
    assert r.returncode == 0 and 'pending  0002-launcher-vitals-to-system' in r.stdout
    assert not shipped['state'].exists()


# kuwai promote asks `--check` before stable moves (2026-11-21): a machine
# without Landlock was told only after stable had moved, and rolled back at
# every promote.
@needs_landlock
def test_check_runs_nothing_and_says_they_can_run(env):
    add(env, '0001-a.sh', 'mkdir -p "$XDG_CONFIG_HOME/kuwai"; echo x > "$XDG_CONFIG_HOME/kuwai/changed"\n')
    before = snapshot(env['home'])
    r = run(env, '--check')
    assert r.returncode == 0 and 'can run here' in r.stdout
    assert snapshot(env['home']) == before


def test_check_without_landlock_refuses_and_says_what_to_install(env):
    add(env, '0001-a.sh', 'true\n')
    fake = env['tmp'] / 'bin'
    fake.mkdir()
    (fake / 'setpriv').write_text('#!/bin/sh\necho "setpriv: unrecognized option --landlock-access" >&2\nexit 1\n')
    (fake / 'setpriv').chmod(0o755)
    r = run(env, '--check', extra={'PATH': str(fake) + ':' + env['env'].get('PATH', '/usr/bin:/bin')})
    assert r.returncode == 2
    assert 'no Landlock' in r.stderr and 'Linux 5.13' in r.stderr and 'util-linux 2.39' in r.stderr


def test_check_with_nothing_pending_passes_without_landlock(env):
    r = run(env, '--check')
    assert r.returncode == 0 and 'nothing to do' in r.stdout


def test_promote_asks_before_stable_moves():
    ctl = (Path(__file__).resolve().parents[2] / 'bin/kuwai-ctl').read_text()
    check = ctl.index('kuwai-migrations" --check')
    move = ctl.index('merge --ff-only --quiet "$head"')
    assert check < move and 'not promoted:' in ctl[check:move]
