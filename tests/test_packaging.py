"""The AUR package depends on exactly what install.sh checks for, and sets up per user."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "packaging/aur/kuwai"


def listed(name):
    return {l.split(":", 1)[1].split("(")[0].strip() for l in (ROOT / "packages" / name).read_text().splitlines()
            if l.strip() and not l.startswith("#")}


def array(text, name):
    m = re.search(rf"^{name}=\((.*?)^\)", text, re.S | re.M)
    return {re.sub(r":.*", "", x.strip().strip("'\"")) for x in m.group(1).splitlines() if x.strip()}


def test_depends_follow_the_package_lists():
    pkgbuild = (PKG / "PKGBUILD").read_text()
    assert listed("core.txt") | listed("fonts.txt") <= array(pkgbuild, "depends")
    assert listed("optional.txt") == array(pkgbuild, "optdepends")


def test_srcinfo_is_current():
    out = subprocess.run(["bash", "-c", f"source {PKG}/PKGBUILD; echo $pkgver"], capture_output=True, text=True).stdout.strip()
    assert f"pkgver = {out}" in (PKG / ".SRCINFO").read_text()
    assert (ROOT / "VERSION").read_text().strip() >= out


def test_setup_refuses_root_and_pins_the_release():
    setup = (PKG / "kuwai-setup").read_text()
    assert 'id -u)" = 0' in setup and '"v$version^{commit}"' in setup and "@VERSION@" in setup
