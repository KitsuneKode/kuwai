"""Backups must be recoverable on fresh setups, during collisions, and under retention."""
import io
import os
from pathlib import Path
import subprocess
import tarfile

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def backup(tmp_path):
    home = tmp_path / 'home with spaces'
    config = home / '.config/kuwai'
    config.mkdir(parents=True)
    settings = config / 'settings.json'
    settings.write_text('original settings')
    tools = tmp_path / 'tools'
    tools.mkdir()
    date = tools / 'date'
    date.write_text('#!/bin/sh\ncase "$1" in +%Y%m%d-%H%M%S) echo 20261118-010000;; *) exec /usr/bin/date "$@";; esac\n')
    date.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=f'{tools}:/usr/bin:/bin',
               XDG_CONFIG_HOME=str(home / '.config'), XDG_DATA_HOME=str(home / '.local/share'),
               XDG_STATE_HOME=str(home / '.local/state'), KUWAI_BACKUP_KEEP='30')
    directory = home / '.local/state/kuwai/backups'
    def run(*args):
        return subprocess.run([str(ROOT / 'bin/kuwai-backup'), *args], env=env,
                              capture_output=True, text=True, timeout=10)
    return run, settings, directory, env


def test_first_automatic_backup_works_without_previous_snapshots(backup):
    run, settings, directory, _ = backup
    result = run('auto')
    assert result.returncode == 0, result.stderr
    archives = list(directory.glob('*.tar.gz'))
    assert len(archives) == 1
    with tarfile.open(archives[0]) as archive:
        assert archive.extractfile('.config/kuwai/settings.json').read() == settings.read_bytes()


def test_missing_optional_files_do_not_fail_a_manual_snapshot(backup):
    run, _, directory, _ = backup
    result = run('now')
    assert result.returncode == 0, result.stderr
    assert len(list(directory.glob('*.info'))) == 1


def test_repeated_same_second_snapshots_preserve_both_versions(backup):
    run, settings, directory, _ = backup
    first = run('now')
    settings.write_text('changed settings')
    second = run('now')
    assert first.returncode == second.returncode == 0
    assert first.stdout != second.stdout
    values = []
    for path in directory.glob('*.tar.gz'):
        with tarfile.open(path) as archive:
            values.append(archive.extractfile('.config/kuwai/settings.json').read())
    assert sorted(values) == [b'changed settings', b'original settings']


def test_automatic_snapshot_skips_unchanged_files(backup):
    run, settings, directory, _ = backup
    assert run('auto').returncode == 0
    assert run('auto').returncode == 0
    assert len(list(directory.glob('*.tar.gz'))) == 1
    settings.write_text('changed')
    assert run('auto').returncode == 0
    assert len(list(directory.glob('*.tar.gz'))) == 2


def test_restore_preserves_selected_archive_even_when_retention_is_one(backup):
    run, settings, _, env = backup
    env['KUWAI_BACKUP_KEEP'] = '1'
    first = run('now')
    assert first.returncode == 0, first.stderr
    name = Path(first.stdout.strip()).name
    settings.write_text('newer settings')
    restored = run('restore', name)
    assert restored.returncode == 0, restored.stderr
    assert settings.read_text() == 'original settings'


@pytest.mark.parametrize('value', ['0', '-1', 'abc', '999999999999999999999999'])
def test_invalid_retention_cannot_delete_snapshots(backup, value):
    run, _, directory, env = backup
    assert run('now').returncode == 0
    archives = {p.name: p.read_bytes() for p in directory.glob('*.tar.gz')}
    env['KUWAI_BACKUP_KEEP'] = value
    assert run('now').returncode != 0
    assert {p.name: p.read_bytes() for p in directory.glob('*.tar.gz')} == archives


@pytest.mark.parametrize('kind', ['symlink', 'hardlink', 'traversal', 'outside-scope'])
def test_unsafe_archive_is_rejected_before_any_restore_or_prebackup(backup, tmp_path, kind):
    run, settings, directory, _ = backup
    directory.mkdir(parents=True)
    archive_path = directory / '20261117-000000.tar.gz'
    outside = tmp_path / 'outside'
    outside.mkdir()
    with tarfile.open(archive_path, 'w:gz') as archive:
        member = tarfile.TarInfo('.config/kuwai/link' if kind != 'traversal' else '../outside/escaped')
        if kind == 'outside-scope': member.name = '.ssh/authorized_keys'
        if kind in ('traversal', 'outside-scope'):
            member.size = 3
            archive.addfile(member, io.BytesIO(b'bad'))
        else:
            member.type = tarfile.SYMTYPE if kind == 'symlink' else tarfile.LNKTYPE
            member.linkname = str(outside / 'escaped')
            archive.addfile(member)
    result = run('restore', archive_path.name)
    assert result.returncode != 0
    assert settings.read_text() == 'original settings'
    assert not list(outside.iterdir())
    assert list(directory.glob('*.tar.gz')) == [archive_path]


def test_notes_outside_home_fail_explicitly_instead_of_misleading_backup(backup, tmp_path):
    run, _, directory, env = backup
    notes = tmp_path / 'external-notes'
    notes.mkdir()
    (notes / 'inbox.md').write_text('outside home')
    env['KUWAI_NOTES'] = str(notes)
    result = run('now')
    assert result.returncode != 0
    assert not list(directory.glob('*.tar.gz'))
