"""bin/rice-clip on a fresh cache: `list` must work before any cache folder exists
(a non-fatal cleanup; under set -e one failed `find` once emptied the clipboard panel)."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_list_works_on_an_empty_cache():
    with tempfile.TemporaryDirectory() as d:
        bindir = Path(d, "bin"); bindir.mkdir()
        stub = bindir / "cliphist"
        stub.write_text("#!/bin/sh\n[ \"$1\" = list ] && printf '2\\tsecond\\n1\\tfirst\\n'\nexit 0\n")
        stub.chmod(0o755)
        env = {"HOME": str(Path(d, "home")), "PATH": f"{bindir}:/usr/bin:/bin"}
        out = subprocess.run(["bash", str(ROOT / "bin/rice-clip"), "list"], env=env, capture_output=True, text=True, timeout=20)
        assert out.returncode == 0, out.stderr
        assert "second" in out.stdout and "first" in out.stdout
