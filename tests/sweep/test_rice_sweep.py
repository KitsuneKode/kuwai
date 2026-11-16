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
    assert s["idle"] == {"days": 30, "projects": 1, "bytes": 6 * GB}
    assert s["projects"] == [{"name": "old", "bytes": 6 * GB, "idleDays": 212}]


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


def test_answer_serves_the_cache_and_asks_for_a_refresh_only_when_stale(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    p = tmp_path / "c.json"
    rs.write_cache(p, {"alive": True, "checkedAt": int(NOW) - 60, "root": "/p", "reclaimable": 7})
    out, again = rs.answer(p, "/p", NOW)
    assert (out["stale"], again, out["reclaimable"]) == (False, False, 7)
    out, again = rs.answer(p, "/p", NOW + 3600)
    assert (out["stale"], again, out["reclaimable"]) == (True, True, 7)    # stale answer still shown


def test_a_new_root_or_no_cache_is_pending_not_stale_data(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "find_sweep", lambda: "/usr/bin/sweep")
    p = tmp_path / "c.json"
    assert rs.answer(p, "/p", NOW) == ({"alive": True, "pending": True, "root": "/p"}, True)
    rs.write_cache(p, {"alive": True, "checkedAt": int(NOW), "root": "/elsewhere"})
    assert rs.answer(p, "/p", NOW)[0]["pending"] is True


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


def test_refresh_scans_once_under_the_lock_and_caches(rs, tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(rs, "status", lambda root: None)       # an older sweep: no `status`
    monkeypatch.setattr(rs, "scan", lambda root: calls.append(root) or {"candidates": [cand("target", GB)]})
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh("/p", p, now=NOW)
    assert calls == ["/p"] and data["reclaimable"] == GB and rs.read_cache(p)["root"] == "/p"
    # A failed scan leaves the last answer alone.
    monkeypatch.setattr(rs, "scan", lambda root: None)
    assert rs.refresh("/p", p, now=NOW + 1) is None
    assert rs.read_cache(p)["checkedAt"] == int(NOW)


STATUS = {
    "reclaimableBytes": 7 * GB, "safeBytes": 2 * GB, "cautionBytes": 5 * GB, "protectedCount": 3,
    "idle": {"days": 30, "projects": 1, "bytes": 4 * GB},
    "kinds": [{"kind": f"k{i}", "bytes": GB, "count": 1} for i in range(6)],
    "projects": [{"name": "old", "path": "/p/old", "bytes": 4 * GB, "idleDays": 212}],
}


def test_sweeps_own_status_is_used_when_it_has_one(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "_run", lambda args: json.dumps(STATUS).encode() if args[0] == "status" else None)
    monkeypatch.setattr(rs, "scan", lambda root: pytest.fail("status answered; no scan needed"))
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh(str(tmp_path), p, now=NOW)
    assert (data["reclaimable"], data["safe"], data["caution"], data["protected"]) == (7 * GB, 2 * GB, 5 * GB, 3)
    assert data["idle"] == {"days": 30, "projects": 1, "bytes": 4 * GB}
    assert len(data["kinds"]) == 4                                   # the island shows four
    assert data["projects"] == [{"name": "old", "bytes": 4 * GB, "idleDays": 212}]   # paths stay in sweep


def test_an_older_sweep_without_status_falls_back_to_the_scan(rs, tmp_path, monkeypatch):
    monkeypatch.setattr(rs, "_run", lambda args: None if args[0] == "status" else
                        json.dumps({"candidates": [cand("target", GB)]}).encode())
    p = tmp_path / "state" / "sweep-status.json"
    data = rs.refresh(str(tmp_path), p, now=NOW)
    assert data["reclaimable"] == GB and rs.read_cache(p)["root"] == str(tmp_path)


def test_a_status_that_is_not_a_summary_is_not_trusted(rs, tmp_path, monkeypatch):
    for junk in (b"not json", b"[]", b'{"reclaimableBytes":"lots"}', b'{"reclaimableBytes":1}'):
        monkeypatch.setattr(rs, "_run", lambda args, junk=junk: junk)
        assert rs.status(str(tmp_path)) is None
