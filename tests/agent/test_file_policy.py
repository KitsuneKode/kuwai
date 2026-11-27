"""The secrets policy holds for searches as well as direct reads (synthetic files only)."""
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import kuwai_files  # noqa: E402

needs_rg = pytest.mark.skipif(not shutil.which("rg"), reason="ripgrep missing")


@pytest.fixture
def tree(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    root = home / "proj"
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
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(tree / "credentials.json")


@needs_rg
def test_recursive_grep_skips_secret_files(tree):
    out = kuwai_files.grep("NEEDLE", tree)
    assert "app.py:1:NEEDLE = 1" in out
    assert "synthetic-secret" not in out and "pem" not in out and "secret-named" not in out


@needs_rg
@pytest.mark.parametrize("glob", ["credentials.json", "*.json", "**/*.pem", "*", "token_store/**"])
def test_caller_glob_cannot_readmit_secrets(tree, glob):
    out = kuwai_files.grep("NEEDLE", tree, glob=glob)
    assert "synthetic-secret" not in out and "pem" not in out and "secret-named" not in out


@needs_rg
def test_grep_through_a_link_to_a_secret(tree, tmp_path):
    (tree / "src/innocent.txt").symlink_to(tree / "credentials.json")
    out = kuwai_files.grep("synthetic", tree)
    assert "synthetic-secret" not in out


@needs_rg
def test_single_file_grep_keeps_plain_format(tree):
    assert kuwai_files.grep("NEEDLE", tree / "src/app.py") == "1:NEEDLE = 1"


def test_find_hides_secret_names(tree):
    out = kuwai_files.find("*", tree)
    assert "app.py" in out
    assert "credentials.json" not in out and "server.pem" not in out and "plain.txt" not in out


def test_agent_credential_stores_are_refused(tmp_path):
    for name in ("credentials.toml", "credentials.yaml"):
        p = tmp_path / name
        p.write_text("api_key = 'synthetic'\n")
        with pytest.raises(kuwai_files.FileError):
            kuwai_files.read(p)


def test_relocated_xdg_dirs_stay_denied(tmp_path, monkeypatch):
    home = tmp_path / "home"
    cfg = tmp_path / "xdg-cfg"
    data = tmp_path / "xdg-data"
    state = tmp_path / "xdg-state"
    cache = tmp_path / "xdg-cache"
    run = tmp_path / "xdg-run"
    for d in (home, cfg, data, state, cache, run):
        d.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setenv("XDG_DATA_HOME", str(data))
    monkeypatch.setenv("XDG_STATE_HOME", str(state))
    monkeypatch.setenv("XDG_CACHE_HOME", str(cache))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(run))

    denied = [
        cfg / "kuwai/secrets/api.env",
        cfg / "kuwai/feeds/gmail.json",
        cfg / "gh/hosts.yml",
        cfg / "chromium/Default/Cookies",
        data / "keyrings/login.keyring",
        data / "kuwai-data/clipboard/history.db",
        data / "voxtype/history.jsonl",
        state / "kuwai/state",
        state / "voxtype/state.json",
        cache / "kuwai/clip/img.png",
        cache / "cliphist/db",
        run / "kuwai/ai/snap.png",
        run / "keyring/control",
    ]
    for f in denied:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("NEEDLE_SECRET\n")
        with pytest.raises(kuwai_files.FileError):
            kuwai_files.read(f)
        with pytest.raises(kuwai_files.FileError):
            kuwai_files.ls(f.parent)

    ok_cfg = cfg / "kuwai/settings.json"
    ok_cfg.parent.mkdir(parents=True, exist_ok=True)
    ok_cfg.write_text('{"theme": "kuwai-night"}\n')
    assert "kuwai-night" in kuwai_files.read(ok_cfg)

    found = kuwai_files.find("*", tmp_path)
    assert "settings.json" in found
    for f in denied:
        assert f.name not in found or str(f) not in found

    if shutil.which("rg"):
        out = kuwai_files.grep("NEEDLE_SECRET", tmp_path)
        assert out == "No matches"


def test_moved_user_dirs_keep_secrets_and_relocated_xdg_denied(tmp_path, monkeypatch):
    home = tmp_path / "home"
    cfg = tmp_path / "xdg-cfg"
    docs = tmp_path / "vault/MyDocuments"
    dl = tmp_path / "vault/MyDownloads"
    state = docs / ".xdg-state"
    for d in (home, cfg, docs, dl, state):
        d.mkdir(parents=True)
    (cfg / "user-dirs.dirs").write_text(
        f'XDG_DOCUMENTS_DIR="{docs}"\n'
        f'XDG_DOWNLOAD_DIR="{dl}"\n'
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setenv("XDG_STATE_HOME", str(state))

    ud = kuwai_files.user_dirs()
    assert ud["DOCUMENTS"] == docs and ud["DOWNLOAD"] == dl

    plain = docs / "notes.txt"
    plain.write_text("NEEDLE ordinary note\n")
    assert "ordinary note" in kuwai_files.read(plain)

    nested_state = state / "kuwai/alarms.json"
    nested_state.parent.mkdir(parents=True, exist_ok=True)
    nested_state.write_text("NEEDLE relocated state secret\n")
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(nested_state)

    secret_folder = dl / "credentials"
    secret_folder.mkdir()
    (secret_folder / "note.txt").write_text("NEEDLE under moved download credentials\n")
    (docs / "alias.txt").symlink_to(secret_folder / "note.txt")
    (dl / "state-link.json").symlink_to(nested_state)
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(docs / "alias.txt")
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(dl / "state-link.json")

    found_docs = kuwai_files.find("*", docs)
    assert "notes.txt" in found_docs
    assert "alarms.json" not in found_docs and "alias.txt" not in found_docs
    if shutil.which("rg"):
        out = kuwai_files.grep("NEEDLE", tmp_path / "vault")
        assert "ordinary note" in out
        assert "relocated state secret" not in out
        assert "moved download credentials" not in out


def test_symlinked_relocated_xdg_dir_stays_denied(tmp_path, monkeypatch):
    home = tmp_path / "home"
    real_cfg = tmp_path / "real-cfg"
    link_cfg = tmp_path / "link-cfg"
    home.mkdir()
    (real_cfg / "kuwai/secrets").mkdir(parents=True)
    secret = real_cfg / "kuwai/secrets/key.txt"
    secret.write_text("TOPSECRET\n")
    link_cfg.symlink_to(real_cfg)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(link_cfg))
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(link_cfg / "kuwai/secrets/key.txt")
    with pytest.raises(kuwai_files.FileError):
        kuwai_files.read(secret)
