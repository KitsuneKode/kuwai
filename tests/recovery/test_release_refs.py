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
        p.write_text("#!/bin/sh\nexit 0\n")
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
