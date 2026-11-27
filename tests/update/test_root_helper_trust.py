"""An update never installs or runs a root helper copied from the user's checkout."""
import importlib.machinery
import json
import io
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def updater(monkeypatch):
    loader = importlib.machinery.SourceFileLoader('helper_updater', str(ROOT / 'bin/kuwai-update'))
    spec = importlib.util.spec_from_loader('helper_updater', loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


class FakeRun:
    def __init__(self):
        self.streamed, self.events = [], []
        self.log = io.StringIO()

    def stream(self, cmd, progress=None):
        self.streamed.append(cmd)
        return 0

    def emit(self, **ev):
        self.events.append(ev)


class Out:
    def readline(self):
        return '{"ready": true}\n'

    def __iter__(self):
        return iter([])


class Hello:
    def __init__(self, cmd):
        self.cmd = cmd
        self.stdout = Out()
        self.stdin = io.StringIO()


def test_stale_or_missing_helper_falls_back_to_plain_pkexec(updater, monkeypatch):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    popened = []
    monkeypatch.setattr(m.subprocess, 'Popen', lambda cmd, **kw: popened.append(cmd) or Hello(cmd))
    R = FakeRun()
    root = m.Root(R)
    assert root.run('upgrade') == 0
    assert popened == [], 'no helper may be started when the installed one is not verified'
    assert R.streamed and R.streamed[0][:2] == ['pkexec', 'pacman']
    for cmd in R.streamed:
        assert m.HELPER_SRC not in cmd and '/usr/bin/install' not in ' '.join(cmd)
    assert any('install-helper' in str(e.get('line', '')) for e in R.events), 'tell the user how to set the helper up'


def test_verified_helper_is_started_directly(updater, monkeypatch):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: True)
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: True)
    popened = []
    monkeypatch.setattr(m.subprocess, 'Popen', lambda cmd, **kw: popened.append(cmd) or Hello(cmd))
    root = m.Root(FakeRun())
    assert root.open() == 0
    assert popened == [['pkexec', m.HELPER]]


def test_a_held_package_is_ignored_even_without_the_helper(updater, monkeypatch):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    R = FakeRun()
    assert m.Root(R).run('upgrade', hold=['nvidia-dkms', 'linux-lts']) == 0
    assert R.streamed[0] == ['pkexec', 'pacman', '-Syu', '--noconfirm', '--needed', '--ignore', 'nvidia-dkms,linux-lts']
    R = FakeRun()
    assert m.Root(R).run('upgrade', deps=['meson'], hold=['linux-lts']) == 0
    assert 'KUWAI_HOLD=linux-lts' in R.streamed[0] and '--ignore "$KUWAI_HOLD"' in ' '.join(R.streamed[0])


def test_the_password_prompt_names_the_transaction(updater, monkeypatch):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: True)
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: True)
    monkeypatch.setattr(m, 'expected_plan', lambda hold=(): ['linux 7.3-1', 'mesa 26.1-1'])
    popened = []
    monkeypatch.setattr(m.subprocess, 'Popen', lambda cmd, **kw: popened.append(cmd) or Hello(cmd))
    root = m.Root(FakeRun())
    assert root.open({'upgrade': m.plan_token(['mesa 26.1-1', 'linux 7.3-1']), 'hold': ['linux-lts'],
                      'deps': ['meson'], 'install': ['paru', 'foo'], 'clean-cache': 2}) == 0
    assert popened[0] == ['pkexec', m.HELPER, 'upgrade=' + m.plan_token(['linux 7.3-1', 'mesa 26.1-1']),
                          'hold=linux-lts', 'deps=meson', 'install=foo,paru', 'clean-cache=2']
    root = m.Root(FakeRun())
    root.run('upgrade', hold=['linux-lts'])
    assert popened[1][:3] == ['pkexec', m.HELPER, 'upgrade=' + m.plan_token(['linux 7.3-1', 'mesa 26.1-1'])]


def test_built_packages_need_a_prompt_that_named_them(updater, monkeypatch):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: True)
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: True)
    popened = []
    monkeypatch.setattr(m.subprocess, 'Popen', lambda cmd, **kw: popened.append(cmd) or Hello(cmd))
    R = FakeRun()
    assert m.Root(R).run('install', files=[{'path': '/x.pkg.tar.zst', 'sha256': '0' * 64}]) == 1
    assert popened == []


def test_the_helper_is_installed_only_from_roots_checked_release(updater, monkeypatch, capsys):
    m = updater
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    ran = []
    monkeypatch.setattr(m.subprocess, 'run', lambda cmd, **kw: ran.append(cmd) or type('R', (), {'returncode': 0, 'stderr': ''})())
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: False)
    assert m.main(['install-helper']) == 1
    assert ran == [] and 'kuwai setup' in capsys.readouterr().out
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: p == m.RELEASE_VERIFY)
    m.main(['install-helper'])
    assert ran == [['pkexec', '/usr/bin/python3', '-I', m.RELEASE_VERIFY, 'place', 'update-helper']]
    assert all(m.HELPER_SRC not in ' '.join(c) for c in ran), "never the checkout's copy"
    assert m.main(['install-helper', '--anything']) == 2


def test_without_roots_release_every_hint_names_the_way_that_works(updater, monkeypatch, capsys, tmp_path):
    m = updater
    monkeypatch.setattr(m, 'RELEASE', str(tmp_path / 'current'))
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    R = FakeRun()
    root = m.Root(R)
    root.run('upgrade')
    root.run('install', files=['/x.pkg.tar.zst'])
    hints = [str(e.get('line', '')) for e in R.events]
    assert len(hints) == 2 and all('kuwai update install-helper --trust-clone' in h and 'trust' in h.split('--trust-clone', 1)[1]
                                   for h in hints), hints
    assert m.main(['install-helper']) == 1
    error = json.loads(capsys.readouterr().out)['error']
    assert 'kuwai update install-helper --trust-clone' in error and 'kuwai setup' in error
    (tmp_path / 'current').symlink_to('releases/v1.0.0')
    R = FakeRun()
    m.Root(R).run('upgrade')
    assert '--trust-clone' not in R.events[0]['line'] and 'kuwai update install-helper' in R.events[0]['line']


def test_when_this_copy_is_ahead_of_roots_release_the_hints_name_trust_clone(updater, monkeypatch, capsys, tmp_path):
    m = updater
    release = tmp_path / 'releases/v1.0.0'
    (release / 'bin').mkdir(parents=True)
    (release / 'bin/kuwai-update-root').write_text('#!/usr/bin/python3\nolder\n')
    (tmp_path / 'current').symlink_to('releases/v1.0.0')
    monkeypatch.setattr(m, 'RELEASE', str(tmp_path / 'current'))
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    R = FakeRun()
    root = m.Root(R)
    root.run('upgrade')
    root.run('install', files=['/x.pkg.tar.zst'])
    hints = [str(e.get('line', '')) for e in R.events]
    assert len(hints) == 2 and all('kuwai setup --system' in h and 'ahead of the newest release' in h
                                   and 'kuwai update install-helper --trust-clone' in h for h in hints), hints
    monkeypatch.setattr(m.os.path, 'isfile', lambda p: p == m.RELEASE_VERIFY)
    monkeypatch.setattr(m.subprocess, 'run', lambda cmd, **kw: type('R', (), {'returncode': 0, 'stderr': ''})())
    assert m.main(['install-helper']) == 1
    error = json.loads(capsys.readouterr().out)['error']
    assert 'kuwai setup --system' in error and 'ahead of the newest release' in error
    assert 'kuwai update install-helper --trust-clone' in error
    (release / 'bin/kuwai-update-root').write_bytes(Path(m.HELPER_SRC).read_bytes())
    monkeypatch.undo()
    monkeypatch.setattr(m, 'RELEASE', str(tmp_path / 'current'))
    monkeypatch.setattr(m, 'helper_ok', lambda: False)
    R = FakeRun()
    m.Root(R).run('upgrade')
    assert '--trust-clone' not in R.events[0]['line'] and 'kuwai update install-helper' in R.events[0]['line']


def test_pacnew_names_the_way_to_the_helper_that_works(monkeypatch, tmp_path, capsys):
    loader = importlib.machinery.SourceFileLoader('pacnew_helper', str(ROOT / 'bin/kuwai-pacnew'))
    spec = importlib.util.spec_from_loader('pacnew_helper', loader)
    p = importlib.util.module_from_spec(spec)
    loader.exec_module(p)
    monkeypatch.setattr(p, 'RELEASE', str(tmp_path / 'current'))
    monkeypatch.setattr(p, 'find', lambda: ['/etc/x.conf'])
    monkeypatch.setattr(p, 'helper_cmd', lambda: None)
    assert p.apply(json.dumps([{'path': '/etc/x.conf', 'action': 'keep'}])) == 1
    assert 'kuwai update install-helper --trust-clone' in json.loads(capsys.readouterr().out)['log'][0]
