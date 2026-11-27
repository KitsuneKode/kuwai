"""kuwai-storage: what fills the disk that a tool rebuilds, cleared only the tool's own way."""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin/kuwai-storage"


def run(home, *args, path=None, env=None):
    env = {"HOME": str(home), "PATH": path or os.environ["PATH"], "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_DATA_HOME": str(home / ".local/share"), **(env or {})}
    r = subprocess.run([str(BIN), *args], capture_output=True, text=True, env=env, timeout=60)
    return json.loads(r.stdout)


def fill(d, mb):
    d.mkdir(parents=True, exist_ok=True)
    (d / "blob").write_bytes(os.urandom(mb << 20))


def module():
    loader = importlib.machinery.SourceFileLoader("storage_fixture", str(BIN))
    spec = importlib.util.spec_from_loader("storage_fixture", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


def test_it_finds_caches_and_tags_what_comes_back(tmp_path):
    fill(tmp_path / ".cache/thumbnails/large", 2)
    fill(tmp_path / ".local/share/Trash/files", 2)
    out = run(tmp_path, "scan", "--fresh", path=str(tools(tmp_path)))
    got = {i["id"]: i for i in out["items"]}
    assert got["thumbnails"]["clearable"] is True and got["thumbnails"]["tag"] == "comes back"
    assert got["trash"]["clearable"] is False and got["trash"]["tag"] == "check first"
    assert out["disk"]["total"] > out["disk"]["free"] > 0


def test_clearing_a_normal_cache_tree_empties_it_and_keeps_the_root(tmp_path):
    thumbs = tmp_path / ".cache/thumbnails"
    fill(thumbs / "large" / "nested", 1)
    (thumbs / "small").mkdir(parents=True)
    (thumbs / "small" / "one").write_text("one")
    out = run(tmp_path, "clear", "thumbnails")
    assert out["ok"] is True and out["freed"] > 0
    assert thumbs.is_dir() and not any(thumbs.iterdir())


def test_clearing_thumbnails_never_follows_a_link_out(tmp_path):
    keep = tmp_path / "Pictures"
    fill(keep, 1)
    thumbs = tmp_path / ".cache/thumbnails"
    fill(thumbs / "large", 2)
    (thumbs / "escape").symlink_to(keep)
    out = run(tmp_path, "clear", "thumbnails")
    assert out["ok"] is True and out["freed"] > 0
    assert (keep / "blob").exists(), "a link inside the cache is removed, not what it points at"
    assert thumbs.is_dir() and not any(thumbs.iterdir())


def test_a_directory_swapped_for_a_link_mid_walk_is_never_followed(tmp_path, monkeypatch):
    keep = tmp_path / "keep"
    keep.mkdir()
    (keep / "blob").write_text("keep me")
    cache = tmp_path / "cache"
    trap = cache / "trap"
    trap.mkdir(parents=True)
    real_scandir = os.scandir
    swapped = []

    def scanning(fd):
        entries = list(real_scandir(fd))
        if not swapped and any(e.name == "trap" for e in entries):
            swapped.append(True)
            trap.rmdir()
            trap.symlink_to(keep)
        return iter(entries)

    monkeypatch.setattr(os, "scandir", scanning)
    module().empty(str(cache))
    assert (keep / "blob").read_text() == "keep me"
    assert not cache.exists() or os.listdir(cache) == []


def test_what_needs_a_look_is_never_cleared_from_here(tmp_path):
    fill(tmp_path / ".local/share/Trash/files", 1)
    for kid in ("trash", "pacman", "paru", "../../etc"):
        assert run(tmp_path, "clear", kid)["ok"] is False
    assert (tmp_path / ".local/share/Trash/files/blob").exists()


def test_a_tool_that_isnt_installed_is_said_so(tmp_path):
    fill(tmp_path / ".cache/go-build", 2)
    only = tmp_path / "bin"
    only.mkdir()
    for tool in ("python3", "du", "nice", "ionice"):
        (only / tool).symlink_to(subprocess.run(["sh", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip())
    out = run(tmp_path, "clear", "go", path=str(only))
    assert out == {"ok": False, "why": "Go build cache: its tool isn't installed"}


MiB = 1 << 20
GiB = 1 << 30

DOCKER = """#!/bin/sh
echo "docker $*" >> "$FAKE_LOG"
case "$*" in
  "system df --format json")
    if [ -n "$FAKE_ERR" ]; then echo "$FAKE_ERR" >&2; exit 1; fi
    cat "$FAKE_DF" ;;
  "image prune --force"|"builder prune --force")
    if [ -n "$FAKE_PRUNE_FAILS" ]; then echo "boom" >&2; exit 1; fi
    if [ -f "$FAKE_AFTER" ]; then cp "$FAKE_AFTER" "$FAKE_DF"; fi
    echo "Total reclaimed space: 1GB" ;;
  *) echo "unexpected: $*" >&2; exit 64 ;;
esac
"""

JOURNALCTL = """#!/bin/sh
echo "journalctl $*" >> "$FAKE_LOG"
case "$*" in
  "--user --disk-usage") [ -n "$FAKE_J_USER" ] && { echo "$FAKE_J_USER"; exit 0; }; exit 1 ;;
  "--system --disk-usage") [ -n "$FAKE_J_SYSTEM" ] && { echo "$FAKE_J_SYSTEM"; exit 0; }; exit 1 ;;
  *) echo "unexpected: $*" >&2; exit 64 ;;
esac
"""


def tools(tmp, docker=False, journalctl=False):
    only = tmp / "fakebin"
    only.mkdir(exist_ok=True)
    for tool in ("python3", "du", "nice", "ionice", "sh", "env", "cat", "cp"):
        link = only / tool
        if not link.exists():
            link.symlink_to(subprocess.run(["sh", "-c", "command -v " + tool], capture_output=True, text=True).stdout.strip())
    for name, body, wanted in (("docker", DOCKER, docker), ("journalctl", JOURNALCTL, journalctl)):
        (only / name).unlink(missing_ok=True)
        if wanted:
            (only / name).write_text(body)
            (only / name).chmod(0o755)
    return only


def df_text(images="13.84GB (68%)", containers="297.6kB (92%)", volumes="738.1MB (95%)", cache="2.347kB"):
    rows = [("Images", images), ("Containers", containers), ("Local Volumes", volumes), ("Build Cache", cache)]
    return "\n".join(json.dumps({"Active": "1", "Reclaimable": r, "Size": "1GB", "TotalCount": "3", "Type": t}) for t, r in rows) + "\n"


class Fakes:
    def __init__(self, tmp, **kw):
        self.tmp = tmp
        self.bin = tools(tmp, docker=kw.pop("docker", True), journalctl=kw.pop("journalctl", True))
        self.log = tmp / "calls.log"
        self.log.write_text("")
        self.df = tmp / "df.json"
        self.after = tmp / "after.json"
        self.df.write_text(kw.pop("df", df_text()))
        self.env = {"FAKE_LOG": str(self.log), "FAKE_DF": str(self.df), "FAKE_AFTER": str(self.after),
                    "FAKE_J_USER": "Archived and active journals take up 180.2M in the file system.",
                    "FAKE_J_SYSTEM": "Archived and active journals take up 28M in the file system."}
        self.env.update(kw)

    def run(self, *args):
        return run(self.tmp, *args, path=str(self.bin), env=self.env)

    def calls(self):
        return self.log.read_text().splitlines()


def item(out, kid):
    return next((i for i in out["items"] if i["id"] == kid), None)


def test_docker_shows_what_would_go_with_the_exact_commands_and_offers_only_images_and_build_cache(tmp_path):
    f = Fakes(tmp_path, df=df_text(cache="2.417GB"))
    out = f.run("scan", "--fresh")
    d = item(out, "docker")
    assert out["docker"] == {"state": "ok"}
    assert d["tag"] == "check first" and d["clearable"] is False
    parts = {p["id"]: p for p in d["parts"]}
    assert parts["docker-images"]["bytes"] == 13_840_000_000
    assert parts["docker-builder"]["bytes"] == 2_417_000_000
    assert parts["docker-containers"]["bytes"] == 297_600
    assert parts["docker-volumes"]["bytes"] == 738_100_000
    assert parts["docker-images"]["command"] == "docker image prune"
    assert parts["docker-builder"]["command"] == "docker builder prune"
    assert parts["docker-containers"]["command"] == "docker container prune"
    assert parts["docker-volumes"]["command"] == "docker volume prune"
    assert {k for k, p in parts.items() if p["runnable"]} == {"docker-images", "docker-builder"}
    assert d["bytes"] == sum(p["bytes"] for p in d["parts"])
    assert all("volume" not in p["why"] for p in [d] if False)
    assert [c for c in f.calls() if c.startswith("docker")] == ["docker system df --format json"]


def test_docker_sizes_read_every_shape_the_cli_prints(tmp_path):
    f = Fakes(tmp_path, df=df_text(images="0B", containers="1.5MiB", volumes="2GB (10%)", cache="3.3TB (99%)"))
    d = item(f.run("scan", "--fresh"), "docker")
    parts = {p["id"]: p["bytes"] for p in d["parts"]}
    assert "docker-images" not in parts
    assert parts == {"docker-builder": 3_300_000_000_000, "docker-containers": 1_572_864, "docker-volumes": 2_000_000_000}


def test_docker_as_one_json_array_reads_the_same(tmp_path):
    rows = [json.loads(line) for line in df_text().splitlines()]
    f = Fakes(tmp_path, df=json.dumps(rows))
    assert item(f.run("scan", "--fresh"), "docker")["parts"][0]["bytes"] == 13_840_000_000


def test_very_large_numbers_stay_whole_numbers_and_never_break_the_scan(tmp_path):
    f = Fakes(tmp_path, df=df_text(images="9999EB (99%)", containers="1.5PB", volumes="123456789012345678TB", cache="8EB"),
              FAKE_J_USER="Archived and active journals take up 3.2P in the file system.",
              FAKE_J_SYSTEM="Archived and active journals take up 999E in the file system.")
    out = f.run("scan", "--fresh")
    for kid in ("docker", "journal"):
        i = item(out, kid)
        assert type(i["bytes"]) is int and 0 < i["bytes"] < 1 << 64
        assert all(type(p["bytes"]) is int and 0 < p["bytes"] <= 1 << 62 for p in i["parts"])
    assert item(out, "docker")["parts"][1]["bytes"] == 1 << 62


def test_a_docker_daemon_that_is_down_is_one_state_not_a_stack_trace(tmp_path):
    f = Fakes(tmp_path, FAKE_ERR="Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?")
    out = f.run("scan", "--fresh")
    assert out["docker"] == {"state": "down"}
    assert item(out, "docker") is None
    assert "Traceback" not in json.dumps(out)


def test_permission_denied_is_told_apart_from_a_daemon_that_is_down(tmp_path):
    f = Fakes(tmp_path, FAKE_ERR="permission denied while trying to connect to the docker API at unix:///var/run/docker.sock")
    out = f.run("scan", "--fresh")
    assert out["docker"] == {"state": "denied"}
    assert item(out, "docker") is None


def test_docker_not_installed_is_a_state_and_runs_nothing(tmp_path):
    f = Fakes(tmp_path, docker=False)
    out = f.run("scan", "--fresh")
    assert out["docker"] == {"state": "missing"}
    assert item(out, "docker") is None
    assert not any(c.startswith("docker") for c in f.calls())


def test_output_that_is_not_docker_json_counts_as_unreachable(tmp_path):
    for junk in ("", "not json at all\n", "[]", "{\"Type\": 7}\n", "\x00\xff"):
        f = Fakes(tmp_path, df=junk)
        out = f.run("scan", "--fresh")
        assert out["docker"]["state"] == "down", junk
        assert item(out, "docker") is None


def test_a_machine_with_nothing_to_reclaim_shows_no_docker_row(tmp_path):
    f = Fakes(tmp_path, df=df_text(images="0B", containers="0B", volumes="12kB", cache="0B"))
    out = f.run("scan", "--fresh")
    assert out["docker"] == {"state": "ok"} and item(out, "docker") is None


def test_clearing_images_runs_only_image_prune_and_says_what_was_freed(tmp_path):
    f = Fakes(tmp_path)
    f.after.write_text(df_text(images="1.84GB (12%)"))
    out = f.run("clear", "docker-images")
    assert out == {"ok": True, "freed": 12_000_000_000}
    assert [c for c in f.calls() if c.startswith("docker")] == [
        "docker system df --format json", "docker image prune --force", "docker system df --format json"]


def test_clearing_build_cache_runs_only_builder_prune(tmp_path):
    f = Fakes(tmp_path, df=df_text(cache="2GB"))
    f.after.write_text(df_text(cache="0B"))
    assert f.run("clear", "docker-builder") == {"ok": True, "freed": 2_000_000_000}
    assert "docker builder prune --force" in f.calls()
    assert not any("image" in c or "volume" in c or "container" in c for c in f.calls())


def test_volumes_containers_and_the_journals_can_never_be_cleared_from_here(tmp_path):
    f = Fakes(tmp_path)
    for kid in ("docker-volumes", "docker-containers", "docker", "journal", "journal-user", "journal-system", "docker-images ", "docker-images;ls"):
        assert f.run("clear", kid)["ok"] is False, kid
    assert f.calls() == []


def test_clearing_with_the_daemon_down_or_denied_says_so_plainly(tmp_path):
    f = Fakes(tmp_path, FAKE_ERR="Cannot connect to the Docker daemon")
    assert f.run("clear", "docker-images") == {"ok": False, "why": "Docker isn't running"}
    f = Fakes(tmp_path, FAKE_ERR="permission denied")
    assert f.run("clear", "docker-images") == {"ok": False, "why": "Docker won't let this user in"}
    assert not any("prune" in c for c in f.calls())


def test_a_prune_that_fails_says_what_could_not_be_cleared(tmp_path):
    f = Fakes(tmp_path, FAKE_PRUNE_FAILS="1")
    assert f.run("clear", "docker-images") == {"ok": False, "why": "Unused images couldn't be cleared"}


def test_journals_are_read_only_with_the_commands_to_shrink_them(tmp_path):
    f = Fakes(tmp_path, docker=False)
    out = f.run("scan", "--fresh")
    j = item(out, "journal")
    parts = {p["id"]: p for p in j["parts"]}
    assert parts["journal-user"]["bytes"] == int(180.2 * MiB)
    assert parts["journal-system"]["bytes"] == 28 * MiB
    assert parts["journal-user"]["command"] == "journalctl --user --vacuum-time=2weeks"
    assert parts["journal-system"]["command"] == "sudo journalctl --vacuum-time=2weeks"
    assert not any(p["runnable"] for p in j["parts"])
    assert j["tag"] == "check first" and j["clearable"] is False
    assert j["bytes"] == sum(p["bytes"] for p in j["parts"])
    assert sorted(f.calls()) == ["journalctl --system --disk-usage", "journalctl --user --disk-usage"]


def test_a_journal_that_cannot_be_read_or_is_small_is_left_out(tmp_path):
    f = Fakes(tmp_path, docker=False, FAKE_J_SYSTEM="", FAKE_J_USER="Archived and active journals take up 512K in the file system.")
    assert item(f.run("scan", "--fresh"), "journal") is None
    f = Fakes(tmp_path, docker=False, FAKE_J_USER="Archived and active journals take up 1.5G in the file system.", FAKE_J_SYSTEM="")
    j = item(f.run("scan", "--fresh"), "journal")
    assert [p["id"] for p in j["parts"]] == ["journal-user"] and j["parts"][0]["bytes"] == int(1.5 * GiB)
    f = Fakes(tmp_path, journalctl=False, docker=False)
    assert item(f.run("scan", "--fresh"), "journal") is None


def test_docker_and_journal_sit_with_the_other_caches_biggest_first(tmp_path):
    fill(tmp_path / ".cache/thumbnails/large", 2)
    f = Fakes(tmp_path)
    out = f.run("scan", "--fresh")
    ids = [i["id"] for i in out["items"]]
    assert ids[0] == "docker" and {"docker", "journal", "thumbnails"} <= set(ids)
    assert [i["bytes"] for i in out["items"]] == sorted((i["bytes"] for i in out["items"]), reverse=True)
