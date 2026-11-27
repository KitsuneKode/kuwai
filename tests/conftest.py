"""Throwaway OpenPGP keys for the release tests, in a GNUPGHOME of their own (never yours)."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "bin/kuwai-verify"


class Keys:
    def __init__(self, home):
        self.home = home
        self.env = {**os.environ, "GNUPGHOME": home, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
        self.mine = self.make("Kuwai Release <release@example.invalid>")
        self.theirs = self.make("Someone Else <else@example.invalid>")

    def make(self, uid):
        subprocess.run(["gpg", "--batch", "--quiet", "--passphrase", "", "--quick-gen-key", uid, "ed25519", "sign", "never"],
                       env=self.env, check=True, capture_output=True)
        out = subprocess.run(["gpg", "--with-colons", "--fingerprint", uid], env=self.env, check=True,
                             capture_output=True, text=True).stdout
        return next(l.split(":")[9] for l in out.splitlines() if l.startswith("fpr:"))

    def asc(self, fpr):
        return subprocess.run(["gpg", "--export", "--armor", fpr], env=self.env, check=True, capture_output=True).stdout

    def signers(self, folder, *fprs):
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=True)
        for f in fprs:
            (folder / f"{f[-8:]}.asc").write_bytes(self.asc(f))
        return folder

    def git(self, repo, *args):
        return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args],
                              env=self.env, check=True, capture_output=True, text=True).stdout.strip()

    def digest(self, repo, rev):
        return subprocess.run([str(VERIFY), "manifest-rev", str(repo), rev], env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def release(self, repo, name, rev="HEAD", fpr=None, digest=None, line=True):
        fpr = fpr or self.mine
        msg = ["-m", f"kuwai {name[1:]}"]
        if line:
            msg += ["-m", f"kuwai-tree-sha256 {digest or self.digest(repo, rev)}"]
        self.git(repo, "-c", "gpg.format=openpgp", "tag", "-s", "-u", fpr, *msg, name, rev)


@pytest.fixture(scope="session")
def release_keys():
    home = tempfile.mkdtemp(prefix="kuwai-test-gnupg-")
    os.chmod(home, 0o700)
    try:
        yield Keys(home)
    finally:
        subprocess.run(["gpgconf", "--homedir", home, "--kill", "all"], capture_output=True)
        shutil.rmtree(home, ignore_errors=True)
