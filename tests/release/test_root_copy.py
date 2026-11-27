"""Root installs only from its own copy of a signed release, checked by root again: against the
fingerprints root keeps, file by file, after the copy is root's. Run under KUWAI_SYSROOT, a
stand-in / owned by the test user, who stands in for root."""
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "bin/kuwai-verify"
GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
PIECES = ("bin/kuwai-verify", "bin/kuwai-session", "bin/kuwai-update-root", "system/session", "system/release.sh",
          "system/kuwai.desktop")


def make_repo(path, keys, signers):
    for rel in PIECES:
        (path / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, path / rel)
    (path / "shell-auth").mkdir()
    (path / "shell-auth/shell.qml").write_text("import QtQuick\nItem {}\n")
    (path / "bin/compat").mkdir()
    (path / "bin/compat/kuwai-session").symlink_to("../kuwai-session")
    keys.signers(path / "release-signers", *signers)
    keys.git(path.parent, "init", "-q", "-b", "main", str(path))
    keys.git(path, "add", "-A")
    keys.git(path, "commit", "-qm", "release")
    return path


def verify(*args, sysroot=None):
    env = {**GIT_ENV, **({"KUWAI_SYSROOT": str(sysroot)} if sysroot else {})}
    return subprocess.run([str(VERIFY), *map(str, args)], capture_output=True, text=True, env=env, timeout=60)


def fetch(keys, repo, name, into, *fprs):
    r = verify("fetch", repo, name, "--signers", keys.signers(into.parent / f"signers-{name}", *(fprs or [keys.mine])),
               "--into", into)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def install(sysroot, stage, info, *more, signers=None, tag_file=None):
    sig = [a for f in (signers if signers is not None else []) for a in ("--signer", f)]
    return verify("install", "--from", stage, "--tag-file", tag_file or info["tagFile"], "--name", info["name"],
                  "--digest", info["digest"], *sig, *more, sysroot=sysroot)


@pytest.fixture
def world(tmp_path, release_keys):
    k = release_keys
    repo = make_repo(tmp_path / "src", k, [k.mine])
    k.release(repo, "v1.0.0")
    stage = tmp_path / "cache/v1.0.0"
    info = fetch(k, repo, "v1.0.0", stage)
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    lib = sysroot / "usr/local/lib/kuwai"
    return k, repo, stage, info, sysroot, lib


def nothing_installed(lib):
    return not os.path.lexists(lib / "current") and not list(lib.glob("releases/v*"))


def test_root_installs_its_own_checked_copy(world):
    k, repo, stage, info, sysroot, lib = world
    r = install(sysroot, stage, info, signers=[k.mine])
    assert r.returncode == 0, r.stderr
    assert os.readlink(lib / "current") == "releases/v1.0.0"
    assert (lib / "signers/fingerprints").read_text().split() == [k.mine]
    assert verify("manifest", lib / "releases/v1.0.0").stdout.strip() == info["digest"]
    assert (lib / "releases/v1.0.0.tag").read_bytes() == Path(info["tagFile"]).read_bytes()
    assert not (lib / "releases/v1.0.0/.git").exists(), "root keeps the tree, not the checkout"
    assert not list(lib.glob(".incoming-*"))
    r = verify("check", lib / "current", sysroot=sysroot)
    assert r.returncode == 0 and k.mine in r.stdout


@pytest.mark.parametrize("change", ["edit", "add", "link-out"])
def test_a_copy_changed_after_it_was_checked_is_refused(world, change):
    k, repo, stage, info, sysroot, lib = world
    if change == "edit":
        (stage / "system/session").write_text("#!/bin/sh\nid > /tmp/owned\n")
    elif change == "add":
        (stage / "system/extra").write_text("planted\n")
    else:
        (stage / "bin/outside").symlink_to("/etc/shadow")
    r = install(sysroot, stage, info, signers=[k.mine])
    assert r.returncode == 1, r.stdout
    assert ("isn't the tree" in r.stderr) if change != "link-out" else ("points outside" in r.stderr)
    assert nothing_installed(lib)
    assert not list(lib.glob(".incoming-*")), "what root copied is gone again"


def test_a_tag_signed_by_a_key_root_doesnt_trust_is_refused(world, tmp_path):
    k, repo, stage, info, sysroot, lib = world
    twin = make_repo(tmp_path / "twin", k, [k.mine, k.theirs])
    k.release(twin, "v1.0.0", fpr=k.theirs)
    raw = tmp_path / "theirs.tag"
    raw.write_bytes(subprocess.run(["git", "-C", str(twin), "cat-file", "tag", "v1.0.0"], capture_output=True,
                                   env=GIT_ENV, check=True).stdout)
    digest = k.digest(twin, "v1.0.0")
    r = verify("install", "--from", twin, "--tag-file", raw, "--name", "v1.0.0", "--digest", digest,
               "--signer", k.mine, sysroot=sysroot)
    assert r.returncode == 1 and "isn't a kuwai release key" in r.stderr, "the twin lists theirs, but root was told only mine"
    assert nothing_installed(lib)
    r = install(sysroot, stage, info, signers=[k.mine], tag_file=raw)
    assert r.returncode == 1 and nothing_installed(lib)


def test_root_needs_a_fingerprint_the_first_time_and_takes_no_new_one_later(world, tmp_path):
    k, repo, stage, info, sysroot, lib = world
    r = install(sysroot, stage, info)
    assert r.returncode == 1 and "--signer" in r.stderr and nothing_installed(lib)
    assert install(sysroot, stage, info, signers=[k.mine]).returncode == 0
    k.git(repo, "commit", "-q", "--allow-empty", "-m", "next")
    k.release(repo, "v1.1.0")
    nxt = fetch(k, repo, "v1.1.0", tmp_path / "cache/v1.1.0")
    r = install(sysroot, tmp_path / "cache/v1.1.0", nxt, signers=[k.theirs])
    assert r.returncode == 1 and "signed by one it already trusts" in r.stderr
    r = install(sysroot, tmp_path / "cache/v1.1.0", nxt)
    assert r.returncode == 0, r.stderr
    assert os.readlink(lib / "current") == "releases/v1.1.0"
    r = install(sysroot, stage, info)
    assert r.returncode == 1 and "older than root's v1.1.0" in r.stderr
    assert os.readlink(lib / "current") == "releases/v1.1.0"


def test_a_copy_missing_files_behind_a_name_with_a_newline_is_refused(tmp_path, release_keys):
    k = release_keys
    repo = make_repo(tmp_path / "src", k, [k.mine])
    (repo / "a").write_bytes(b"one\n")
    (repo / "b").write_bytes(b"two\n")
    k.git(repo, "add", "-A")
    k.git(repo, "commit", "-qm", "two files")
    k.release(repo, "v1.0.0")
    stage = tmp_path / "cache/v1.0.0"
    info = fetch(k, repo, "v1.0.0", stage)
    (stage / "a").unlink()
    (stage / "b").unlink()
    (stage / f"a\nf {hashlib.sha256(b'two' + chr(10).encode()).hexdigest()} b").write_bytes(b"one\n")
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    lib = sysroot / "usr/local/lib/kuwai"
    r = install(sysroot, stage, info, signers=[k.mine])
    assert r.returncode == 1 and "control character" in r.stderr, "root took a copy missing a and b"
    assert nothing_installed(lib)


def test_root_takes_its_keys_from_each_release_a_key_it_trusts_signed(world, tmp_path):
    k, repo, stage, info, sysroot, lib = world
    def fprs():
        return sorted((lib / "signers/fingerprints").read_text().split())

    assert install(sysroot, stage, info, signers=[k.mine]).returncode == 0

    def cut(name, signer, *listed):
        shutil.rmtree(repo / "release-signers")
        k.signers(repo / "release-signers", *listed)
        k.git(repo, "add", "-A")
        k.git(repo, "commit", "-q", "--allow-empty", "-m", name)
        k.release(repo, name, fpr=signer)
        return tmp_path / f"cache/{name}", fetch(k, repo, name, tmp_path / f"cache/{name}", k.mine, k.theirs)

    added = cut("v1.1.0", k.mine, k.mine, k.theirs)
    r = install(sysroot, *added)
    assert r.returncode == 0, r.stderr
    assert fprs() == sorted([k.mine, k.theirs]), "a release signed by a trusted key adds the key it lists"
    rotated = cut("v1.2.0", k.theirs, k.theirs)
    r = install(sysroot, *rotated)
    assert r.returncode == 0, r.stderr
    assert fprs() == [k.theirs], "and drops the one it no longer lists"
    assert verify("check", lib / "current", sysroot=sysroot).returncode == 0
    assert verify("place", "update-helper", sysroot=sysroot).returncode == 0
    removed = cut("v1.3.0", k.mine, k.mine, k.theirs)
    r = install(sysroot, *removed)
    assert r.returncode == 1 and "isn't a kuwai release key" in r.stderr, "a removed key signs nothing root takes"
    assert os.readlink(lib / "current") == "releases/v1.2.0" and fprs() == [k.theirs]
    r = install(sysroot, *removed, signers=[k.mine])
    assert r.returncode == 1 and fprs() == [k.theirs], "nor can it be named back in"


def test_root_reads_a_keys_fingerprint_as_gpg_does(release_keys, tmp_path):
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("kuwai_verify", str(VERIFY))
    spec = importlib.util.spec_from_loader("kuwai_verify", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    d = release_keys.signers(tmp_path / "both", release_keys.mine, release_keys.theirs)
    assert mod.key_fingerprints(mod.dearmor(mod.asc_files([d]))) == {release_keys.mine, release_keys.theirs}
    with pytest.raises(mod.Refused):
        mod.key_fingerprints(b"\x99\x00\x40" + b"\x04" * 8)


@pytest.mark.parametrize("change", ["edit", "add", "writable"])
def test_roots_copy_is_checked_again_before_use(world, change):
    k, repo, stage, info, sysroot, lib = world
    assert install(sysroot, stage, info, signers=[k.mine]).returncode == 0
    rel = lib / "releases/v1.0.0"
    if change == "edit":
        (rel / "shell-auth/shell.qml").write_text("import QtQuick\nItem { Component.onCompleted: steal() }\n")
    elif change == "add":
        (rel / "shell-auth/extra.qml").write_text("Item {}\n")
    else:
        (rel / "shell-auth").chmod(0o777)
    r = verify("check", rel, sysroot=sysroot)
    assert r.returncode == 1, r.stdout
    r = verify("place", "auth-prompt", sysroot=sysroot)
    assert r.returncode == 1
    assert not (sysroot / "usr/local/share/kuwai/shell-auth").exists(), "nothing placed from a changed copy"


def test_place_puts_pieces_of_the_checked_release_in_place(world):
    k, repo, stage, info, sysroot, lib = world
    assert install(sysroot, stage, info, signers=[k.mine]).returncode == 0
    r = verify("place", "update-helper", sysroot=sysroot)
    assert r.returncode == 0, r.stderr
    assert (lib / "kuwai-update-root").read_bytes() == (ROOT / "bin/kuwai-update-root").read_bytes()
    assert (lib / "kuwai-update-root").stat().st_mode & 0o777 == 0o755
    assert verify("place", "auth-prompt", sysroot=sysroot).returncode == 0
    assert (sysroot / "usr/local/share/kuwai/shell-auth/shell.qml").read_text() == "import QtQuick\nItem {}\n"
    assert verify("place", "auth-prompt", sysroot=sysroot).returncode == 0, "placing again replaces it"
    assert verify("place", "anything", sysroot=sysroot).returncode == 1


def test_without_root_or_a_stand_in_root_nothing_happens(world):
    k, repo, stage, info, sysroot, lib = world
    r = install(None, stage, info, signers=[k.mine])
    assert r.returncode == 1 and "runs as root" in r.stderr


def session(script, sysroot, *args):
    return subprocess.run([str(script), *args], capture_output=True, text=True, timeout=60,
                          env={**GIT_ENV, "KUWAI_SYSROOT": str(sysroot)})


def test_the_login_entry_installs_from_roots_copy_only(world):
    k, repo, stage, info, sysroot, lib = world
    launcher = sysroot / "usr/local/bin/kuwai-session"
    r = session(ROOT / "system/session", sysroot)
    assert r.returncode == 1 and "doesn't install from it" in r.stderr and "--trust-clone" in r.stderr
    assert not launcher.exists()
    assert install(sysroot, stage, info, signers=[k.mine]).returncode == 0
    r = session(lib / "current/system/session", sysroot)
    assert r.returncode == 0, r.stderr
    assert launcher.read_bytes() == (ROOT / "bin/kuwai-session").read_bytes()
    assert session(lib / "current/system/session", sysroot, "--undo").returncode == 0
    assert not launcher.exists()
    (lib / "releases/v1.0.0/bin/kuwai-session").write_text("#!/bin/sh\nid\n")
    r = session(lib / "current/system/session", sysroot)
    assert r.returncode == 1 and "isn't the signed release" in r.stderr
    assert not launcher.exists(), "a changed copy installs nothing"


def test_trust_clone_says_plainly_what_it_trusts(tmp_path):
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    r = session(ROOT / "system/session", sysroot, "--trust-clone")
    assert r.returncode == 0, r.stderr
    assert "trusts every file in it; nothing was checked" in r.stderr
    assert (sysroot / "usr/local/bin/kuwai-session").exists()


def test_root_scripts_refuse_a_clone_before_doing_anything():
    for script in ("system/session", "system/install", "greeter/install"):
        text = (ROOT / script).read_text()
        guard = text.index("from_release ")
        first_change = min(i for i in (text.find(w, guard - 1) for w in ("install -", "rm -", "systemctl ", "rsync ")) if i >= 0)
        assert guard < first_change, f"{script} changes something before it checks where it runs from"


def test_every_hint_to_run_a_root_script_names_one_root_will_run():
    hint = re.compile(r"sudo[^\n]{0,80}(?:system/install|greeter/install|system/session)")
    ok = ("$LIB/current", "$KUWAI_LIB/current", "/usr/local/lib/kuwai/current", "--trust-clone")
    stale = []
    for top in ("bin", "shell", "greeter", "system", "lib", "install.sh"):
        for path in sorted((ROOT / top).rglob("*")) if (ROOT / top).is_dir() else [ROOT / top]:
            if not path.is_file() or path.suffix in (".png", ".jpg", ".ttf", ".otf"):
                continue
            for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
                if hint.search(line) and not any(o in line for o in ok):
                    stale.append(f"{path.relative_to(ROOT)}:{n}")
    assert stale == [], "these point at a copy root refuses to install from"
