"""The secrets policy holds for searches as well as direct reads (synthetic files only)."""
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import rice_files  # noqa: E402

needs_rg = pytest.mark.skipif(not shutil.which("rg"), reason="ripgrep missing")


@pytest.fixture
def tree(tmp_path):
    root = tmp_path / "proj"
    (root / "src").mkdir(parents=True)
    (root / "src/app.py").write_text("NEEDLE = 1\n")
    (root / "credentials.json").write_text('{"NEEDLE": "synthetic-secret"}\n')
    (root / "keys").mkdir()
    (root / "keys/server.pem").write_text("NEEDLE pem\n")
    (root / ".env").write_text("NEEDLE=hidden\n")
    (root / "token_store").mkdir()
    (root / "token_store/plain.txt").write_text("NEEDLE under a secret-named folder\n")
    return root


def test_direct_read_refuses(tree):
    with pytest.raises(rice_files.FileError):
        rice_files.read(tree / "credentials.json")


@needs_rg
def test_recursive_grep_skips_secret_files(tree):
    out = rice_files.grep("NEEDLE", tree)
    assert "app.py:1:NEEDLE = 1" in out
    assert "synthetic-secret" not in out and "pem" not in out and "secret-named" not in out


@needs_rg
@pytest.mark.parametrize("glob", ["credentials.json", "*.json", "**/*.pem", "*", "token_store/**"])
def test_caller_glob_cannot_readmit_secrets(tree, glob):
    out = rice_files.grep("NEEDLE", tree, glob=glob)
    assert "synthetic-secret" not in out and "pem" not in out and "secret-named" not in out


@needs_rg
def test_grep_through_a_link_to_a_secret(tree, tmp_path):
    (tree / "src/innocent.txt").symlink_to(tree / "credentials.json")
    out = rice_files.grep("synthetic", tree)
    assert "synthetic-secret" not in out


@needs_rg
def test_single_file_grep_keeps_plain_format(tree):
    assert rice_files.grep("NEEDLE", tree / "src/app.py") == "1:NEEDLE = 1"


def test_find_hides_secret_names(tree):
    out = rice_files.find("*", tree)
    assert "app.py" in out
    assert "credentials.json" not in out and "server.pem" not in out and "plain.txt" not in out
