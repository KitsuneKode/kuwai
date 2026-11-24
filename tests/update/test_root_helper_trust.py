"""An update never installs or runs a root helper copied from the user's checkout."""
import importlib.machinery
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
