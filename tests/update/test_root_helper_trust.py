"""An update never installs or runs a root helper copied from the user's checkout."""
import importlib.machinery
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
