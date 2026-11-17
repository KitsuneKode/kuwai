"""greeter/sync: what a program running as you may write into the login screen.

The login screen takes the login password, so its code is root's
(greeter/install); sync, which runs as you at every login, copies data only.
A directory from before that split (all yours) keeps working as it did.
"""
import os
import stat
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SYNC = REPO / "greeter" / "sync"


def run(dest, home):
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "KUWAI_GREETER_DIR": str(dest)}
    return subprocess.run([str(SYNC)], env=env, capture_output=True, text=True)


def home_with_data(tmp_path):
    home = tmp_path / "home"
    (home / ".config/rice").mkdir(parents=True)
    (home / ".config/rice/settings.json").write_text('{"clock24": true}')
    (home / ".face").write_bytes(b"png")
    return home


def test_locked_layout_gets_data_only(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "greeter"
    (dest / "home").mkdir(parents=True)
    (dest / "start").write_text("#!/bin/sh\n# root's\n")
    (dest / "shell").mkdir()
    (dest / "shell" / "greeter.qml").write_text("// root's\n")
    os.chmod(dest / "shell", 0o555)
    os.chmod(dest, 0o555)                      # as root-owned 0755 looks to you
    try:
        r = run(dest, home)
        assert r.returncode == 0, r.stderr
        assert (dest / "start").read_text() == "#!/bin/sh\n# root's\n"
        assert (dest / "shell" / "greeter.qml").read_text() == "// root's\n"
        assert not (dest / "user").exists() and not (dest / "face").exists()
        assert (dest / "home/.kuwai-user").read_text().strip()
        assert (dest / "home/.face").read_bytes() == b"png"
        assert (dest / "home/.config/rice/settings.json").read_text() == '{"clock24": true}'
        assert "still writable" not in r.stderr
    finally:
        os.chmod(dest, 0o755)
        os.chmod(dest / "shell", 0o755)


def test_not_installed_does_nothing(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "missing"
    assert run(dest, home).returncode == 0
    assert not dest.exists()


def test_old_layout_still_works_and_says_how_to_close_it(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "greeter"
    dest.mkdir()                                # all yours: the layout before the split
    r = run(dest, home)
    assert r.returncode == 0, r.stderr
    assert "greeter/install --code" in r.stderr
    assert (dest / "shell" / "greeter.qml").exists() and (dest / "start").exists()
    assert stat.S_IMODE((dest / "start").stat().st_mode) == 0o755
    assert (dest / "user").read_text().strip() and (dest / "face").read_bytes() == b"png"
    assert (dest / "home/.kuwai-user").exists()


def test_install_script_keeps_the_code_roots():
    text = (REPO / "greeter" / "install").read_text()
    assert 'install -d -m755 -o root -g root "$DEST"' in text
    assert '-o "$USER_NAME" "$DEST/home"' in text
    assert '-o "$USER_NAME" "$DEST"\n' not in text      # the whole directory is never yours again
