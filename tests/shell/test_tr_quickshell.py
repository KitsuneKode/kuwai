"""Tr (shell/config/Tr.qml) in a real Quickshell, not just its logic in bun.

Quickshell 0.3.2 installs no QTranslator, so qsTr() can't translate
(docs/design/TRANSLATION.md); this proves the path that replaces it, end to
end: the singleton picks the catalogue from the locale, the real PowerPanel
and Dates read it, English stays the default and the fallback. Runs offscreen
in the bwrap sandbox bin/kuwai-ui-test uses (no host bus, home or network;
every bin/ helper a stub; services/ reduced to the two PowerPanel calls, as
the real ones need a layer-shell window), so nothing of the session is touched. Skips where
qs, bwrap or dbus-run-session are missing.
"""
import json
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
NEEDS = ("qs", "bwrap", "dbus-run-session")
pytestmark = pytest.mark.skipif(any(shutil.which(b) is None for b in NEEDS), reason="needs qs, bwrap and dbus-run-session")

# A plural entry the shipped catalogue doesn't have yet: added to the copy only.
PLURAL = {"{n} update": {"one": "{n} Aktualisierung", "other": "{n} Aktualisierungen"}}


def run(env_extra: dict, out_dir: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix="kuwai-tr-") as private:
        private = Path(private)
        app, home = private / "app", private / "home"
        home.mkdir()
        shutil.copytree(ROOT / "shell", app / "shell")
        de = app / "shell/i18n/de.json"
        cat = json.loads(de.read_text())
        cat.update(PLURAL)
        de.write_text(json.dumps(cat, ensure_ascii=False))
        # The services module needs a layer-shell window (WallFx), which
        # offscreen has none of: the copy gets the two PowerPanel calls as stubs.
        shutil.rmtree(app / "shell/services")
        (app / "shell/services").mkdir()
        for name, body in (("Island", "function close() {}"), ("Goodbye", "function run(kind, cmd) {}")):
            (app / f"shell/services/{name}.qml").write_text(
                f"pragma Singleton\nimport Quickshell\nSingleton {{ {body} }}\n")
        (app / "shell/tr-probe.qml").write_text((ROOT / "tests/ui/tr-probe.qml").read_text())
        helpers = app / "bin"
        helpers.mkdir()
        for original in (ROOT / "bin").iterdir():
            if original.is_file():
                stub = helpers / original.name
                stub.write_text("#!/bin/sh\nexit 99\n")
                stub.chmod(0o755)
        command = ["bwrap", "--unshare-all", "--die-with-parent", "--new-session",
                   "--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
                   "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
                   "--dir", "/etc", "--ro-bind", "/etc/fonts", "/etc/fonts", "--dir", "/etc/dbus-1",
                   "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/run", "--tmpfs", "/tmp",
                   "--dir", "/home", "--bind", str(home), "/home/test",
                   "--ro-bind", str(app), "/app", "--bind", str(out_dir), "/out", "--chdir", "/app"]
        env = {"PATH": "/app/bin:/usr/bin:/bin", "HOME": "/home/test", "USER": "test", "XDG_RUNTIME_DIR": "/run/test",
               "XDG_CONFIG_HOME": "/home/test/config", "XDG_STATE_HOME": "/home/test/state",
               "XDG_CACHE_HOME": "/home/test/cache", "XDG_DATA_HOME": "/home/test/data",
               "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", "QSG_RENDER_LOOP": "basic",
               "KUWAI_ROOT": "/app", "KUWAI_REDUCE_MOTION": "1", "KUWAI_DRYRUN": "1"}
        env.update(env_extra)
        for k, v in env.items():
            command += ["--setenv", k, v]
        command += ["/usr/bin/sh", "-c", "mkdir -p /run/test; chmod 700 /run/test; exec dbus-run-session -- qs -p /app/shell/tr-probe.qml"]
        # Quickshell ignores Qt.quit(): read until the probe reports, then stop
        # the sandbox (bwrap --die-with-parent takes everything in it along).
        proc = subprocess.Popen(command, env={"PATH": "/usr/bin:/bin"}, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, start_new_session=True)
        lines = []
        timer = threading.Timer(30, proc.kill)
        timer.start()
        try:
            for line in proc.stdout:
                lines.append(line)
                if "TR_CAPTURED" in line or "No PanelWindow backend" in line:
                    break
        finally:
            timer.cancel()
            proc.kill()
            proc.wait()
        log = "".join(lines)
        (out_dir / "runtime.log").write_text(log)
        for line in log.splitlines():
            if "TR_RESULT " in line:
                return json.loads(line.split("TR_RESULT ", 1)[1])
        raise AssertionError("no TR_RESULT:\n" + log[-3000:])


@pytest.fixture
def out(tmp_path):
    return tmp_path


def test_english_by_default(out):
    r = run({"LANG": "C.UTF-8"}, out)
    assert r["language"] == ""
    assert [t["text"] for t in r["tiles"]] == ["Lock", "Sleep", "Log Out", "Restart", "Firmware", "Shut Down"]
    assert r["hints"][0]["text"] == "Click or press ↵ to lock"
    assert r["hints"][5]["text"] == "Hold to shut down"
    assert r["hints"][4]["text"] == "Hold to restart into the firmware setup"
    assert r["today"] == "Today" and r["yesterday"] == "Yesterday"
    assert r["one"] == "1 update" and r["many"] == "5 updates"


def test_german_under_a_german_locale(out):
    r = run({"LANG": "de_DE.UTF-8"}, out)
    assert r["locale"] == "de_DE" and r["language"] == "de"
    assert [t["text"] for t in r["tiles"]] == ["Sperren", "Bereitschaft", "Abmelden", "Neu starten", "Firmware", "Herunterfahren"]
    assert r["hints"][5]["text"] == "Zum Herunterfahren gedrückt halten"
    assert r["today"] == "Heute" and r["yesterday"] == "Gestern"
    # Plural through the singleton: the category for the count.
    assert r["one"] == "1 Aktualisierung" and r["many"] == "5 Aktualisierungen"
    # A key no catalogue has reads English; a value put into a text is never looked up.
    assert r["missing"] == "A string no catalogue has"
    assert r["outside"] == "Shut Down"
    # The tiles grow to the longest label ("Herunterfahren"): every label fits inside its tile.
    assert all(t["w"] < t["tile"] for t in r["tiles"])
    print("GEOMETRY de", json.dumps({"tiles": r["tiles"], "hints": r["hints"]}, ensure_ascii=False))
    assert (out / "power.png").is_file()


def test_language_list_order(out):
    # LANGUAGE=fr:de with no French catalogue: German, the next one asked for.
    r = run({"LANG": "fr_FR.UTF-8", "LANGUAGE": "fr:de"}, out)
    assert r["language"] == "de" and r["tiles"][0]["text"] == "Sperren"
    # English listed first wins over German.
    r = run({"LANG": "de_DE.UTF-8", "LANGUAGE": "en:de"}, out)
    assert r["language"] == "" and r["tiles"][0]["text"] == "Lock"


def test_pseudo_locale_is_longer(out):
    r = run({"LANG": "C.UTF-8", "KUWAI_PSEUDO": "1"}, out)
    assert all(t["text"].startswith("[") for t in r["tiles"])
    print("GEOMETRY pseudo", json.dumps({"tiles": r["tiles"], "hints": r["hints"]}, ensure_ascii=False))


def test_no_brace_above_pragma_singleton():
    """Quickshell 0.3.2 reads a `{` above `pragma Singleton`, even in a comment,
    as the object's start: the file then loads as an empty object, with no
    error (found building Tr.qml: `Tr.t` was "not a function")."""
    bad = []
    for p in (ROOT / "shell").rglob("*.qml"):
        text = p.read_text(encoding="utf-8", errors="replace")
        at = text.find("pragma Singleton")
        if at > 0 and "{" in text[:at]:
            bad.append(str(p.relative_to(ROOT)))
    assert bad == []
