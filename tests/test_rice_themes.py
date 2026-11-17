"""Synchronous theme application observes actual child outcomes in temporary roots."""
import importlib.machinery
import importlib.util
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
@pytest.mark.parametrize('exit_code',[0,7])
def test_wait_completes_child_and_propagates_status(tmp_path,monkeypatch,exit_code):
    loader=importlib.machinery.SourceFileLoader('theme_fixture',str(ROOT/'bin/rice-themes'))
    spec=importlib.util.spec_from_loader('theme_fixture',loader)
    m=importlib.util.module_from_spec(spec);loader.exec_module(m)
    themes=tmp_path/'themes';(themes/'fixture').mkdir(parents=True)
    lib=tmp_path/'lib';lib.mkdir();marker=tmp_path/'completed'
    script=lib/'theme.switch.sh'
    script.write_text('#!/bin/sh\nsleep 0.05\nprintf done > '+str(marker)+'\nexit '+str(exit_code)+'\n');script.chmod(0o755)
    monkeypatch.setattr(m,'THEMES',str(themes));monkeypatch.setattr(m,'LIB',str(lib))
    status=m.main(['theme','fixture','--wait'])
    assert marker.read_text()=='done'
    assert status==exit_code
