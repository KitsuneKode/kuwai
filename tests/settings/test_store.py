"""Real settings entry points, isolated XDG roots; no shell/session invocation."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import pytest

ROOT = Path(__file__).resolve().parents[2]

@pytest.fixture
def store(tmp_path):
    cfg = tmp_path / 'config'
    path = cfg / 'kuwai/settings.json'
    path.parent.mkdir(parents=True)
    path.write_text('{"clock24":false,"hoverDelay":0,"future":{"kept":[null,[]]}}\n')
    env = dict(os.environ, HOME=str(tmp_path), XDG_CONFIG_HOME=str(cfg))
    def run(*args, cli=False):
        return subprocess.run([str(ROOT/'bin'/('kuwai' if cli else 'kuwai-settings')), *args], env=env, text=True, capture_output=True)
    return path, env, run

@pytest.mark.parametrize('key,value', [('unknownSetting','true'),('idleOwner','typo'),('clock24','0'),('textScale','9'),('hoverDelay','-1'),('favoriteThemes','null'),('sleepAt','25:90')])
def test_cli_rejects_invalid_patch_without_touching_file(store,key,value):
    path, _, run = store
    before = path.read_bytes()
    result = run('set',key,value,cli=True)
    assert result.returncode != 0, result.stdout
    assert path.read_bytes() == before


def test_roundtrip_false_zero_arrays_unknown_and_reset(store):
    path, _, run = store
    assert run('set','favoriteThemes','[]').returncode == 0
    doc = json.loads(path.read_text())
    assert doc['clock24'] is False and doc['hoverDelay'] == 0
    assert doc['future'] == {'kept':[None,[]]}
    assert doc['_schemaVersion'] == 1
    assert path.stat().st_mode & 0o777 == 0o600
    assert run('reset','clock24').returncode == 0
    assert 'clock24' not in json.loads(path.read_text())
    assert json.loads(run('get','clock24').stdout) is True


def test_cooperative_writers_merge_distinct_fields(store):
    path, env, _ = store
    procs = [subprocess.Popen([str(ROOT/'bin/kuwai-settings'),'set',key,value], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for key,value in [('showSeconds','true'),('workspaceCount','7')]]
    for p in procs:
        _, err = p.communicate(timeout=8)
        assert p.returncode == 0, err
    doc = json.loads(path.read_text())
    assert doc['showSeconds'] is True and doc['workspaceCount'] == 7
    assert doc['future']['kept'] == [None,[]]

@pytest.mark.parametrize('content', ['{broken', '[]', '{"clock24":"false"}', '{"_schemaVersion":99,"clock24":true}'])
def test_invalid_or_future_document_is_not_replaced(store,content):
    path, _, run = store
    path.write_text(content)
    assert run('set','showSeconds','true').returncode != 0
    assert path.read_text() == content


def test_migration_dry_run_and_backup_are_lossless(store):
    path, _, run = store
    before = '{"clock24":"bad","hoverDelay":0,"future":[null,[]]}'
    path.write_text(before)
    preview = run('migrate','--dry-run')
    assert preview.returncode == 0, preview.stderr
    assert 'clock24' in json.loads(preview.stdout)['invalid']
    assert path.read_text() == before
    migrated = run('migrate')
    assert migrated.returncode == 0, migrated.stderr
    report = json.loads(migrated.stdout)
    assert Path(report['backup']).read_text() == before
    doc = json.loads(path.read_text())
    assert 'clock24' not in doc and doc['hoverDelay'] == 0 and doc['future'] == [None,[]]


def test_interrupted_replace_keeps_original(store,monkeypatch):
    path, _, _ = store
    loader = importlib.machinery.SourceFileLoader('settings_fixture',str(ROOT/'bin/kuwai-settings'))
    spec = importlib.util.spec_from_loader('settings_fixture',loader)
    mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)
    before = path.read_bytes()
    def fail(*args):
        raise OSError('fixture disk failure')
    monkeypatch.setattr(mod.os,'replace',fail)
    with pytest.raises(OSError):
        mod.atomic_write(path,b'{"clock24":true}\n',before)
    assert path.read_bytes() == before
    assert not list(path.parent.glob('*.tmp'))


def test_compare_before_replace_rejects_an_external_editor(store):
    path, _, _ = store
    loader = importlib.machinery.SourceFileLoader('settings_external_fixture',str(ROOT/'bin/kuwai-settings'))
    spec = importlib.util.spec_from_loader('settings_external_fixture',loader)
    mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)
    before = path.read_bytes()
    external = b'{"clock24":true,"future":"external"}'
    path.write_bytes(external)
    with pytest.raises(ValueError, match='changed externally'):
        mod.atomic_write(path,b'{"clock24":false}\n',before)
    assert path.read_bytes() == external
    assert not list(path.parent.glob('*.tmp'))


@pytest.mark.parametrize('content', ['{"future":NaN}', '{"future":Infinity}'])
def test_nonstandard_json_is_not_silently_rewritten(store,content):
    path, _, run = store
    path.write_text(content)
    assert run('set','showSeconds','true').returncode != 0
    assert path.read_text() == content


@pytest.mark.parametrize('content', ['{"future":1.234567890123456789}', '{"future":1e1000}', '{"future":{"a":1,"a":2}}'])
def test_ambiguous_or_unrepresentable_unknown_data_stays_read_only(store,content):
    path, _, run = store
    path.write_text(content)
    result=run('set','showSeconds','true')
    assert result.returncode != 0
    assert path.read_text() == content


def test_future_large_integer_and_exact_decimal_survive(store):
    path, _, run = store
    path.write_text('{"future":{"id":12345678901234567890123456789,"weight":0.1}}')
    assert run('set','showSeconds','true').returncode == 0
    result=json.loads(path.read_text())['future']
    assert result == {'id':12345678901234567890123456789,'weight':0.1}


def test_empty_xdg_config_home_matches_reader_fallback(tmp_path):
    env=dict(os.environ,HOME=str(tmp_path/'home'),XDG_CONFIG_HOME='')
    result=subprocess.run([str(ROOT/'bin/kuwai'),'set','clock24','false'],env=env,cwd=tmp_path,capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    target=tmp_path/'home/.config/kuwai/settings.json'
    assert target.exists() and json.loads(target.read_text())['clock24'] is False
    assert not (tmp_path/'kuwai/settings.json').exists()


def test_kuwai_get_and_bar_apply_propagate_invalid_read(store,tmp_path):
    path,env,run=store
    path.write_text('{broken')
    assert run('get','clock24',cli=True).returncode!=0
    stubs=tmp_path/'stubs';stubs.mkdir(); marker=tmp_path/'bar-started'
    (stubs/'pgrep').write_text('#!/bin/sh\nexit 1\n')
    (stubs/'setsid').write_text('#!/bin/sh\ntouch "'+str(marker)+'"\n')
    for p in stubs.iterdir():p.chmod(0o755)
    env['PATH']=str(stubs)+':'+env['PATH']
    assert run('bar','apply',cli=True).returncode!=0
    assert not marker.exists()


def test_integral_json_floats_are_valid_and_preserved_by_migration(store):
    path,_,run=store
    path.write_text('{"_schemaVersion":1.0,"idleLockAc":600.0,"hoverDelay":0.0}')
    preview=run('migrate','--dry-run')
    assert preview.returncode==0,preview.stderr
    assert json.loads(preview.stdout)['invalid']==[]
    result=run('set','showSeconds','true')
    assert result.returncode==0,result.stderr
    assert json.loads(path.read_text())['idleLockAc']==600
