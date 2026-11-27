"""What the lock and login screens show to anyone standing at the machine."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_a_hidden_message_hides_its_title_too():
    src = (ROOT / "shell/modules/lock/LockNotifs.qml").read_text()
    heading = src[src.index("function heading(i)"):src.index("function preview(i)")]
    assert 'if (Notifs.lockHidden(i)) return i.app || "Message";' in heading, "a chat app's title is often the message"


def test_a_hidden_message_shows_no_status_or_picture_of_its_own():
    src = (ROOT / "shell/modules/lock/LockNotifs.qml").read_text()
    assert "visible: !!card.item.status && !Notifs.lockHidden(card.item)" in src
    assert 'Notifs.lockHidden(card.item) ? NotifAdapters.iconForApp(card.item.app || "")' in src


def test_lock_art_is_never_fetched_from_the_web():
    media = (ROOT / "shell/services/Media.qml").read_text()
    assert 'readonly property string safeArt: /^file:\\/\\//i.test(art) ? art : artRemote ? artLocal : ""' in media
    for f in ("LockMedia.qml", "LockView.qml"):
        src = (ROOT / "shell/modules/lock" / f).read_text()
        assert "Media.safeArt" in src, f"{f}: only local or already-cached art on the lock"
        assert "Media.art :" not in src and "Media.art)" not in src


def test_the_login_screen_never_shows_greetds_own_error_text():
    src = (ROOT / "shell/greeter.qml").read_text()
    assert '"Couldn\'t log in (" + error' not in src
    assert "launchAck.start();" in src and "launch-timeout" in src, "a launch that never answers returns to the login"
