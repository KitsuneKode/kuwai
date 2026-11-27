"""kuwai-setup installs only a release signed by a key in release-signers, whose every file is the
signed one, and runs nothing from it before both are checked."""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "bin/kuwai-verify"
GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


def source_repo(tmp_path, keys, *signers):
    repo = tmp_path / "src"
    (repo / "bin/compat").mkdir(parents=True)
    shutil.copy2(VERIFY, repo / "bin/kuwai-verify")
    (repo / "install.sh").write_text('#!/bin/sh\necho "$@" > "$KUWAI_TEST_MARK"\n')
    (repo / "install.sh").chmod(0o755)
    (repo / "bin/compat/kuwai-verify").symlink_to("../kuwai-verify")
    (repo / "notes.txt").write_text("a release\n")
    keys.signers(repo / "release-signers", *(signers or [keys.mine]))
    keys.git(repo.parent, "init", "-q", "-b", "main", str(repo))
    keys.git(repo, "add", "-A")
    keys.git(repo, "commit", "-qm", "release")
    return repo


def verify(*args):
    return subprocess.run([str(VERIFY), *map(str, args)], capture_output=True, text=True, env=GIT_ENV, timeout=60)


def test_a_signed_release_verifies_and_is_staged_as_signed(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    signers = k.signers(tmp_path / "signers", k.mine)
    r = verify("tag", repo, "v1.0.0", "--signers", signers)
    assert r.returncode == 0, r.stderr
    info = json.loads(r.stdout)
    assert info["signer"] == k.mine and info["digest"] == k.digest(repo, "v1.0.0")
    stage = tmp_path / "cache/stage"
    r = verify("fetch", repo, "--signers", signers, "--into", stage)
    assert r.returncode == 0, r.stderr
    info = json.loads(r.stdout)
    assert info["name"] == "v1.0.0", "the newest release when none is named"
    assert verify("manifest", stage).stdout.strip() == info["digest"]
    assert (stage / "bin/compat/kuwai-verify").is_symlink()
    assert Path(info["tagFile"]).read_bytes().startswith(b"object ")
    assert oct(stage.stat().st_mode & 0o777) == "0o700"


def test_the_newest_release_is_picked_by_version_not_by_name(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.2.0")
    k.release(repo, "v1.10.0")
    r = verify("fetch", repo, "--signers", k.signers(tmp_path / "signers", k.mine), "--into", tmp_path / "stage")
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["name"] == "v1.10.0"


@pytest.mark.parametrize("case, why", [
    ("unsigned", "isn't signed"),
    ("plain", "plain tag"),
    ("unknown-key", "isn't a kuwai release key"),
    ("no-digest", "digest of its files"),
    ("wrong-digest", "aren't the ones its signature names"),
    ("renamed", "was made as"),
])
def test_a_tag_that_isnt_a_signed_release_is_refused(tmp_path, release_keys, case, why):
    k = release_keys
    repo = source_repo(tmp_path, k)
    signers = k.signers(tmp_path / "signers", k.mine)
    if case == "unsigned":
        k.git(repo, "tag", "-a", "-m", "kuwai 1.0.0", "v1.0.0")
    elif case == "plain":
        k.git(repo, "tag", "v1.0.0")
    elif case == "unknown-key":
        k.release(repo, "v1.0.0", fpr=k.theirs)
    elif case == "no-digest":
        k.release(repo, "v1.0.0", line=False)
    elif case == "wrong-digest":
        k.release(repo, "v1.0.0", digest="0" * 64)
    else:
        k.release(repo, "v0.9.0")
        k.git(repo, "update-ref", "refs/tags/v1.0.0", k.git(repo, "rev-parse", "refs/tags/v0.9.0"))
    r = verify("tag", repo, "v1.0.0", "--signers", signers)
    assert r.returncode == 1 and why in r.stderr, r.stderr
    stage = tmp_path / "stage"
    r = verify("fetch", repo, "v1.0.0", "--signers", signers, "--into", stage)
    assert r.returncode == 1 and why in r.stderr, r.stderr
    assert not (stage / "install.sh").exists(), "nothing is checked out before the tag checks out"


def test_no_key_in_release_signers_refuses_everything(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    empty = tmp_path / "empty"
    empty.mkdir()
    (empty / "README").write_text("no key yet\n")
    for r in (verify("tag", repo, "v1.0.0", "--signers", empty), verify("signers", empty),
              verify("fetch", repo, "--signers", empty, "--into", tmp_path / "stage")):
        assert r.returncode == 1 and "holds no key" in r.stderr
    assert not (tmp_path / "stage").exists()


def test_an_ssh_signed_tag_is_refused_plainly(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    key = tmp_path / "ssh"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
    k.git(repo, "-c", "gpg.format=ssh", "-c", f"user.signingkey={key}", "tag", "-s", "-m", "kuwai 1.0.0",
          "-m", f"kuwai-tree-sha256 {k.digest(repo, 'HEAD')}", "v1.0.0")
    r = verify("tag", repo, "v1.0.0", "--signers", k.signers(tmp_path / "signers", k.mine))
    assert r.returncode == 1 and "SSH key" in r.stderr


def test_a_name_with_a_newline_cant_stand_for_two_files(tmp_path, release_keys):
    full, short = tmp_path / "full", tmp_path / "short"
    full.mkdir()
    short.mkdir()
    (full / "a").write_bytes(b"one\n")
    (full / "b").write_bytes(b"two\n")
    (short / f"a\nf {hashlib.sha256(b'two' + chr(10).encode()).hexdigest()} b").write_bytes(b"one\n")
    good = verify("manifest", full)
    assert good.returncode == 0, good.stderr
    r = verify("manifest", short)
    assert r.returncode == 1 and "control character" in r.stderr, f"one file hashed as two: {r.stdout.strip()} == {good.stdout.strip()}"
    for name in ("tab\there", "esc\x1bhere", "del\x7fhere"):
        odd = tmp_path / f"odd-{len(name)}-{ord(name[3])}"
        odd.mkdir()
        (odd / name).write_text("x\n")
        r = verify("manifest", odd)
        assert r.returncode == 1 and "control character" in r.stderr, name
    k = release_keys
    repo = source_repo(tmp_path, k)
    (repo / "two\nlines").write_text("x\n")
    k.git(repo, "add", "-A")
    k.git(repo, "commit", "-qm", "odd")
    r = verify("manifest-rev", repo, "HEAD")
    assert r.returncode == 1 and "control character" in r.stderr


def setup_dir(tmp_path, keys, *fprs):
    d = tmp_path / "setup"
    (d / "bin").mkdir(parents=True)
    shutil.copy2(ROOT / "bin/kuwai-setup", d / "bin/kuwai-setup")
    shutil.copy2(VERIFY, d / "bin/kuwai-verify")
    if fprs:
        keys.signers(d / "release-signers", *fprs)
    else:
        (d / "release-signers").mkdir()
    return d


def run_setup(tmp_path, d, *args, sysroot=None):
    env = {**GIT_ENV, "HOME": str(tmp_path / "home"), "XDG_CACHE_HOME": str(tmp_path / "cache"),
           "KUWAI_TEST_MARK": str(tmp_path / "ran"), **({"KUWAI_SYSROOT": str(sysroot)} if sysroot else {})}
    return subprocess.run([str(d / "bin/kuwai-setup"), *map(str, args)], env=env, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=120)


def test_setup_runs_the_release_only_after_checking_it(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    r = run_setup(tmp_path, setup_dir(tmp_path, k, k.mine), "--source", repo, "--yes")
    assert r.returncode == 0, r.stderr
    assert f"Verified kuwai v1.0.0: signed by {k.mine}" in r.stdout
    assert (tmp_path / "ran").read_text().split() == ["--from-release", "--yes"]
    assert "sudo /usr/bin/python3 -I" in r.stdout and "--signer " + k.mine in r.stdout, "root's step is said, not skipped"


def test_setup_names_the_release_keys_to_root_only_the_first_time(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    lib = sysroot / "usr/local/lib/kuwai"
    r = run_setup(tmp_path, setup_dir(tmp_path, k, k.mine), "--source", repo, "--system", sysroot=sysroot)
    assert r.returncode == 0, r.stderr
    assert (lib / "signers/fingerprints").read_text().split() == [k.mine]
    k.git(repo, "commit", "-q", "--allow-empty", "-m", "next")
    k.release(repo, "v1.1.0")
    r = run_setup(tmp_path, setup_dir(tmp_path / "later", k, k.mine, k.theirs), "--source", repo, "--system", sysroot=sysroot)
    assert r.returncode == 0, "a second key in release-signers beside kuwai-setup broke root's step: " + r.stderr
    assert os.readlink(lib / "current") == "releases/v1.1.0"


def logged_verifier(d, log):
    real = d / "bin/kuwai-verify.real"
    shutil.move(d / "bin/kuwai-verify", real)
    (d / "bin/kuwai-verify").write_text(f"import runpy, sys\nopen({str(log)!r}, 'a').write(sys.argv[1] + chr(10))\n"
                                        f"sys.argv[0] = {str(real)!r}\nrunpy.run_path({str(real)!r}, run_name='__main__')\n")


def test_root_checks_a_release_with_its_own_verifier_once_it_has_one(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    d = setup_dir(tmp_path, k, k.mine)
    log = tmp_path / "verifier.log"
    logged_verifier(d, log)
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    lib = sysroot / "usr/local/lib/kuwai"
    r = run_setup(tmp_path, d, "--source", repo, "--system", sysroot=sysroot)
    assert r.returncode == 0, r.stderr
    assert log.read_text().split() == ["signers", "fetch", "install"], "the first time, this folder's is all there is"
    assert os.readlink(lib / "current") == "releases/v1.0.0"
    for name in ("v1.1.0", "v1.2.0"):
        k.git(repo, "commit", "-q", "--allow-empty", "-m", name)
        k.release(repo, name)
        log.write_text("")
        r = run_setup(tmp_path, d, "--source", repo, "--system", sysroot=sysroot)
        assert r.returncode == 0, r.stderr
        assert os.readlink(lib / "current") == f"releases/{name}"
        if name == "v1.1.0":
            assert "install" not in log.read_text().split(), "root's own verifier checked the new release"
            (lib / "releases/v1.1.0/bin/kuwai-verify").chmod(0o775)
        else:
            assert "install" in log.read_text().split(), "a verifier others can write isn't root's"


def test_setup_installs_nothing_after_root_refuses_the_release(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    k.git(repo, "commit", "-q", "--allow-empty", "-m", "next")
    k.release(repo, "v1.1.0")
    d = setup_dir(tmp_path, k, k.mine)
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    assert run_setup(tmp_path, d, "--source", repo, "--system", sysroot=sysroot).returncode == 0
    r = run_setup(tmp_path, d, "--source", repo, "--tag", "v1.0.0", sysroot=sysroot)
    assert r.returncode != 0 and "older than root's v1.1.0" in r.stderr
    assert "nothing was installed" in r.stderr
    assert not (tmp_path / "ran").exists(), "your half never installs a release root refused"


@pytest.mark.parametrize("signed_by", ["theirs", "nobody"])
def test_setup_runs_nothing_from_a_release_it_cant_check(tmp_path, release_keys, signed_by):
    k = release_keys
    repo = source_repo(tmp_path, k)
    if signed_by == "theirs":
        k.release(repo, "v1.0.0", fpr=k.theirs)
    else:
        k.git(repo, "tag", "-a", "-m", "kuwai 1.0.0", "v1.0.0")
    r = run_setup(tmp_path, setup_dir(tmp_path, k, k.mine), "--source", repo)
    assert r.returncode != 0 and "nothing was installed" in r.stderr
    assert not (tmp_path / "ran").exists(), "the release's install.sh never ran"
    assert list((tmp_path / "cache/kuwai/releases").iterdir()) == [], "its folder is gone"


def test_setup_refuses_without_a_release_key(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    r = run_setup(tmp_path, setup_dir(tmp_path, k), "--source", repo)
    assert r.returncode != 0 and "holds no key" in r.stderr
    assert not (tmp_path / "ran").exists()


def test_setup_verify_only_installs_nothing(tmp_path, release_keys):
    k = release_keys
    repo = source_repo(tmp_path, k)
    k.release(repo, "v1.0.0")
    r = run_setup(tmp_path, setup_dir(tmp_path, k, k.mine), "--source", repo, "--verify-only")
    assert r.returncode == 0, r.stderr
    assert "nothing was installed" in r.stdout and not (tmp_path / "ran").exists()


def test_setup_never_runs_as_root():
    text = (ROOT / "bin/kuwai-setup").read_text()
    assert '[ "$(id -u)" != 0 ] ||' in text
    assert text.index('"$VERIFY" fetch') < text.index('"$STAGE/install.sh"'), "the release runs only after fetch checked it"
