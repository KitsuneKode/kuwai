"""kuwai-secrets: keys leave the shell's startup files for the keyring, and a value is never printed."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALUE = "sk-test-0123456789abcdef"


def env_for(tmp_path):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    store = tmp_path / "store"
    store.mkdir()
    (bin_ / "secret-tool").write_text(f"""#!/bin/bash
case $1 in
  store) shift 3; cat > "{store}/$4" ;;
  lookup) [ -f "{store}/$5" ] && cat "{store}/$5" || exit 1 ;;
  search) for f in "{store}"/*; do [ -f "$f" ] && echo "attribute.key = $(basename "$f")"; done ;;
esac
""")
    (bin_ / "secret-tool").chmod(0o755)
    home = tmp_path / "home"
    home.mkdir()
    return dict(os.environ, HOME=str(home), PATH=f"{bin_}:{os.environ['PATH']}", ZDOTDIR=""), home, store


def run(env, *args):
    return subprocess.run([str(ROOT / "bin/kuwai-secrets"), *args], env=env, capture_output=True, text=True, timeout=20)


def test_scan_and_move_never_print_the_value(tmp_path):
    env, home, store = env_for(tmp_path)
    rc = home / ".zshrc"
    rc.write_text(f'alias x=1\nexport OPENAI_API_KEY="{VALUE}"\nalias ccx="env OPENAI_API_KEY={VALUE} tool"\n')
    rc.chmod(0o600)
    s = run(env, "scan")
    assert "OPENAI_API_KEY" in s.stdout and ":2" in s.stdout and ":3" in s.stdout
    m = run(env, "move", "OPENAI_API_KEY")
    assert m.returncode == 0
    for out in (s, m):
        assert VALUE not in out.stdout + out.stderr
    text = rc.read_text().split("\n")
    assert text[1] == 'export OPENAI_API_KEY="$(secret-tool lookup service kuwai-env key OPENAI_API_KEY 2>/dev/null </dev/null)"'
    assert VALUE in text[2], "a key inside a command is left for you, with how to move it"
    assert "inside a command" in m.stdout
    assert (store / "OPENAI_API_KEY").read_text() == VALUE
    assert oct(rc.stat().st_mode & 0o777) == "0o600"
    assert run(env, "list").stdout.strip() == "OPENAI_API_KEY"


def test_run_gives_only_that_command_the_key(tmp_path):
    env, home, store = env_for(tmp_path)
    (store / "TOKEN_X").write_text(VALUE)
    p = run(env, "run", "TOKEN_X", "--", "sh", "-c", 'test "$TOKEN_X" = "$1" && echo same', "sh", VALUE)
    assert p.stdout.strip() == "same"


def test_a_keyring_that_does_not_keep_it_changes_nothing(tmp_path):
    env, home, store = env_for(tmp_path)
    (tmp_path / "bin" / "secret-tool").write_text("#!/bin/sh\nexit 1\n")
    rc = home / ".bashrc"
    before = f"export GH_TOKEN={VALUE}\n"
    rc.write_text(before)
    m = run(env, "move", "GH_TOKEN")
    assert m.returncode == 1 and rc.read_text() == before
    assert VALUE not in m.stdout + m.stderr


def test_commented_and_fish_keys_are_reported_not_missed(tmp_path):
    env, home, store = env_for(tmp_path)
    (home / ".zshrc").write_text(f'# export OLD_TOKEN={VALUE}\n')
    (home / ".config/fish").mkdir(parents=True)
    (home / ".config/fish/config.fish").write_text(f'set -gx FISH_API_KEY {VALUE}\n')
    out = run(env, "scan").stdout
    assert "OLD_TOKEN" in out and "commented out" in out
    assert "FISH_API_KEY" in out and "fish" in out
    assert VALUE not in out
