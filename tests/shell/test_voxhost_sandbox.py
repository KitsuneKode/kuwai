import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
NEEDS = ("qs", "bwrap", "dbus-run-session", "Xvfb", "pgrep")
pytestmark = pytest.mark.skipif(any(shutil.which(b) is None for b in NEEDS), reason="needs qs, bwrap, dbus-run-session, Xvfb and pgrep")


def test_a_new_pill_file_is_drawn_after_the_take_never_during_it():
    with tempfile.TemporaryDirectory(prefix="kuwai-voxhost-") as out:
        run = subprocess.run([str(ROOT / "bin/kuwai-ui-test"), "--case", "voxhost", "--backend", "x11", "--output", out],
                             capture_output=True, text=True, timeout=120)
        if run.returncode == 2:
            pytest.skip("sandbox unqualified: " + run.stdout.strip())
        verdict = json.loads(run.stdout.strip().splitlines()[-1])
        log = (Path(out) / "runtime.log").read_text() if (Path(out) / "runtime.log").exists() else ""
        assert verdict["status"] == "PASS", log[-2000:]
        assert "built again from them" in log


def test_the_rebuild_busts_the_engines_cache_for_every_file_it_loads():
    src = (ROOT / "shell/modules/voxtype/VoxtypeHost.qml").read_text()
    assert '(generation > 0 ? "?v=" + generation : "")' in src
    assert 'c.custom_qml = "file://" + styleQml + "?v=" + generation' in src
    assert "styleFile: generation > 0 && styleQml ? mirror : styleFile" in src
    assert "if (host.takeOn || showing)" in src
