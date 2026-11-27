"""SECURITY.md says precisely what root's own verifier protects: files root reads from your
account can't choose what root trusts, but a script you run with sudo still chooses what runs."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def prose():
    return re.sub(r"\s+", " ", (ROOT / "SECURITY.md").read_text())


def test_a_changed_kuwai_setup_is_not_claimed_harmless():
    text = prose()
    assert "a `kuwai-setup` changed after that can't choose what root trusts" not in text
    assert "a changed `kuwai-verify` or `release-signers/` in your account can't choose what root trusts" in text
    assert "A changed `kuwai-setup` still can, like any script you run that calls `sudo`" in text
