"""bin/kuwai-clip on a fresh cache: `list` must work before any cache folder exists
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
        out = subprocess.run(["bash", str(ROOT / "bin/kuwai-clip"), "list"], env=env, capture_output=True, text=True, timeout=20)
        assert out.returncode == 0, out.stderr
        assert "second" in out.stdout and "first" in out.stdout


def _paste(tmp, active, hint_addr, hint_class=""):
    bindir = Path(tmp, "bin"); bindir.mkdir(exist_ok=True)
    log = Path(tmp, "typed")
    stubs = {
        "hyprctl": f"#!/bin/sh\n[ \"$1\" = activewindow ] && printf '%s' '{active}'\nexit 0\n",
        "wtype": f"#!/bin/sh\necho \"$*\" >> {log}\n",
        "wl-copy": "#!/bin/sh\ncat >/dev/null\n",
    }
    for name, body in stubs.items():
        p = bindir / name; p.write_text(body); p.chmod(0o755)
    env = {"HOME": str(Path(tmp, "home")), "PATH": f"{bindir}:/usr/bin:/bin"}
    r = subprocess.run(["bash", str(ROOT / "bin/kuwai-clip"), "paste-text", "rm -rf ~\n", hint_class, hint_addr],
                       env=env, capture_output=True, text=True, timeout=20)
    return r, (log.read_text() if log.exists() else "")


def test_a_paste_is_typed_only_into_the_window_it_was_for():
    with tempfile.TemporaryDirectory() as d:
        r, typed = _paste(d, '{"address": "0xbbb", "class": "kitty"}', "0xaaa", "firefox")
        assert r.returncode == 3 and typed == "", "another window in front: nothing is typed, the text stays on the clipboard"
    with tempfile.TemporaryDirectory() as d:
        r, typed = _paste(d, '{"address": "0xaaa", "class": "kitty"}', "0xaaa", "firefox")
        assert r.returncode == 0, r.stderr
        assert "-M shift" in typed, "the keys follow the window really in front (a terminal), not the hint"
