"""What the lock and login screens show to anyone standing at the machine."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_a_hidden_message_hides_its_title_too():
    src = (ROOT / "shell/modules/lock/LockNotifs.qml").read_text()
    heading = src[src.index("function heading(i)"):src.index("function preview(i)")]
    assert 'if (Notifs.lockHidden(i)) return i.app || "Message";' in heading, "a chat app's title is often the message"


def test_lock_art_is_never_fetched_from_the_web():
    src = (ROOT / "shell/modules/lock/LockMedia.qml").read_text()
    assert "Media.artLocal" in src
    assert not re.search(r'source:\s*media\.player \? \(media\.player\.trackArtUrl', src)


def test_the_login_screen_never_shows_greetds_own_error_text():
    src = (ROOT / "shell/greeter.qml").read_text()
    assert '"Couldn\'t log in (" + error' not in src
    assert "launchAck.start();" in src and "launch-timeout" in src, "a launch that never answers returns to the login"
