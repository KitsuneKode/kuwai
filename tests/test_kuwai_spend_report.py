"""bin/kuwai-spend-report: the Usage panel's Spend and Tokens.

Without a token, or with T3 Code closed, it reads the totals kuwai-spend keeps
from this machine's logs and says why, each model's share of the day's money.
"""
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-spend-report"


def run(home, period):
    runner = shutil.which("bun") or shutil.which("node")
    env = {"PATH": os.environ.get("PATH", ""), "HOME": str(home), "XDG_STATE_HOME": str(home / "state"),
           "XDG_CACHE_HOME": str(home / "cache"), "T3CODE_HOME": str(home / "t3"), "TZ": "UTC",
           "KUWAI_NOW_MS": str(int(time.mktime((2026, 11, 22, 12, 0, 0, 0, 0, 0)) * 1000))}
    out = subprocess.run([runner, str(BIN), period], env=env, capture_output=True, text=True, timeout=60, check=True)
    return json.loads(out.stdout)


def test_without_a_token_it_reads_the_local_logs(tmp_path):
    cache = tmp_path / "cache" / "kuwai"
    cache.mkdir(parents=True)
    (cache / "spend.json").write_text(json.dumps({"version": 1, "files": {}, "days": {
        "claude": {"2026-11-22": {"tokens": 300, "cost": 3.0, "unpriced": 0, "models": {"opus": 200, "sonnet": 100}},
                   "2026-10-01": {"tokens": 999, "cost": 9.0, "unpriced": 0, "models": {"opus": 999}}},
        "codex": {"2026-11-20": {"tokens": 50, "cost": 0, "unpriced": 50, "models": {"gpt": 50}}}}}))
    d = run(tmp_path, "7d")
    assert d["source"] == "local" and d["why"] == "token" and d["period"] == "7d"
    by = {(b["provider"], b["model"]): b for b in d["buckets"]}
    assert set(by) == {("claude", "opus"), ("claude", "sonnet"), ("codex", "gpt")}
    assert abs(by[("claude", "opus")]["cost"] - 2.0) < 1e-9
    assert by[("codex", "gpt")]["priced"] is False


def test_nothing_recorded_is_an_empty_report(tmp_path):
    d = run(tmp_path, "24h")
    assert d["source"] == "local" and d["buckets"] == [] and d["period"] == "24h"


def test_an_unknown_period_is_a_week(tmp_path):
    assert run(tmp_path, "nonsense")["period"] == "7d"
