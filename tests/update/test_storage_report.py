"""`kuwai-update storage` and `kuwai-update clean` regressions."""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
MIB = 1024 * 1024


@pytest.fixture
def updater(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader('storage_updater', str(ROOT / 'bin/kuwai-update'))
    spec = importlib.util.spec_from_loader('storage_updater', loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    for key in ('RUNTIME', 'CACHE', 'STATE', 'AUR_DIR', 'LOG_DIR'):
        monkeypatch.setattr(m, key, str(tmp_path / key))
    for key in ('LOCK', 'EVENTS', 'APPROVED', 'TRUSTED', 'INSTALLED'):
        monkeypatch.setattr(m, key, str(tmp_path / key))
    monkeypatch.setattr(m, 'PACMAN_CACHE', str(tmp_path / 'pacman-pkg'))
    return m


def write(path, size=1):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(os.urandom(size))


def stub_system(m, monkeypatch, installed=('pkg-a',), orphans=(), paccache=None):
    paccache = paccache or {}
    calls = []

    def sh(cmd, **kw):
        calls.append(cmd)
        out, rc = '', 0
        if cmd[:2] == ['pacman', '-Qq']:
            out = '\n'.join(installed)
        elif cmd[:2] == ['pacman', '-Qdtq']:
            out = '\n'.join(orphans)
        elif cmd[:2] == ['pacman', '-Qi']:
            out = '\n'.join(f'Name            : {n}\nInstalled Size  : 2.00 MiB\n' for n in cmd[3:])
        elif cmd[0] == 'paccache':
            out = paccache.get(cmd[-1], '==> no candidate packages found for pruning')
        elif cmd[0] == 'systemctl':
            rc = 3
        return SimpleNamespace(returncode=rc, stdout=out, stderr='')

    monkeypatch.setattr(m, 'sh', sh)
    monkeypatch.setattr(m.shutil, 'which', lambda name: f'/usr/bin/{name}')
    monkeypatch.setattr(m, 'git', lambda d, *a, check=False: SimpleNamespace(
        returncode=0, stdout='refs/rice/installed\n' if Path(d).name == 'old-recipe' else '', stderr=''))
    return calls


def snapshot(root):
    return sorted((str(p), p.lstat().st_size, p.lstat().st_mtime_ns) for p in Path(root).rglob('*'))


def item(report, ident):
    return next(i for i in report['items'] if i['id'] == ident)


def test_report_counts_each_purpose_and_changes_nothing(updater, monkeypatch, tmp_path):
    m = updater
    write(tmp_path / 'AUR_DIR/pkg-a/PKGBUILD', 4096)
    for i in range(m.ARTIFACT_KEEP + 1):
        batch = tmp_path / f'CACHE/artifacts/pkg-a/installed-{i}'
        write(batch / f'pkg-a-1.{i}-1-x86_64.pkg.tar.zst', MIB)
        os.utime(batch, (1_000 + i, 1_000 + i))
    write(tmp_path / 'CACHE/artifacts/removed/installed-0/removed-2.0-1-x86_64.pkg.tar.zst', MIB)
    for i in range(m.FAILED_KEEP + 1):
        stage = tmp_path / f'CACHE/builds/pkg-a-{i}'
        write(stage / 'src/blob', MIB)
        (stage / '.kuwai-workspace.json').write_text(json.dumps(
            {'schema': 1, 'repository': str(tmp_path / 'AUR_DIR/pkg-a')}))
        os.utime(stage, (2_000 + i, 2_000 + i))
    write(tmp_path / 'CACHE/builds/stranger/file', MIB)
    write(tmp_path / 'CACHE/aur/pkg-a/pkg/blob', MIB)
    write(tmp_path / 'CACHE/aur/old-recipe/src/blob', MIB)
    m.save(m.INSTALLED, {'pkg-a': {'schema': 1}})
    write(tmp_path / 'pacman-pkg/pkg-a-1.0-1-x86_64.pkg.tar.zst', MIB)
    (tmp_path / 'pacman-pkg/download-AbC123').mkdir()

    stub_system(m, monkeypatch, installed=('pkg-a', 'pkg-a-debug', 'electron42'), orphans=('electron42',),
                paccache={'-k2': '==> finished dry run: 3 candidates (disk space saved: 1.50 MiB)',
                          '-k0': '==> finished dry run: 9 candidates (disk space saved: 2.00 GiB)'})
    before = snapshot(tmp_path)
    report = m.storage_report()
    assert snapshot(tmp_path) == before

    assert report['dryRun'] is True and report['running'] is False
    assert item(report, 'recipes')['keep'] is True and item(report, 'recipes')['reclaimable'] == 0

    artifacts = {e['recipe']: e for e in item(report, 'artifacts')['entries']}
    assert artifacts['pkg-a']['batches'] == m.ARTIFACT_KEEP + 1
    assert MIB <= artifacts['pkg-a']['reclaimable'] < 2 * MIB
    assert artifacts['removed']['reclaimable'] == artifacts['removed']['bytes'] > 0
    assert artifacts['removed']['why']

    builds = item(report, 'builds')
    assert builds['count'] == m.FAILED_KEEP + 2
    assert MIB <= builds['reclaimable'] < 2 * MIB
    assert builds['unowned'] == [str(tmp_path / 'CACHE/builds/stranger')]

    legacy = {e['recipe']: e for e in item(report, 'legacy-aur')['entries']}
    assert legacy['pkg-a']['receipt'] is True
    assert legacy['old-recipe']['receipt'] is False and legacy['old-recipe']['legacyRef'] is True
    assert item(report, 'legacy-aur')['reclaimable'] == item(report, 'legacy-aur')['bytes'] > 0

    pacman = item(report, 'pacman-cache')
    assert pacman['reclaimable'] == int(1.5 * MIB)
    assert pacman['options']['keep0'] == {'files': 9, 'bytes': 2 * 1024 ** 3}
    assert pacman['options']['uninstalled'] == {'files': 0, 'bytes': 0}
    assert pacman['staleDownloads'] == 1

    assert report['packages']['orphans'] == [{'name': 'electron42', 'bytes': 2 * MIB}]
    assert report['packages']['debug'] == [{'name': 'pkg-a-debug', 'bytes': 2 * MIB}]
    assert report['reclaimable'] == sum(i['reclaimable'] for i in report['items'])


def test_links_are_counted_as_links_never_followed(updater, monkeypatch, tmp_path):
    m = updater
    write(tmp_path / 'elsewhere/huge', 8 * MIB)
    (tmp_path / 'CACHE/aur/linked').mkdir(parents=True)
    os.symlink(tmp_path / 'elsewhere', tmp_path / 'CACHE/aur/linked/out')
    os.symlink(tmp_path / 'elsewhere', tmp_path / 'CACHE/aur/as-dir')
    stub_system(m, monkeypatch)
    legacy = item(m.storage_report(), 'legacy-aur')
    assert [e['recipe'] for e in legacy['entries']] == ['linked']
    assert legacy['bytes'] < MIB


def test_unreadable_paccache_output_is_unknown_not_zero(updater, monkeypatch):
    m = updater
    stub_system(m, monkeypatch, paccache={'-k2': 'something else entirely'})
    options = item(m.storage_report(), 'pacman-cache')['options']
    assert options['keep2'] is None


def test_clean_removes_legacy_stale_artifacts_and_owned_builds_only(updater, monkeypatch, tmp_path):
    m = updater
    monkeypatch.setattr(m, 'ARTIFACT_CAP_BYTES', 2 * MIB)
    write(tmp_path / 'CACHE/aur/old/src/blob', MIB)
    for name, ts in (('pkg-a', 1000), ('pkg-b', 2000), ('pkg-c', 3000)):
        batch = tmp_path / f'CACHE/artifacts/{name}/installed-0'
        write(batch / f'{name}-1.0-1-x86_64.pkg.tar.zst', MIB)
        os.utime(batch, (ts, ts))
    write(tmp_path / 'CACHE/artifacts/removed/installed-0/removed-1.0-1-x86_64.pkg.tar.zst', MIB)
    write(tmp_path / 'CACHE/builds/stranger/keep', 1024)
    owned = tmp_path / 'CACHE/builds/owned-1'
    write(owned / 'src/blob', MIB)
    (owned / '.kuwai-workspace.json').write_text(json.dumps(
        {'schema': 1, 'repository': str(tmp_path / 'AUR_DIR/pkg-a')}))
    stub_system(m, monkeypatch, installed=('pkg-a', 'pkg-b', 'pkg-c'))

    dry = m.clean_storage(['--dry-run'])
    assert dry['ok'] is True and dry['dryRun'] is True and dry['freedBytes'] >= 3 * MIB
    assert (tmp_path / 'CACHE/aur').exists()

    res = m.clean_storage([])
    assert res['ok'] is True and res['dryRun'] is False
    assert not (tmp_path / 'CACHE/aur').exists()
    assert not (tmp_path / 'CACHE/artifacts/removed').exists()
    assert not (tmp_path / 'CACHE/artifacts/pkg-a').exists()
    assert (tmp_path / 'CACHE/artifacts/pkg-b').exists()
    assert (tmp_path / 'CACHE/artifacts/pkg-c').exists()
    assert not owned.exists()
    assert (tmp_path / 'CACHE/builds/stranger/keep').exists()


def test_makepkg_config_disables_debug(updater, tmp_path):
    cfg = updater.makepkg_config(str(tmp_path))
    text = Path(cfg).read_text(encoding='utf-8')
    assert 'OPTIONS+=(!debug)' in text
    assert '/etc/makepkg.conf' in text
