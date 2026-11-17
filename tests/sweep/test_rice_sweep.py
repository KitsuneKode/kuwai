"""bin/rice-sweep: what a sweep scan becomes for the island, offline.

Plans are shaped like `sweep scan --json`; no scan is run and nothing is deleted.
"""
import importlib.machinery
import importlib.util
import json
import stat
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
NOW = 1_800_000_000.0
DAY = 86_400_000
GB = 10**9


@pytest.fixture(scope="module")
def rs():
    loader = importlib.machinery.SourceFileLoader("rice_sweep", str(ROOT / "bin" / "rice-sweep"))
    spec = importlib.util.spec_from_loader("rice_sweep", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def cand(kind, size, tier="safe", root="/p/app", idle_days=None):
    c = {"kind": kind, "name": kind, "estimatedBytes": size, "riskTier": tier, "projectRoot": root}
    if idle_days is not None:
        c["projectActiveMs"] = NOW * 1000 - idle_days * DAY
    return c


def test_reclaimable_counts_only_safe_and_caution(rs):
    plan = {"candidates": [
        cand("node_modules", 5 * GB, "caution"), cand(".next", 1 * GB, "safe"),
        cand("target", 9 * GB, "dangerous"), cand(".git", 2 * GB, "blocked"),
    ]}
    s = rs.summarize(plan, NOW * 1000)
    assert (s["reclaimable"], s["safe"], s["caution"], s["protected"]) == (6 * GB, 1 * GB, 5 * GB, 2)


def test_kinds_are_ranked_by_size_and_capped(rs):
    plan = {"candidates": [cand(k, n * GB) for k, n in
                           [("a", 1), ("b", 5), ("c", 3), ("d", 2), ("e", 4)]] + [cand("b", GB)]}
    s = rs.summarize(plan, NOW * 1000)
    assert [(k["kind"], k["bytes"], k["count"]) for k in s["kinds"]] == [
        ("b", 6 * GB, 2), ("e", 4 * GB, 1), ("c", 3 * GB, 1), ("d", 2 * GB, 1)]


def test_idle_means_known_and_old_never_unknown(rs):
    plan = {"candidates": [
        cand("node_modules", 4 * GB, root="/p/old", idle_days=212),
        cand("target", 2 * GB, root="/p/old", idle_days=212),
        cand("node_modules", 3 * GB, root="/p/fresh", idle_days=3),
        cand("node_modules", 9 * GB, root="/p/unknown"),           # activity unreadable
        cand("node_modules", 7 * GB, tier="dangerous", root="/p/guarded", idle_days=400),
    ]}
    s = rs.summarize(plan, NOW * 1000)
    assert {k: v for k, v in s["idle"].items() if k != "kinds"} == {"days": 30, "projects": 1, "bytes": 6 * GB}
    assert s["projects"] == [{"name": "old", "path": "/p/old", "bytes": 6 * GB, "idleDays": 212}]


def test_idle_kinds_split_only_the_idle_projects_and_add_up_to_the_headline(rs):
    plan = {"candidates": [
        cand("node_modules", 4 * GB, root="/p/old", idle_days=212),
        cand("target", 2 * GB, root="/p/old", idle_days=212),
        cand("node_modules", 1 * GB, root="/p/older", idle_days=400),
        cand("node_modules", 30 * GB, root="/p/fresh", idle_days=3),     # busy: not in the idle split
        cand(".next", 9 * GB, root="/p/unknown"),                        # unknown is not idle
        cand("target", 7 * GB, tier="dangerous", root="/p/old", idle_days=212),
    ]}
    s = rs.summarize(plan, NOW * 1000)
    assert s["idle"]["kinds"] == [{"kind": "node_modules", "bytes": 5 * GB, "count": 2},
                                  {"kind": "target", "bytes": 2 * GB, "count": 1}]
    assert sum(k["bytes"] for k in s["idle"]["kinds"]) == s["idle"]["bytes"] == 7 * GB
    assert s["kinds"][0] == {"kind": "node_modules", "bytes": 35 * GB, "count": 3}     # all of it, still there


def test_empty_plan_is_all_zeros(rs):
    s = rs.summarize({"candidates": []}, NOW * 1000)
    assert s["reclaimable"] == 0 and s["kinds"] == [] and s["idle"]["projects"] == 0


def test_cache_round_trips_privately_and_ignores_junk(rs, tmp_path):
    p = tmp_path / "state" / "sweep-status.json"
    assert rs.read_cache(p) is None
    rs.write_cache(p, {"alive": True, "checkedAt": 5})
    assert rs.read_cache(p)["checkedAt"] == 5
    assert stat.S_IMODE(p.stat().st_mode) == 0o600
    assert not [f for f in p.parent.iterdir() if f.name.startswith(".sweep-status.")]
    p.write_text("not json")
    assert rs.read_cache(p) is None


@pytest.fixture
def proj(tmp_path):
    d = tmp_path / "Projects"
    d.mkdir()
    return str(d)


def test_answer_serves_the_cache_and_asks_for_a_refresh_only_when_stale(rs, tmp_path, proj, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    p = tmp_path / "c.json"
    rs.write_cache(p, {"alive": True, "checkedAt": int(NOW) - 60, "root": proj, "reclaimable": 7})
    out, again = rs.answer(p, proj, NOW)
    assert (out["stale"], out["refreshing"], again, out["reclaimable"]) == (False, False, False, 7)
    out, again = rs.answer(p, proj, NOW + 3600, ttl=1800)
    assert (out["stale"], out["refreshing"], again, out["reclaimable"]) == (True, True, True, 7)   # stale still shown


def test_a_new_root_or_no_cache_is_pending_not_stale_data(rs, tmp_path, proj, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    p = tmp_path / "c.json"
    assert rs.answer(p, proj, NOW) == ({"alive": True, "pending": True, "root": proj, "refreshing": True}, True)
    rs.write_cache(p, {"alive": True, "checkedAt": int(NOW), "root": "/elsewhere"})
    assert rs.answer(p, proj, NOW)[0]["pending"] is True


def test_without_sweep_the_capsule_has_nothing_to_show(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: None)
    assert rs.answer(tmp_path / "c.json", "/p", NOW) == ({"alive": False}, False)


def test_find_sweep_looks_in_bun_bin_when_path_lacks_it(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs.shutil, "which", lambda n: None)
    monkeypatch.setattr(rs.Path, "home", lambda: tmp_path)
    assert rs.find_sweep() is None
    exe = tmp_path / ".bun" / "bin" / "sweep"
    exe.parent.mkdir(parents=True)
    exe.write_text("#!/bin/sh\n")
    assert rs.find_sweep() is None            # not executable: not sweep
    exe.chmod(0o755)
    assert rs.find_sweep() == str(exe)


def test_refresh_scans_once_under_the_lock_and_caches(rs, tmp_path, proj, monkeypatch):
    calls = []
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    monkeypatch.setattr(rs, "status", lambda root: None)       # an older sweep: no `status`
    monkeypatch.setattr(rs, "scan", lambda root: calls.append(root) or {"candidates": [cand("target", GB)]})
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh(proj, p, now=NOW)
    assert calls == [proj] and data["reclaimable"] == GB and rs.read_cache(p)["root"] == proj
    assert "error" not in data
    # A failed scan leaves the last answer alone, with a note of what failed.
    monkeypatch.setattr(rs, "scan", lambda root: None)
    assert rs.refresh(proj, p, now=NOW + 1) is None
    c = rs.read_cache(p)
    assert (c["checkedAt"], c["reclaimable"], c["failedAt"]) == (int(NOW), GB, int(NOW) + 1)
    assert c["error"].startswith("scan failed")
    # Served with the note; no new try until the back-off is over.
    out, again = rs.answer(p, proj, NOW + 1000, ttl=600)
    assert (out["reclaimable"], out["error"][:11], out["stale"], again) == (GB, "scan failed", True, False)
    out, again = rs.answer(p, proj, NOW + 1 + rs.FAIL_RETRY_S + 1, ttl=1800)
    assert again is True
    # The next good count clears the note.
    monkeypatch.setattr(rs, "scan", lambda root: {"candidates": [cand("target", 2 * GB)]})
    data = rs.refresh(proj, p, now=NOW + 7200)
    assert "error" not in rs.read_cache(p) and data["reclaimable"] == 2 * GB


def test_a_missing_folder_says_so_instead_of_counting_forever(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    gone = str(tmp_path / "nope")
    p = tmp_path / "state" / "sweep-status.json"
    out, again = rs.answer(p, gone, NOW)
    assert (out["error"], out["checkedAt"], again) == ("folder missing", 0, False)
    assert "pending" not in out
    assert rs.refresh(gone, p, now=NOW) is None
    c = rs.read_cache(p)
    assert (c["error"], c["checkedAt"], c["root"], c["failedAt"]) == ("folder missing", 0, gone, int(NOW))


def test_a_failing_sweep_is_recorded_not_retried_in_a_loop(rs, tmp_path, proj, monkeypatch):
    # A real `sweep` on PATH that fails every command (status and scan alike).
    bindir = tmp_path / "bin"
    bindir.mkdir()
    shim = bindir / "sweep"
    shim.write_text("#!/bin/sh\necho 'boom' >&2\nexit 3\n")
    shim.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:/usr/bin:/bin")
    monkeypatch.setattr(rs.Path, "home", lambda: tmp_path)
    assert rs.find_sweep() == str(shim)
    p = tmp_path / "state" / "sweep-status.json"
    assert rs.refresh(proj, p, now=NOW) is None
    c = rs.read_cache(p)
    assert (c["error"], c["checkedAt"], c["failedAt"]) == ("scan failed (exit 3)", 0, int(NOW))
    out, again = rs.answer(p, proj, NOW + 60)
    assert (out["error"], out.get("pending"), out["refreshing"], again) == ("scan failed (exit 3)", None, False, False)


def test_while_the_lock_is_held_it_says_refreshing_and_starts_no_second(rs, tmp_path, proj, monkeypatch):
    import fcntl
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    monkeypatch.setattr(rs, "scan", lambda root: pytest.fail("a refresh is already running"))
    monkeypatch.setattr(rs, "status", lambda root: pytest.fail("a refresh is already running"))
    p = tmp_path / "state" / "sweep-status.json"
    rs.write_cache(p, {"alive": True, "checkedAt": int(NOW) - 7200, "root": proj, "reclaimable": 7})
    with open(rs.lock_path(p), "a") as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert rs.is_refreshing(p) is True
        out, again = rs.answer(p, proj, NOW, ttl=1800)
        assert (out["refreshing"], out["stale"], out["reclaimable"], again) == (True, True, 7, False)
        assert rs.refresh(proj, p, now=NOW) is None
        assert rs.read_cache(p)["checkedAt"] == int(NOW) - 7200          # untouched
        # First run under a held lock: pending, and no second refresh.
        p.unlink()
        assert rs.answer(p, proj, NOW) == ({"alive": True, "pending": True, "root": proj, "refreshing": True}, False)
    assert rs.is_refreshing(p) is False


def test_the_background_beat_is_6h_and_the_panel_asks_for_30_min(rs, tmp_path, proj, monkeypatch, capsys):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    monkeypatch.setattr(rs, "state_dir", lambda: tmp_path / "state")
    monkeypatch.setattr(rs.time, "time", lambda: NOW)
    spawned = []
    monkeypatch.setattr(rs.subprocess, "Popen", lambda cmd, **kw: spawned.append(cmd))
    rs.write_cache(tmp_path / "state" / "sweep-status.json", {"alive": True, "checkedAt": int(NOW) - 2 * 3600, "root": proj})
    assert rs.TTL_S == 6 * 3600
    assert rs.main(["--root", proj]) == 0 and spawned == []                       # 2 h old: fine for the mark
    assert json.loads(capsys.readouterr().out)["stale"] is False
    assert rs.main(["--max-age", "1800", "--root", proj]) == 0                    # the panel: older than 30 min
    assert len(spawned) == 1 and spawned[0][-3:] == ["--refresh", "--root", proj]
    assert json.loads(capsys.readouterr().out)["refreshing"] is True
    assert rs.main(["--max-age", "soon"]) == 2


def test_the_review_opens_in_your_terminal(rs):
    run = ["sh", "-c", rs.REVIEW_SH, "sh", "/x/sweep", "/p/app"]
    assert rs.open_cmd("", "/x/sweep", "/p/app") == [
        "kitty", "--single-instance", "--instance-group=local", "--title", "sweep", "--directory", "/p/app", *run]
    assert rs.open_cmd("/usr/bin/kitty", "/x/sweep", "/p/app")[0] == "kitty"
    assert rs.open_cmd("ghostty", "/x/sweep", "/p/app") == [
        "ghostty", "--working-directory=/p/app", "--title=sweep", "-e", *run]
    assert rs.open_cmd("foot", "/x/sweep", "/p/app") == ["foot", "--working-directory=/p/app", "--title=sweep", *run]
    assert rs.open_cmd("alacritty --class x", "/x/sweep", "/p/app") == ["alacritty", "--class", "x", "-e", *run]


@pytest.mark.parametrize("code,kept", [(0, False), (3, True)])
def test_the_window_stays_only_when_sweep_failed(rs, tmp_path, code, kept):
    import subprocess
    fake = tmp_path / "sweep"
    fake.write_text(f"#!/bin/sh\n[ \"$1\" = ui ] && [ \"$2\" = /p/app ] || exit 99\nexit {code}\n")
    fake.chmod(0o755)
    r = subprocess.run(["sh", "-c", rs.REVIEW_SH, "sh", str(fake), "/p/app"], input="\n",
                       capture_output=True, text=True, timeout=10)
    assert r.returncode == code
    assert ("Press Enter to close" in r.stdout) is kept


def test_open_needs_sweep_and_a_folder(rs, tmp_path, monkeypatch):
    spawned = []
    monkeypatch.setattr(rs.subprocess, "Popen", lambda cmd, **kw: spawned.append((cmd, kw["cwd"])))
    monkeypatch.setattr(rs, "find_sweep", lambda: None)
    assert rs.open_review(str(tmp_path)) == 1 and spawned == []
    monkeypatch.setattr(rs, "find_sweep", lambda: "/x/sweep")
    assert rs.open_review(str(tmp_path / "gone")) == 1 and spawned == []
    monkeypatch.setenv("KUWAI_TERMINAL", "foot")
    assert rs.main(["--open", str(tmp_path)]) == 0
    assert spawned[0][0][0] == "foot" and spawned[0][1] == str(tmp_path)


STATUS = {
    "reclaimableBytes": 7 * GB, "safeBytes": 2 * GB, "cautionBytes": 5 * GB, "protectedCount": 3,
    "idle": {"days": 30, "projects": 1, "bytes": 4 * GB},
    "kinds": [{"kind": f"k{i}", "bytes": GB, "count": 1} for i in range(6)],
    "projects": [{"name": "old", "path": "/p/old", "bytes": 4 * GB, "idleDays": 212}],
}


def test_sweeps_own_status_is_used_when_it_has_one(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    monkeypatch.setattr(rs, "_run", lambda args: json.dumps(STATUS).encode() if args[0] == "status" else None)
    monkeypatch.setattr(rs, "scan", lambda root: pytest.fail("status answered; no scan needed"))
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh(str(tmp_path), p, now=NOW)
    assert (data["reclaimable"], data["safe"], data["caution"], data["protected"]) == (7 * GB, 2 * GB, 5 * GB, 3)
    assert data["idle"] == {"days": 30, "projects": 1, "bytes": 4 * GB}          # no idle.kinds: left out
    assert len(data["kinds"]) == 4                                   # the island shows four
    # The path comes along: a row opens the project it names.
    assert data["projects"] == [{"name": "old", "path": "/p/old", "bytes": 4 * GB, "idleDays": 212}]
    no_path = {**STATUS, "projects": [{"name": "old", "bytes": 4 * GB, "idleDays": 212}]}
    assert rs.from_status(no_path)["projects"] == [{"name": "old", "bytes": 4 * GB, "idleDays": 212}]


def test_status_idle_kinds_are_kept_when_sweep_gives_them(rs):
    st = {**STATUS, "idle": {**STATUS["idle"], "kinds": [{"kind": f"k{i}", "bytes": GB, "count": 2} for i in range(6)]}}
    out = rs.from_status(st)
    assert len(out["idle"]["kinds"]) == 4 and out["idle"]["kinds"][0] == {"kind": "k0", "bytes": GB, "count": 2}
    assert "kinds" not in rs.from_status(STATUS)["idle"]


def test_an_older_sweep_without_status_falls_back_to_the_scan(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    monkeypatch.setattr(rs, "_run", lambda args: None if args[0] == "status" else
                        json.dumps({"candidates": [cand("target", GB)]}).encode())
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh(str(tmp_path), p, now=NOW)
    assert data["reclaimable"] == GB and rs.read_cache(p)["root"] == str(tmp_path)


def test_a_status_that_is_not_a_summary_is_not_trusted(rs, tmp_path, monkeypatch):
    for junk in (b"not json", b"[]", b'{"reclaimableBytes":"lots"}', b'{"reclaimableBytes":1}'):
        monkeypatch.setattr(rs, "_run", lambda args, junk=junk: junk)
        assert rs.status(str(tmp_path)) is None
