import fcntl
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

from .extract import sha256_file

MANIFEST = "themes/wallpaper-packs.json"
LICENCES = {"CC0", "PD", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-3.0", "CC-BY-SA-3.0",
            "CC-BY-2.0", "CC-BY-SA-2.0", "ESO-CC-BY-4.0"}
MAX_BYTES = 40 * 1024 * 1024


def source_url(value, host, prefix):
    url = urlsplit(value)
    return (url.scheme == "https" and url.netloc == host and url.path.startswith(prefix)
            and not url.query and not url.fragment)


def catalog(root):
    packs = json.loads((Path(root) / MANIFEST).read_text(encoding="utf-8"))
    if not isinstance(packs, list) or not packs:
        raise ValueError("empty wallpaper pack catalog")
    ids = set()
    for pack in packs:
        key = pack["id"]
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", key) or key in ids or not pack["name"].strip():
            raise ValueError("invalid or duplicate wallpaper pack")
        ids.add(key)
        files = set()
        if not isinstance(pack["images"], list) or not pack["images"]:
            raise ValueError(f"{key}: no images")
        for image in pack["images"]:
            filename = image["file"]
            if (not re.fullmatch(r"[a-z0-9-]+\.(jpg|png|webp)", filename)
                    or filename in files or not image["name"].strip()):
                raise ValueError(f"{key}: invalid or duplicate image")
            if not re.fullmatch(r"[a-f0-9]{64}", image["sha256"]):
                raise ValueError(f"{key}/{filename}: missing SHA-256 pin")
            if type(image["bytes"]) is not int or not 0 < image["bytes"] <= MAX_BYTES:
                raise ValueError(f"{key}/{filename}: invalid size")
            if image["licence"] not in LICENCES or not image["author"].strip():
                raise ValueError(f"{key}/{filename}: missing redistributable licence or credit")
            if not (source_url(image["url"], "upload.wikimedia.org", "/wikipedia/commons/")
                    and source_url(image["page"], "commons.wikimedia.org", "/wiki/File:")):
                raise ValueError(f"{key}/{filename}: unapproved image or source URL")
            files.add(filename)
    return packs


def data_dir():
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "kuwai-data/wallpaper-packs"


def install_path(pack):
    revision = hashlib.sha256(json.dumps(pack["images"], sort_keys=True).encode()).hexdigest()[:16]
    return data_dir() / f"{pack['id']}-{revision}"


def installed(pack, *, verify=False):
    folder = install_path(pack)
    try:
        if folder.is_symlink() or not (folder / "CREDITS.txt").is_file():
            return False
        for image in pack["images"]:
            path = folder / image["file"]
            if path.is_symlink() or not path.is_file() or path.stat().st_size != image["bytes"]:
                return False
            if verify and sha256_file(path) != image["sha256"]:
                return False
    except OSError:
        return False
    return True


def installed_walls(root):
    try:
        packs = catalog(root)
    except (OSError, ValueError, KeyError, AttributeError, TypeError):
        return []
    return [
        {"path": str(install_path(pack) / image["file"]), "name": image["name"], "pack": pack["id"]}
        for pack in packs if installed(pack) for image in pack["images"]
    ]


def install(pack, progress):
    folder = install_path(pack)
    folder.parent.mkdir(parents=True, exist_ok=True)
    total = len(pack["images"])
    with (folder.parent / f".{pack['id']}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if installed(pack, verify=True):
            return
        with tempfile.TemporaryDirectory(prefix=f".{pack['id']}-", dir=folder.parent) as work:
            staging = Path(work) / "ready"
            staging.mkdir()
            credits = []
            for index, image in enumerate(pack["images"]):
                progress(index, total)
                path = staging / image["file"]
                subprocess.run(
                    ["curl", "--disable", "--fail", "--silent", "--show-error", "--proto", "=https",
                     "--max-time", "120", "--max-filesize", str(image["bytes"]), "--user-agent",
                     "kuwai-wallpacks/1 (+https://github.com/KitsuneKode/kuwai)", "--output", str(path), "--", image["url"]],
                    check=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, timeout=125,
                )
                if path.stat().st_size != image["bytes"] or sha256_file(path) != image["sha256"]:
                    raise ValueError(f"{image['file']}: wallpaper verification failed")
                licence = image["licence"]
                cc = re.search(r"CC-(BY(?:-SA)?)-([0-9.]+)$", licence)
                link = f"\nhttps://creativecommons.org/licenses/{cc[1].lower()}/{cc[2]}/" if cc else ""
                credits.append(f"{image['name']} — {image['author']} ({licence})\n{image['page']}{link}")
            (staging / "CREDITS.txt").write_text("Unmodified original images.\n\n" + "\n\n".join(credits) + "\n", encoding="utf-8")
            backup = Path(work) / "previous"
            if os.path.lexists(folder):
                os.rename(folder, backup)
            try:
                os.rename(staging, folder)
            except BaseException:
                if os.path.lexists(backup):
                    os.rename(backup, folder)
                raise
            progress(total, total)
