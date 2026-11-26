"""Reviewed recipe preparation must fail before any executable PKGBUILD is read."""
import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[2]

@pytest.fixture
def updater(tmp_path, monkeypatch):
    loader = importlib.machinery.SourceFileLoader('recipe_updater', str(ROOT / 'bin/kuwai-update'))
    spec = importlib.util.spec_from_loader('recipe_updater', loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    monkeypatch.setattr(m, 'agent_missing', lambda: False)
    for key in ('RUNTIME', 'CACHE', 'STATE', 'AUR_DIR', 'LOG_DIR'):
        monkeypatch.setattr(m, key, str(tmp_path / key))
    for key in ('LOCK', 'EVENTS', 'APPROVED', 'TRUSTED', 'INSTALLED'):
        monkeypatch.setattr(m, key, str(tmp_path / key))
    return m

@pytest.mark.parametrize('failure', ['checkout', 'clean', 'wrong-head', 'dirty'])
def test_failed_preparation_never_executes_makepkg(updater, monkeypatch, failure, tmp_path):
    m = updater
    head = '1' * 40
    monkeypatch.setattr(m, 'clone', lambda pkg: (str(tmp_path), head))
    m.save(m.APPROVED, {'fixture': head})
    monkeypatch.setattr(m.os, 'statvfs', lambda p: SimpleNamespace(f_bavail=10**10, f_frsize=1))
    calls = []
    def git(d, *args, check=False):
        if args[0] == failure:
            if check: raise RuntimeError('synthetic prep failure')
            return SimpleNamespace(returncode=128, stdout='', stderr='synthetic prep failure')
        out = ('2' * 40 if failure == 'wrong-head' else head) if args[0] == 'rev-parse' else ''
        if args[0] == 'status' and failure == 'dirty': out = ' M PKGBUILD'
        return SimpleNamespace(returncode=0, stdout=out, stderr='')
    monkeypatch.setattr(m, 'git', git)
    monkeypatch.setattr(m, 'missing_deps', lambda d: (calls.append('makepkg --printsrcinfo') or ([], [], True)))
    class Run:
        path = 'synthetic'
        def emit(self, **event): pass
        def stream(self, *args, **kwargs): calls.append('makepkg'); return 1
    class Root:
        helper = False
        prompts = 0
        def __init__(self, r): pass
        def close(self): pass
    monkeypatch.setattr(m, 'Run', Run)
    monkeypatch.setattr(m, 'Root', Root)
    m.run(['--aur', 'fixture'])
    assert calls == []


def test_verified_installed_recipe_precedes_same_version_guess(updater, monkeypatch, tmp_path):
    m = updater
    subprocess.run(['git', 'init', '-q', str(tmp_path)], check=True)
    def git(*args):
        return subprocess.run(['git', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-C', str(tmp_path), *args], capture_output=True, text=True, check=True).stdout.strip()
    for text in ('old recipe', 'changed recipe, same version'):
        (tmp_path / 'PKGBUILD').write_text(text)
        (tmp_path / '.SRCINFO').write_text('pkgbase = fixture\npkgver = 1.0\npkgrel = 1\n')
        git('add', 'PKGBUILD', '.SRCINFO')
        git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        if text == 'old recipe':
            installed = git('rev-parse', 'HEAD')
            git('update-ref', 'refs/kuwai/installed', installed)
    newest = git('rev-parse', 'HEAD')
    monkeypatch.setattr(m, 'installed_version', lambda p: '1.0-1')
    # No durable receipt means we cannot prove which matching-version recipe was installed.
    assert m.baseline(str(tmp_path), 'fixture', newest) == ''


def test_durable_receipt_owns_baseline_and_invalidates_external_install(updater, monkeypatch, tmp_path):
    m = updater
    old, new = '1' * 40, '2' * 40
    monkeypatch.setattr(m, 'installed_fingerprint', lambda p: {'version': '1.0-1', 'identity': 'install-A'}, raising=False)
    monkeypatch.setattr(m, 'installed_version', lambda p: '1.0-1')
    monkeypatch.setattr(m, 'git', lambda d, *args, **kw: SimpleNamespace(returncode=0, stdout=old))
    m.record_install('fixture', old, [])
    assert m.baseline(str(tmp_path), 'fixture', new) == old
    # Same package version installed outside this updater is not the same installation.
    monkeypatch.setattr(m, 'installed_fingerprint', lambda p: {'version': '1.0-1', 'identity': 'install-B'})
    assert m.baseline(str(tmp_path), 'fixture', new) == ''


def test_recipe_build_uses_fresh_disposable_workspace(updater, tmp_path):
    m = updater
    repo = tmp_path / 'recipe'
    repo.mkdir()
    def git(*args):
        return subprocess.run(['git','-c','commit.gpgsign=false','-c','core.hooksPath=/dev/null','-C',str(repo),*args],capture_output=True,text=True,check=True).stdout.strip()
    git('init','-q')
    (repo/'PKGBUILD').write_text('fixture recipe, never executed')
    git('add','PKGBUILD');git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture')
    head=git('rev-parse','HEAD')
    stage=m.prepare_recipe(str(repo), 'fixture', head)
    assert Path(stage).is_relative_to(Path(m.CACHE))
    assert (Path(stage)/'PKGBUILD').read_text() == 'fixture recipe, never executed'
    assert not (Path(stage)/'src').exists()
    assert (repo/'PKGBUILD').read_text() == 'fixture recipe, never executed'


def test_split_output_resolves_its_recipe_base(updater, monkeypatch, tmp_path):
    m = updater
    monkeypatch.setattr(m, 'aur_info', lambda names: {'fixture-libs': {'packageBase':'fixture'}})
    clones=[]
    monkeypatch.setattr(m, 'sh', lambda cmd, **kw: (clones.append(cmd) or SimpleNamespace(returncode=0,stdout='',stderr='')))
    monkeypatch.setattr(m, 'git', lambda *args, **kw: SimpleNamespace(returncode=0,stdout='1'*40,stderr=''))
    directory, head=m.clone('fixture-libs')
    assert Path(directory).name == 'fixture'
    assert clones[0][-2] == 'https://aur.archlinux.org/fixture.git'


def test_only_selected_split_artifacts_are_installed(updater, monkeypatch, tmp_path):
    a,b=tmp_path/'fixture.pkg.tar.zst',tmp_path/'fixture-debug.pkg.tar.zst'
    a.write_bytes(b'fixture');b.write_bytes(b'fixture debug')
    def sh(cmd, **kw):
        text=str(a)+'\n'+str(b)+'\n' if cmd[0]=='makepkg' else ('fixture 1.0-1' if cmd[-1]==str(a) else 'fixture-debug 1.0-1')
        return SimpleNamespace(returncode=0,stdout=text,stderr='')
    monkeypatch.setattr(updater,'sh',sh)
    assert updater.package_files(str(tmp_path),['fixture']) == [str(a)]
    with pytest.raises(RuntimeError): updater.package_files(str(tmp_path),['missing-output'])


def test_successful_workspace_keeps_artifacts_but_releases_sources(updater, tmp_path, monkeypatch):
    m=updater
    repo=Path(m.AUR_DIR)/'fixture';repo.mkdir(parents=True)
    def git(*args):
        return subprocess.run(['git','-c','commit.gpgsign=false','-c','core.hooksPath=/dev/null','-C',str(repo),*args],capture_output=True,text=True,check=True).stdout.strip()
    git('init','-q');(repo/'PKGBUILD').write_text('fixture');git('add','PKGBUILD')
    git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture')
    stage=m.prepare_recipe(str(repo),'fixture',git('rev-parse','HEAD'))
    archive=Path(stage)/'fixture-1.0-1-any.pkg.tar.zst';archive.write_bytes(b'archive')
    (Path(stage)/'src').mkdir();(Path(stage)/'src/large').write_bytes(b'source')
    kept=m.finish_workspace(stage,[str(archive)])
    assert not Path(stage).exists()
    assert len(kept)==1 and Path(kept[0]).read_bytes()==b'archive'


def test_withdrawal_is_persisted(updater):
    updater.save(updater.APPROVED,{'fixture':'1'*40,'other':'2'*40})
    assert updater.main(['unapprove','fixture'])==0
    assert updater.load(updater.APPROVED,{})=={'other':'2'*40}


def test_cancelled_authentication_closes_helper_and_prunes_while_locked(updater, monkeypatch, tmp_path):
    m=updater;head='1'*40;closed=[];pruned=[]
    m.save(m.APPROVED,{'fixture':head})
    monkeypatch.setattr(m,'clone',lambda pkg:(str(tmp_path),head))
    monkeypatch.setattr(m,'prepare_recipe',lambda *args:str(tmp_path))
    monkeypatch.setattr(m,'missing_deps',lambda path:([],[],True))
    monkeypatch.setattr(m.os,'statvfs',lambda p:SimpleNamespace(f_bavail=10**10,f_frsize=1))
    monkeypatch.setattr(m,'prune_failed_workspaces',lambda:pruned.append(True))
    class Run:
        path='fixture'
        def emit(self,**event):pass
    class Root:
        helper=True
        def __init__(self,r):pass
        def open(self, ops=()):return 126
        def close(self):closed.append(True)
    monkeypatch.setattr(m,'Run',Run);monkeypatch.setattr(m,'Root',Root)
    assert m.run(['--aur','fixture'])==1
    assert closed==[True] and pruned==[True]
