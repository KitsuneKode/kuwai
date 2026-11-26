"""kuwai promote / rollback keep a usable recovery ref in disposable repos."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CTL = ROOT / "bin/kuwai-ctl"


GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True, env=GIT_ENV).stdout.strip()


def make_world(tmp_path):
    home = tmp_path / "home"
    data = home / ".local/share"
    state = home / ".local/state"
    stubs = tmp_path / "stubs"
    for d in (data, state, stubs):
        d.mkdir(parents=True)
    for name, body in {"qs": "echo '[]'", "hyprctl": "exit 0", "systemctl": "exit 0"}.items():
        p = stubs / name
        p.write_text(f"#!/bin/sh\n{body}\n")
        p.chmod(0o755)
    dev = home / "Projects/rice"
    (dev / "hypr").mkdir(parents=True)
    (dev / "bin").mkdir()
    (dev / "hypr/init.lua").write_text("return {}\n")
    for tool in ("kuwai-check", "kuwai-backup", "kuwai-loadtest", "kuwai-migrations", "kuwai-shell"):
        p = dev / "bin" / tool
        p.write_text(f'#!/bin/sh\n[ -n "$KUWAI_TEST_CALLS" ] && echo "{tool} $*" >> "$KUWAI_TEST_CALLS"\nexit 0\n')
        p.chmod(0o755)
    git(dev, "init", "-q", "-b", "main")
    git(dev, "config", "user.email", "t@example.invalid")
    git(dev, "config", "user.name", "t")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "A")
    a = git(dev, "rev-parse", "HEAD")
    stable = data / "kuwai"
    git(dev, "worktree", "add", "-q", "-b", "stable", str(stable), a)
    (dev / "hypr/extra.lua").write_text("return 1\n")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "B")
    b = git(dev, "rev-parse", "HEAD")
    env = {
        "PATH": f"{stubs}:{os.environ.get('PATH', '/usr/bin:/bin')}",
        "HOME": str(home),
        "XDG_DATA_HOME": str(data),
        "XDG_STATE_HOME": str(state),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
    }
    return env, dev, stable, a, b


def ctl(env, *args):
    return subprocess.run([str(CTL), *args], env=env, capture_output=True, text=True, timeout=60)


def prev_of(stable):
    return git(stable, "rev-parse", "refs/heads/stable-prev")


def test_promote_then_rollback_round_trip(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    r = ctl(env, "promote")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b
    assert prev_of(stable) == a
    r = ctl(env, "rollback")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == a
    assert prev_of(stable) == b


def test_promoting_the_same_commit_twice_keeps_the_rollback_target(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    assert ctl(env, "promote").returncode == 0
    r = ctl(env, "promote")
    assert r.returncode == 0, r.stderr
    assert "already" in (r.stdout + r.stderr)
    assert git(stable, "rev-parse", "HEAD") == b
    assert prev_of(stable) == a, "a no-op promote must not overwrite stable-prev"


def test_failed_fast_forward_leaves_the_rollback_target_alone(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    assert ctl(env, "promote").returncode == 0
    git(dev, "reset", "-q", "--hard", a)
    (dev / "hypr/other.lua").write_text("return 2\n")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "C diverges from B")
    r = ctl(env, "promote")
    assert r.returncode != 0
    assert git(stable, "rev-parse", "HEAD") == b
    assert prev_of(stable) == a


def test_rollback_reports_failure_when_git_refuses_the_reset(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    assert ctl(env, "promote").returncode == 0
    gitdir = Path(git(stable, "rev-parse", "--absolute-git-dir"))
    (gitdir / "index.lock").write_text("")
    try:
        r = ctl(env, "rollback")
    finally:
        (gitdir / "index.lock").unlink()
    assert r.returncode != 0, r.stdout
    assert "rolled back" not in r.stdout
    assert git(stable, "rev-parse", "HEAD") == b
    assert prev_of(stable) == a, "a refused reset must not move stable-prev"


def with_origin(tmp_path, dev):
    origin = tmp_path / "origin.git"
    git(tmp_path, "init", "-q", "--bare", str(origin))
    git(dev, "remote", "add", "origin", str(origin))
    git(dev, "push", "-q", "origin", "main")
    return origin


def test_update_self_follows_the_newest_release_tag(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    git(dev, "tag", "v0.1.0", a)
    git(dev, "tag", "v0.2.0", b)
    git(dev, "push", "-q", "origin", "--tags")
    r = ctl(env, "update-self")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b
    assert prev_of(stable) == a
    r = ctl(env, "update-self")
    assert r.returncode == 0, r.stderr
    assert "already up to date" in r.stdout


def test_update_self_never_moves_stable_back_to_an_older_tag(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    git(stable, "merge", "--ff-only", "-q", b)
    git(dev, "tag", "v0.1.0", a)
    git(dev, "push", "-q", "origin", "--tags")
    r = ctl(env, "update-self")
    assert r.returncode == 0, r.stderr
    assert "already up to date" in r.stdout
    assert git(stable, "rev-parse", "HEAD") == b


def test_version_names_the_release_and_the_stable_commit(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    git(dev, "tag", "v0.1.0", a)
    r = ctl(env, "version")
    assert r.returncode == 0, r.stderr
    version = (ROOT / "VERSION").read_text().strip()
    assert r.stdout.splitlines()[0] == f"kuwai {version}"
    assert "stable  v0.1.0" in r.stdout


def test_rollback_undoes_the_migrations_the_older_release_lacks(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    runner = dev / "bin/kuwai-migrations"
    runner.write_text('#!/bin/sh\n[ "$1" = --undo ] && echo "$@" >> "$XDG_STATE_HOME/undo-args"\nexit 0\n')
    (dev / "migrations").mkdir()
    (dev / "migrations/0009-new.sh").write_text("# what: x\n# touches: $XDG_STATE_HOME/kuwai/x\n")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "C")
    assert ctl(env, "promote").returncode == 0
    done = Path(env["XDG_STATE_HOME"]) / "kuwai/migrations/done"
    done.mkdir(parents=True)
    (done / "0009-new.sh").write_text("now\n")
    r = ctl(env, "rollback")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == a
    assert (Path(env["XDG_STATE_HOME"]) / "undo-args").read_text().split() == ["--undo", "0009-new.sh"]


def test_promote_and_rollback_with_a_standalone_stable_clone(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    git(dev, "worktree", "remove", "--force", str(stable))
    subprocess.run(["git", "clone", "-q", "--branch", "stable", str(dev), str(stable)], check=True, env=GIT_ENV)
    state = Path(env["XDG_STATE_HOME"]) / "kuwai"
    state.mkdir(parents=True, exist_ok=True)
    moved = tmp_path / "elsewhere"
    dev.rename(moved)
    (state / "dev-root").write_text(f"{moved}\n")
    r = ctl(env, "promote")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b
    r = ctl(env, "rollback")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == a


def test_update_self_needs_a_release_or_an_explicit_ref(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    r = ctl(env, "update-self")
    assert r.returncode != 0 and "no release tag" in r.stderr
    assert git(stable, "rev-parse", "HEAD") == a, "no silent branch fallback"
    r = ctl({**env, "KUWAI_UPDATE_REF": "origin/main"}, "update-self")
    assert r.returncode != 0 and "ignored now" in r.stderr, "an ambient variable no longer moves stable"
    assert git(stable, "rev-parse", "HEAD") == a
    r = ctl(env, "update-self", "--ref", "origin/main")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b


def test_update_self_ignores_local_only_tags_and_refuses_a_moved_release(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    origin = with_origin(tmp_path, dev)
    git(dev, "tag", "v0.1.0", a)
    git(dev, "push", "-q", "origin", "--tags")
    git(dev, "tag", "v9.0.0", b)
    r = ctl(env, "update-self")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == a, "a tag origin doesn't have is never picked"
    git(dev, "tag", "-f", "-a", "-m", "moved", "v0.1.0", b)
    git(dev, "push", "-q", "-f", "origin", "v0.1.0")
    r = ctl(env, "update-self")
    assert r.returncode != 0 and "points somewhere else" in r.stderr
    assert git(stable, "rev-parse", "HEAD") == a


def test_update_self_refuses_an_unsigned_release_once_signers_are_listed(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    conf = Path(env["HOME"]) / ".config/kuwai"
    conf.mkdir(parents=True)
    (conf / "release-signers").write_text("0123456789ABCDEF0123456789ABCDEF01234567\n")
    git(dev, "tag", "-a", "-m", "r", "v0.2.0", b)
    git(dev, "push", "-q", "origin", "--tags")
    r = ctl(env, "update-self")
    assert r.returncode != 0 and "isn't signed" in r.stderr
    assert git(stable, "rev-parse", "HEAD") == a


def ssh_key(tmp_path, name):
    key = tmp_path / name
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", name, "-f", str(key)], check=True)
    return key


def test_update_self_takes_a_release_signed_by_a_listed_ssh_key_and_no_other(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    mine, theirs = ssh_key(tmp_path, "mine"), ssh_key(tmp_path, "theirs")
    conf = Path(env["HOME"]) / ".config/kuwai"
    conf.mkdir(parents=True)
    (conf / "release-signers").write_text("# releases\n" + Path(f"{theirs}.pub").read_text())
    git(dev, "-c", "gpg.format=ssh", "-c", f"user.signingkey={mine}", "tag", "-s", "-m", "r", "v0.2.0", b)
    git(dev, "push", "-q", "origin", "--tags")
    r = ctl(env, "update-self")
    assert r.returncode != 0 and "isn't signed" in r.stderr, "a key that isn't listed is refused"
    assert git(stable, "rev-parse", "HEAD") == a
    (conf / "release-signers").write_text(Path(f"{mine}.pub").read_text())
    r = ctl(env, "update-self")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b


def test_an_unsigned_release_is_refused_when_only_ssh_keys_are_listed(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    with_origin(tmp_path, dev)
    conf = Path(env["HOME"]) / ".config/kuwai"
    conf.mkdir(parents=True)
    (conf / "release-signers").write_text(Path(f"{ssh_key(tmp_path, 'mine')}.pub").read_text())
    git(dev, "tag", "-a", "-m", "r", "v0.2.0", b)
    git(dev, "push", "-q", "origin", "--tags")
    r = ctl(env, "update-self")
    assert r.returncode != 0 and "isn't signed" in r.stderr
    assert git(stable, "rev-parse", "HEAD") == a


def test_kuwai_release_signs_with_the_listed_key_and_nothing_else(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    mine, other = ssh_key(tmp_path, "mine"), ssh_key(tmp_path, "other")
    (dev / "release-signers").write_text("# releases\n" + Path(f"{mine}.pub").read_text())
    git(dev, "add", "release-signers")
    git(dev, "commit", "-qm", "signers")
    r = ctl({**env, "KUWAI_RELEASE_KEY": str(other)}, "release", "v1.0.0")
    assert r.returncode != 0 and "isn't in release-signers" in r.stderr
    assert git(dev, "tag", "-l", "v1.0.0") == "", "no tag from a key that isn't listed"
    assert ctl({**env, "KUWAI_RELEASE_KEY": str(mine)}, "release", "1.0").returncode == 2
    r = ctl({**env, "KUWAI_RELEASE_KEY": str(mine)}, "release", "v1.0.0")
    assert r.returncode == 0, r.stderr
    assert "-----BEGIN SSH SIGNATURE-----" in git(dev, "cat-file", "tag", "v1.0.0")
    assert git(dev, "rev-parse", "v1.0.0^{commit}") == git(dev, "rev-parse", "HEAD")


def test_a_second_rollback_moves_forward_and_runs_the_migrations(tmp_path):
    env, dev, stable, a, b = make_world(tmp_path)
    calls = tmp_path / "calls"
    env = {**env, "KUWAI_TEST_CALLS": str(calls)}
    assert ctl(env, "promote").returncode == 0
    calls.write_text("")
    assert ctl(env, "rollback").returncode == 0
    assert git(stable, "rev-parse", "HEAD") == a
    assert "kuwai-migrations \n" not in calls.read_text(), "going back undoes; it doesn't run them forward"
    calls.write_text("")
    r = ctl(env, "rollback")
    assert r.returncode == 0, r.stderr
    assert git(stable, "rev-parse", "HEAD") == b
    assert "kuwai-migrations \n" in calls.read_text(), "going forward again runs that release's migrations"
