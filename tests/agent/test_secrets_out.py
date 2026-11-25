"""What the assistant reads from the clipboard or selection has secrets taken out first."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import kuwai_agent  # noqa: E402


def test_known_token_shapes_are_removed():
    for s in ("ghp_" + "a1B2" * 9, "sk-ant-" + "x" * 30, "AKIA" + "ABCDEFGHIJKLMNOP", "xoxb-1234567890-abcdef"):
        out = kuwai_agent.without_secrets(f"my key is {s} ok")
        assert s not in out and "[secret removed]" in out


def test_a_private_key_block_is_removed_whole():
    pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\ndef\n-----END OPENSSH PRIVATE KEY-----"
    assert kuwai_agent.without_secrets("x\n" + pem + "\ny") == "x\n[secret removed]\ny"


def test_one_random_looking_word_is_removed_but_prose_and_paths_stay():
    assert kuwai_agent.without_secrets("Zq8vT3kLm9PxW2rN5bYc7HdJ") == "[secret removed]"
    for keep in ("the build passed in 3 minutes", "/home/me/Projects/kuwai/README.md", "https://example.com/aB3dE5fG7hJ9kL1mN3pQ5rS7"):
        assert kuwai_agent.without_secrets(keep) == keep


def test_clipboard_and_audit_are_not_offered_in_chat_mode():
    assert "read_clipboard" not in kuwai_agent.CHAT_SAFE
    assert "system_audit" not in kuwai_agent.CHAT_SAFE
