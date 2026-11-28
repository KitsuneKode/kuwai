import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
NEEDS = ("qs", "bwrap", "dbus-run-session", "Xvfb", "setpriv")
pytestmark = pytest.mark.skipif(any(shutil.which(b) is None for b in NEEDS), reason="needs qs, bwrap, dbus-run-session, Xvfb and setpriv")


def test_meeting_follows_a_fake_voxtype_from_start_to_summary():
    with tempfile.TemporaryDirectory(prefix="kuwai-meeting-") as out:
        run = subprocess.run([str(ROOT / "bin/kuwai-ui-test"), "--case", "meeting", "--backend", "x11", "--motion", "full", "--output", out],
                             capture_output=True, text=True, timeout=240)
        if run.returncode == 2:
            pytest.skip("sandbox unqualified: " + run.stdout.strip())
        verdict = json.loads(run.stdout.strip().splitlines()[-1])
        log = (Path(out) / "runtime.log").read_text() if (Path(out) / "runtime.log").exists() else ""
        assert verdict["status"] == "PASS", log[-2000:]
        for frame in ("meeting-live", "meeting-paused", "meeting-ended", "meeting-list", "meeting-detail"):
            assert (Path(out) / (frame + ".png")).is_file(), frame


def test_the_fake_speaks_the_contracts_shapes():
    feed = [json.loads(l) for l in (ROOT / "tests/ui/fixtures/meeting/feed.ndjson").read_text().splitlines() if l.strip()]
    assert feed[0]["event"] == "hello" and feed[-1]["event"] == "summary_ready"
    assert {e["event"] for e in feed} >= {"hello", "segments", "segment_updated", "segment_deleted", "speaker_renamed", "title_changed", "status", "levels", "summary_ready"}
    rows = json.loads((ROOT / "tests/ui/fixtures/meeting/list.json").read_text())
    assert all({"id", "title", "started_at", "duration_secs", "status", "speaker_count", "has_summary"} <= set(r) for r in rows)
