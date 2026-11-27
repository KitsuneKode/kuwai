"""The login screen reads your name from its home, as the greeter account.

greeter/install gave that home to the greeter group and then ran
`chown -R USER: home`, which hands it to your own primary group: the greeter
could no longer read .kuwai-user, fell back to its own account name, and the
next login tried your password on the greeter account.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "greeter/install").read_text()


def test_the_home_keeps_the_greeter_group():
    body = SRC[SRC.index("install_code()"):SRC.index("\n}\n", SRC.index("install_code()"))]
    assert 'greeter_group() { [ -z "$SYS" ] && getent group greeter >/dev/null; }' in SRC
    grouped = body[body.index('if greeter_group; then\n        chown -R'):]
    assert re.search(r'chown -R "\$USER_NAME:greeter" "\$DEST/home"', grouped)
    bare = [m.start() for m in re.finditer(r'chown -R "\$USER_NAME": "\$DEST/home"', body)]
    assert len(bare) == 1 and "else" in body[body.rindex("\n", 0, bare[0]) - 40:bare[0]], "a bare chown only where there is no greeter group"


def test_the_install_checks_the_greeter_can_read_the_name():
    assert 'runuser -u greeter -- test -r "$DEST/home/.kuwai-user"' in SRC


def test_undo_takes_root_s_copy_of_the_login_screen_with_it():
    undo = SRC[SRC.index("if [ $MODE = undo ]"):SRC.index("was=$(basename")]
    assert undo.rstrip().endswith("exit 0\nfi") and 'rm -rf -- "$DEST"\n    exit 0' in undo
    assert undo.index('done <"$RECEIPT"') < undo.index('rm -rf -- "$DEST"'), "the saved originals are read first"
