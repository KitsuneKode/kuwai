"""greeter/install --undo restores only what the root-owned receipt written at install lists.

Runs greeter/install from root's copy of a signed release under KUWAI_SYSROOT (a stand-in / owned
by the test user), with pacman and systemctl stood in for."""
import getpass
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "bin/kuwai-verify"
GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


@pytest.fixture
def greeter(tmp_path, release_keys):
    k = release_keys
    repo = tmp_path / "src"
    shutil.copytree(ROOT / "greeter", repo / "greeter")
    (repo / "shell").mkdir()
    (repo / "shell/greeter.qml").write_text("import QtQuick\nItem {}\n")
    for rel in ("bin/kuwai-verify", "system/release.sh"):
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, repo / rel)
    k.signers(repo / "release-signers", k.mine)
    k.git(tmp_path, "init", "-q", "-b", "main", str(repo))
    k.git(repo, "add", "-A")
    k.git(repo, "commit", "-qm", "release")
    k.release(repo, "v1.0.0")
    sysroot = tmp_path / "sys"
    sysroot.mkdir()
    env = {**GIT_ENV, "KUWAI_SYSROOT": str(sysroot)}
    stage = tmp_path / "stage"
    info = json.loads(subprocess.run([str(VERIFY), "fetch", str(repo), "--signers", str(repo / "release-signers"),
                                      "--into", str(stage)], env=env, check=True, capture_output=True, text=True).stdout)
    subprocess.run([str(VERIFY), "install", "--from", str(stage), "--tag-file", info["tagFile"], "--name", "v1.0.0",
                    "--digest", info["digest"], "--signer", k.mine], env=env, check=True, capture_output=True)
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    log = tmp_path / "systemctl.log"
    for name, body in {"pacman": "exit 0", "systemctl": f'echo "$*" >> {log}\nexit 0'}.items():
        (stubs / name).write_text(f"#!/bin/sh\n{body}\n")
        (stubs / name).chmod(0o755)
    etc = sysroot / "etc"
    (etc / "pam.d").mkdir(parents=True)
    (etc / "pam.d/greetd").write_text("old pam\n")
    (etc / "systemd/system/getty@tty1.service.d").mkdir(parents=True)
    (etc / "systemd/system/getty@tty1.service.d/override.conf").write_text("autologin\n")
    (etc / "systemd/system/display-manager.service").symlink_to("/usr/lib/systemd/system/sddm.service")
    home = tmp_path / "home"
    home.mkdir()
    run_env = {**env, "SUDO_USER": getpass.getuser(), "HOME": str(home), "PATH": f"{stubs}:{os.environ['PATH']}"}
    script = sysroot / "usr/local/lib/kuwai/current/greeter/install"

    def run(*args):
        return subprocess.run([str(script), *args], env=run_env, capture_output=True, text=True, timeout=120,
                              stdin=subprocess.DEVNULL)
    return run, sysroot, log


def test_install_writes_a_receipt_and_undo_follows_it(greeter):
    run, sysroot, log = greeter
    r = run("--yes")
    assert r.returncode == 0, r.stderr
    etc = sysroot / "etc"
    keep = sysroot / "var/lib/kuwai-greeter/original"
    receipt = keep / "receipt"
    assert receipt.stat().st_mode & 0o777 == 0o600 and keep.stat().st_mode & 0o777 == 0o700
    lines = [l.split("\t") for l in receipt.read_text().splitlines()]
    assert [l[:3] for l in lines] == [["restore", "/etc/pam.d/greetd", "pam-greetd"],
                                      ["remove", "/etc/greetd/config.toml"],
                                      ["restore", "/etc/systemd/system/getty@tty1.service.d/override.conf", "getty-tty1-override.conf"],
                                      ["display-manager", "sddm.service"]]
    assert "pam_keyinit" in (etc / "pam.d/greetd").read_text()
    assert 'command = "/var/lib/kuwai-greeter/compositor-start"' in (etc / "greetd/config.toml").read_text()
    assert not (etc / "systemd/system/getty@tty1.service.d/override.conf").exists()
    assert (sysroot / "var/lib/kuwai-greeter/code-revision").read_text().startswith("v1.0.0, root's checked copy")
    r = run("--yes")
    assert r.returncode == 0 and receipt.read_text().count("\n") == 4, "a second install keeps the first install's record"
    r = run("--undo")
    assert r.returncode == 0, r.stderr
    assert (etc / "pam.d/greetd").read_text() == "old pam\n"
    assert not (etc / "greetd/config.toml").exists()
    assert (etc / "systemd/system/getty@tty1.service.d/override.conf").read_text() == "autologin\n"
    assert "enable sddm.service" in log.read_text()


def test_undo_of_an_install_from_before_receipts_records_what_root_kept_first(greeter):
    run, sysroot, log = greeter
    assert run("--yes").returncode == 0
    keep = sysroot / "var/lib/kuwai-greeter/original"
    (keep / "receipt").unlink()
    r = run("--undo")
    assert r.returncode == 0, r.stderr
    assert "no record" in r.stderr
    etc = sysroot / "etc"
    assert (etc / "pam.d/greetd").read_text() == "old pam\n"
    assert not (etc / "greetd/config.toml").exists()
    assert (etc / "systemd/system/getty@tty1.service.d/override.conf").read_text() == "autologin\n"
    assert "enable sddm.service" in log.read_text()
    assert not keep.parent.exists()


@pytest.mark.parametrize("damage", ["missing-keep-writable", "missing-dest-writable", "missing-kept-writable",
                                    "missing-var-writable", "writable", "link"])
def test_undo_without_a_trustworthy_receipt_restores_nothing(greeter, damage):
    run, sysroot, log = greeter
    assert run("--yes").returncode == 0
    keep = sysroot / "var/lib/kuwai-greeter/original"
    receipt = keep / "receipt"
    if damage.startswith("missing"):
        receipt.unlink()
        {"keep": keep, "dest": keep.parent, "kept": keep / "pam-greetd", "var": sysroot / "var"}[damage.split("-")[1]].chmod(0o777)
    elif damage == "writable":
        receipt.chmod(0o666)
    else:
        moved = keep / "elsewhere"
        receipt.rename(moved)
        receipt.symlink_to(moved)
    pam = (sysroot / "etc/pam.d/greetd").read_text()
    r = run("--undo")
    assert r.returncode == 1 and "nothing is restored" in r.stderr
    assert (sysroot / "etc/pam.d/greetd").read_text() == pam, "the kept copy beside it is not used without a receipt"
    assert "disable greetd" not in log.read_text()


@pytest.mark.parametrize("damage", ["kept-writable", "kept-link", "marker-link", "dm-writable", "keep-writable",
                                    "dest-writable", "var-writable"])
def test_an_install_over_kept_copies_nobody_vouched_for_records_nothing(greeter, damage):
    run, sysroot, log = greeter
    assert run("--yes").returncode == 0
    keep = sysroot / "var/lib/kuwai-greeter/original"
    (keep / "receipt").unlink()
    planted = sysroot / "planted"
    planted.write_text("planted\n")
    if damage == "kept-writable":
        (keep / "pam-greetd").write_text("planted pam\n")
        (keep / "pam-greetd").chmod(0o666)
    elif damage == "kept-link":
        (keep / "getty-tty1-override.conf").unlink()
        (keep / "getty-tty1-override.conf").symlink_to(planted)
    elif damage == "marker-link":
        (keep / "greetd-config.toml.absent").unlink()
        (keep / "greetd-config.toml.absent").symlink_to(planted)
    elif damage == "dm-writable":
        (keep / "display-manager").chmod(0o666)
    else:
        {"keep": keep, "dest": keep.parent, "var": sysroot / "var"}[damage.split("-")[0]].chmod(0o777)
    pam = (sysroot / "etc/pam.d/greetd").read_text()
    r = run("--yes")
    assert r.returncode == 1 and "isn't root's alone" in r.stderr, r.stderr
    assert not (keep / "receipt").exists() and not (keep / "receipt").is_symlink()
    assert (sysroot / "etc/pam.d/greetd").read_text() == pam
    if damage == "keep-writable":
        assert keep.stat().st_mode & 0o777 == 0o777, "the folder is not taken over before it is checked"


def test_an_install_over_kept_copies_only_root_kept_records_them(greeter):
    run, sysroot, log = greeter
    assert run("--yes").returncode == 0
    keep = sysroot / "var/lib/kuwai-greeter/original"
    first = (keep / "receipt").read_text()
    (keep / "receipt").unlink()
    r = run("--yes")
    assert r.returncode == 0, r.stderr
    assert (keep / "receipt").read_text() == first


def test_undo_restores_only_paths_the_install_replaces_from_copies_it_recorded(greeter):
    run, sysroot, log = greeter
    assert run("--yes").returncode == 0
    keep = sysroot / "var/lib/kuwai-greeter/original"
    receipt = keep / "receipt"
    good = receipt.read_text()
    sum_ = good.split("\n")[0].split("\t")[3]
    receipt.write_text(good + f"restore\t/etc/shadow\tpam-greetd\t{sum_}\n"
                       + "restore\t/etc/greetd/config.toml\tpam-greetd\t" + sum_ + "\nrun\t/bin/sh\n")
    receipt.chmod(0o600)
    (keep / "getty-tty1-override.conf").write_text("changed afterwards\n")
    r = run("--undo")
    assert r.returncode == 0, r.stderr
    assert not (sysroot / "etc/shadow").exists()
    assert (sysroot / "etc/pam.d/greetd").read_text() == "old pam\n"
    assert not (sysroot / "etc/systemd/system/getty@tty1.service.d/override.conf").exists(), "a kept copy that changed is not used"
    assert "the install never replaces it" in r.stderr and "isn't the one the install recorded" in r.stderr
    assert "not where the install kept it" in r.stderr


def test_the_login_screen_installs_only_from_roots_copy(tmp_path):
    env = {**GIT_ENV, "KUWAI_SYSROOT": str(tmp_path), "SUDO_USER": getpass.getuser()}
    r = subprocess.run([str(ROOT / "greeter/install"), "--yes"], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 1 and "doesn't install from it" in r.stderr
    assert not (tmp_path / "var").exists()
    r = subprocess.run([str(ROOT / "greeter/install"), "--dirty"], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 2 and "--trust-clone" in r.stderr
