"""Scripts that can run outside a session never fall back to a shared /tmp directory."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BANNED = re.compile(r'XDG_RUNTIME_DIR:-/tmp|XDG_RUNTIME_DIR",\s*"/tmp"|XDG_RUNTIME_DIR\'\)\s*or\s*["\']/tmp')


def test_no_tmp_runtime_fallback_in_scripts():
    hits = []
    for base in ("bin", "lib"):
        for p in (ROOT / base).rglob("*"):
            if p.is_file() and p.stat().st_size < 2_000_000:
                try:
                    text = p.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                for n, line in enumerate(text.splitlines(), 1):
                    if BANNED.search(line):
                        hits.append(f"{p.relative_to(ROOT)}:{n}: {line.strip()}")
    assert not hits, "use the owner-checked runtime dir instead of /tmp:\n" + "\n".join(hits)


def test_update_runtime_is_private(monkeypatch, tmp_path):
    import importlib.machinery
    import importlib.util
    shared = tmp_path / "shared"
    shared.mkdir(mode=0o777)
    shared.chmod(0o777)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(shared))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    loader = importlib.machinery.SourceFileLoader("rt_updater", str(ROOT / "bin/kuwai-update"))
    spec = importlib.util.spec_from_loader("rt_updater", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    assert not m.RUNTIME.startswith(str(shared)), "a group/world-writable runtime dir must not be used"
