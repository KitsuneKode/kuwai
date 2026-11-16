"""A native capture must not hide runtime exceptions or binding failures."""
import importlib.machinery
import importlib.util
from pathlib import Path
import pytest

@pytest.mark.parametrize('line', ['TypeError: missing function', 'ReferenceError: missing binding', 'Unable to assign [undefined] to bool', 'UI_SMOKE_FAILED: overlap'])
def test_native_errors_fail_even_after_capture(line):
    path = Path(__file__).resolve().parents[2]/'bin/rice-ui-test'
    loader = importlib.machinery.SourceFileLoader('ui_fixture',str(path))
    spec = importlib.util.spec_from_loader('ui_fixture',loader)
    mod = importlib.util.module_from_spec(spec);loader.exec_module(mod)
    assert mod.has_runtime_failure('Configuration Loaded\n'+line+'\nUI_SMOKE_CAPTURED')
