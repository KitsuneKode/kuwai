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

  rice_install.py --state DIR remember PATH
  rice_install.py --state DIR installed PATH
  rice_install.py --state DIR unit NAME
  rice_install.py --state DIR restore [--dry-run]
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
            # Older installs already replaced things: their backups are the
            # only trace of the original, and current unit states aren't.
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
        elif old and old[0] == "absent":
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

    def unit(self, name):
        if name in self.data["units"]:
            return
        if self.data.get("legacy"):
            state = "unknown"   # an older install already enabled it; what it was before is lost
        else:
            r = subprocess.run(["systemctl", "--user", "is-enabled", name], capture_output=True, text=True)
            state = "enabled" if r.stdout.strip() == "enabled" else "disabled"
        self.data["units"][name] = state
        self.save()

    def restore(self, dry):
        say = print
        if not self.data["paths"] and not self.data["units"]:
            return self.restore_legacy(dry)
        conflicts = 0
        stamp = time.strftime('%Y%m%d-%H%M%S')
        done = self.state / f"original.restored-{stamp}"
        for path, rec in sorted(self.data["paths"].items()):
            p = Path(path)
            now = fingerprint(p)
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
        for name, state in sorted(self.data["units"].items()):
            verb = "enable" if state == "enabled" else "disable"
            if dry:
                say(f"  would: systemctl --user {verb} {name} (as before kuwai)")
                continue
            subprocess.run(["systemctl", "--user", verb, name], capture_output=True)
            say(f"  ✓ {name}: {verb}d, as before kuwai" if state != "unknown" else f"  ✓ {name}: disabled")
        if not dry:
            self.dir.rename(done)
            legacy = self.state / "backup"
            if legacy.is_dir():   # used up: a later install starts a fresh record
                legacy.rename(self.state / f"backup.restored-{stamp}")
            say(f"  (the record is kept in {done})")
        return 0   # a conflict is reported, not a failure: your file is kept

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
    ap.add_argument("cmd", choices=["remember", "installed", "unit", "restore"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    s = Store(a.state)
    if a.cmd == "restore":
        sys.exit(s.restore(a.dry_run))
    if not a.arg:
        ap.error(f"{a.cmd} needs an argument")
    getattr(s, a.cmd)(a.arg)


if __name__ == "__main__":
    main()
