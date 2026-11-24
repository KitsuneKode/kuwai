#!/usr/bin/env python3
"""install.sh's memory of what was there before kuwai.

The first time the installer is about to replace a path, `remember` records
how it was: absent, a file (its bytes are kept) or a link (its target). Later
installs never overwrite that record, so uninstall goes back to the desktop
you had before the first install, not to the previous kuwai. After each
install `installed` notes what kuwai put there; uninstall only puts the
original back where the path still holds exactly that, and reports anything
you changed since as a conflict, leaving it alone.

Unit enablement is remembered the same way (the first time only).

State, in <state>/original/: manifest.json and files/<n> (saved contents).
Older installers kept timestamped copies in <state>/backup/<time>/ with a
MANIFEST of paths relative to $HOME; when there's no record yet those seed it,
the oldest copy of each path winning, since that's the closest to the
original.

  kuwai_install.py --state DIR remember PATH
  kuwai_install.py --state DIR installed PATH
  kuwai_install.py --state DIR edited PATH     exit 0: changed since kuwai installed it
  kuwai_install.py --state DIR manages PATH    exit 0: recorded
  kuwai_install.py --state DIR unit NAME
  kuwai_install.py --state DIR restore [--dry-run]
  kuwai_install.py --state DIR restore-one PATH
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


def fingerprint(p):
    """How a path is now: ['absent'] / ['link', target] / ['file', sha256] / ['other']."""
    p = Path(p)
    if p.is_symlink():
        return ["link", os.readlink(p)]
    if not p.exists():
        return ["absent"]
    if p.is_file():
        return ["file", hashlib.sha256(p.read_bytes()).hexdigest()]
    return ["other"]


class Store:
    def __init__(self, state):
        self.state = Path(state)
        self.dir = self.state / "original"
        self.file = self.dir / "manifest.json"
        try:
            self.data = json.loads(self.file.read_text())
        except (OSError, ValueError):
            root = self.state / "backup"
            self.data = {"paths": {}, "units": {}, "legacy": root.is_dir() and any(root.glob("*/MANIFEST"))}

    def save(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=1, sort_keys=True))
        os.replace(tmp, self.file)

    def keep(self, src):
        """Save a copy of a file's bytes; returns its name under files/."""
        files = self.dir / "files"
        files.mkdir(parents=True, exist_ok=True)
        name = str(len(list(files.iterdir())) + 1)
        shutil.copy2(src, files / name, follow_symlinks=True)
        return name

    def legacy(self, path):
        """The oldest legacy backup of `path`: ('absent'|'copy', Path) or None
        when there are no legacy backups at all."""
        root = self.state / "backup"
        dirs = sorted(d for d in root.glob("*/") if (d / "MANIFEST").is_file()) if root.is_dir() else []
        if not dirs:
            return None
        home = Path.home()
        for d in dirs:
            for rel in (d / "MANIFEST").read_text().splitlines():
                rel = rel.strip()
                if rel and (home / rel == Path(path) or Path(rel) == Path(path)):
                    return "copy", d / rel.lstrip("/")
        return "absent", None

    def remember(self, path):
        path = str(Path(path).absolute())
        if path in self.data["paths"]:
            return
        p = Path(path)
        rec = {}
        old = self.legacy(path) if self.data.get("legacy") else None
        if old and old[0] == "copy" and (old[1].exists() or old[1].is_symlink()):
            src = old[1]
            rec["from"] = "legacy backup " + str(src.parent)
        elif old and old[0] == "absent" and not (p.exists() or p.is_symlink()):
            src = None
            rec["from"] = "legacy backups (not in any: it was absent)"
        else:
            src = p
        if src is None or not (src.exists() or src.is_symlink()):
            rec["kind"] = "absent"
        elif src.is_symlink():
            rec.update(kind="link", target=os.readlink(src))
        elif src.is_file():
            rec.update(kind="file", saved=self.keep(src), mode=src.stat().st_mode & 0o7777)
        else:
            sys.exit(f"{path} is neither a file nor a link; not replacing it")
        rec["installed"] = None
        self.data["paths"][path] = rec
        self.save()

    def installed(self, path):
        path = str(Path(path).absolute())
        if path in self.data["paths"]:
            self.data["paths"][path]["installed"] = fingerprint(path)
            self.save()

    def edited(self, path):
        rec = self.data["paths"].get(str(Path(path).absolute())) or {}
        now = fingerprint(path)
        sys.exit(0 if rec.get("installed") and now != rec["installed"] and now != ["absent"] else 1)

    def original(self, rec):
        if rec["kind"] == "absent":
            return ["absent"]
        if rec["kind"] == "link":
            return ["link", rec["target"]]
        saved = self.dir / "files" / str(rec.get("saved"))
        return ["file", hashlib.sha256(saved.read_bytes()).hexdigest()] if saved.is_file() else None

    def manages(self, path):
        sys.exit(0 if str(Path(path).absolute()) in self.data["paths"] else 1)

    def unit(self, name):
        if name in self.data["units"]:
            return
        if self.data.get("legacy"):
            state = "unknown"
        elif user_bus():
            r = subprocess.run(["systemctl", "--user", "is-enabled", name], capture_output=True, text=True)
            state = "enabled" if r.stdout.strip() == "enabled" else "disabled"
        else:
            state = "enabled" if wanted_links(name) else "disabled"
        self.data["units"][name] = state
        self.save()

    def restore_one(self, path):
        path = str(Path(path).absolute())
        rec = self.data["paths"].get(path)
        if not rec:
            print(f"  • {path}: kuwai has no record of what was there before; left as it is")
            return 1
        now = fingerprint(path)
        if rec.get("installed") and now != rec["installed"] and now != ["absent"]:
            print(f"  • conflict: {path} changed since kuwai installed it; kept as it is")
            return 1
        put_back(Path(path), rec, self.dir / "files")
        del self.data["paths"][path]
        self.save()
        print(f"  ✓ restored {path} ({'removed: it was absent' if rec['kind'] == 'absent' else rec['kind']})")
        return 0

    def restore(self, dry):
        say = print
        if not self.data["paths"] and not self.data["units"]:
            return self.restore_legacy(dry)
        conflicts = 0
        stamp = time.strftime('%Y%m%d-%H%M%S')
        done = self.state / f"original.restored-{stamp}"
        failed = []
        units = sorted(self.data["units"].items())
        bus = user_bus()
        for name, state in units:
            if state == "enabled":
                continue
            if dry:
                say(f"  would: stop and disable {name} (as before kuwai)")
            elif not set_unit(name, False, bus):
                failed.append(name)
        for path, rec in sorted(self.data["paths"].items()):
            p = Path(path)
            now = fingerprint(p)
            if now == self.original(rec):
                continue
            if rec.get("installed") and now != rec["installed"] and now != ["absent"]:
                conflicts += 1
                where = f" (the original is saved at {(self.dir if dry else done) / 'files' / rec['saved']})" if rec["kind"] == "file" else ""
                say(f"  • conflict: {path} changed since kuwai installed it; kept as it is{where}")
                continue
            if dry:
                say(f"  would: restore {path} ({rec['kind']})")
                continue
            put_back(p, rec, self.dir / "files")
            say(f"  ✓ restored {path} ({'removed: it was absent' if rec['kind'] == 'absent' else rec['kind']})")
        if not dry and bus:
            subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
        for name, state in units:
            if state != "enabled":
                if not dry and name not in failed:
                    say(f"  ✓ {name}: disabled" + (", as before kuwai" if state != "unknown" else ""))
                continue
            if dry:
                say(f"  would: systemctl --user enable {name} (as before kuwai)")
            elif set_unit(name, True, bus):
                say(f"  ✓ {name}: enabled, as before kuwai")
            else:
                failed.append(name)
        if failed:
            say(f"  • could not set {', '.join(failed)} back; the record stays in {self.dir}: run ./install.sh --uninstall again")
            return 1
        if not dry:
            self.dir.rename(done)
            legacy = self.state / "backup"
            if legacy.is_dir():
                legacy.rename(self.state / f"backup.restored-{stamp}")
            say(f"  (the record is kept in {done})")
        return 0

    def restore_legacy(self, dry):
        """No record: an older installer's backups. Each path from its oldest copy."""
        root = self.state / "backup"
        dirs = sorted(d for d in root.glob("*/") if (d / "MANIFEST").is_file()) if root.is_dir() else []
        if not dirs:
            print(f"  • nothing recorded in {self.dir} or {root}: left everything as it is")
            return 0
        seen = set()
        for d in dirs:
            for rel in (d / "MANIFEST").read_text().splitlines():
                rel = rel.strip()
                if not rel or rel in seen:
                    continue
                seen.add(rel)
                dst = Path(rel) if rel.startswith("/") else Path.home() / rel
                src = d / rel.lstrip("/")
                if dry:
                    print(f"  would: restore {dst} from {d.name}")
                    continue
                rec = {"kind": "link", "target": os.readlink(src)} if src.is_symlink() else {"kind": "copy", "src": src}
                put_back(dst, rec, None)
                print(f"  ✓ restored {dst} (from the oldest backup, {d.name})")
        return 0


def user_bus():
    try:
        return subprocess.run(["systemctl", "--user", "show-environment"], capture_output=True).returncode == 0
    except OSError:
        return False


def units_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "systemd" / "user"


def wanted_links(name):
    return [p for d in units_dir().glob("*.wants") for p in [d / name] if p.is_symlink() or p.exists()] + \
        [p for d in units_dir().glob("*.requires") for p in [d / name] if p.is_symlink() or p.exists()]


def set_unit(name, on, bus):
    if bus:
        args = ["enable", name] if on else ["disable", "--now", name]
        r = subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True)
        if r.returncode == 0:
            return True
        missing = "not found" in (r.stderr or "") or "does not exist" in (r.stderr or "")
        return missing and not on
    if on:
        return False
    for link in wanted_links(name):
        link.unlink(missing_ok=True)
    return True


def put_back(p, rec, files):
    """Make `p` what `rec` says, replacing whatever is there (never writing through a link)."""
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(f".{p.name}.kuwai-restore")
    if tmp.exists() or tmp.is_symlink():
        tmp.unlink()
    kind = rec["kind"]
    if kind == "absent":
        if p.is_symlink() or p.is_file():
            p.unlink()
        return
    if kind == "link":
        os.symlink(rec["target"], tmp)
    elif kind == "file":
        shutil.copy2(files / rec["saved"], tmp)
        os.chmod(tmp, rec.get("mode", 0o644))
    elif kind == "copy":
        shutil.copy2(rec["src"], tmp)
    os.replace(tmp, p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("cmd", choices=["remember", "installed", "edited", "manages", "unit", "restore", "restore-one"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    s = Store(a.state)
    if a.cmd == "restore":
        sys.exit(s.restore(a.dry_run))
    if not a.arg:
        ap.error(f"{a.cmd} needs an argument")
    if a.cmd == "restore-one":
        sys.exit(s.restore_one(a.arg))
    getattr(s, a.cmd)(a.arg)


if __name__ == "__main__":
    main()
