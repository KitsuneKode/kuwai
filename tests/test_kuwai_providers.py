"""bin/kuwai-providers: T3 Code's provider caches, read for the island.

Fixture caches in T3's shapes (seen in v0.1.12-nightly.20261125), never this machine's: the reader keeps
name, colour, status and reason, plan label and model names, says "unavailable" for a file it can't read
as that shape, and never lets the account's email reach its output or its own cache.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-providers"
EMAIL = "someone.private@example.org"
WORKSPACE = "ws-7f3a9c"

CLAUDE = {
    "displayName": "Claude-2", "showInteractionModeToggle": True, "enabled": True, "installed": True,
    "version": "3.1.0", "status": "ready",
    "auth": {"status": "authenticated", "email": EMAIL, "workspaceId": WORKSPACE, "type": "oauth",
             "label": "Claude Pro Subscription"},
    "checkedAt": "2099-01-01T00:00:00.000Z",
    "models": [{"slug": "claude-opus-5-5", "name": "Claude Opus 5.5", "aliases": ["opus"],
                "capabilities": {"optionDescriptors": [{"id": "effort", "label": "Effort"}]}},
               {"slug": "openrouter/~anthropic/claude-opus-latest", "name": "Claude Opus (latest)"}],
    "slashCommands": [{"name": "review", "description": "mail " + EMAIL}],
    "instanceId": "claudeAgent_2", "driver": "claudeAgent", "accentColor": "#EB2575",
    "continuation": {"groupKey": "claude:" + EMAIL},
}
CODEX_SIGNED_OUT = {
    "displayName": "codex-2", "enabled": True, "status": "warning", "auth": {"status": "unauthenticated"},
    "message": "Sign in with ChatGPT to use Codex.", "models": [], "instanceId": "codex_2", "driver": "codex",
}
PI_OFF = {
    "displayName": "Pi", "enabled": False, "status": "disabled", "auth": {"status": "unknown"},
    "message": "Pi is disabled in T3 Code settings.", "models": [{"slug": "pi", "name": "Pi default"}],
    "instanceId": "pi", "driver": "pi",
}
GROK_EMAIL_LABEL = {
    "displayName": "Grok", "enabled": True, "status": "ready",
    "auth": {"status": "authenticated", "label": EMAIL, "email": EMAIL}, "message": "Signed in as " + EMAIL,
    "models": [], "instanceId": "grok", "driver": "grok", "accentColor": "red",
}


def run(tmp_path, files=None, raw=None, cache_home=None):
    t3 = tmp_path / "t3"
    caches = t3 / "caches"
    if files is not None or raw is not None:
        caches.mkdir(parents=True, exist_ok=True)
    for name, data in (files or {}).items():
        (caches / name).write_text(json.dumps(data))
    for name, text in (raw or {}).items():
        (caches / name).write_text(text)
    env = dict(os.environ, T3CODE_HOME=str(t3), XDG_CACHE_HOME=str(cache_home or tmp_path / "cache"))
    out = subprocess.run([str(BIN)], env=env, capture_output=True, text=True, timeout=20)
    assert out.returncode == 0, out.stderr
    assert out.stderr == ""
    return json.loads(out.stdout), out.stdout


def by_id(doc):
    return {p["id"]: p for p in doc["providers"]}


def test_keeps_only_what_the_island_shows(tmp_path):
    doc, _ = run(tmp_path, {"claudeAgent_2.json": CLAUDE})
    assert doc["state"] == "ok"
    assert doc["providers"] == [{
        "id": "claudeAgent_2", "driver": "claudeAgent", "name": "Claude-2", "accent": "#eb2575", "enabled": True,
        "status": "ready", "reason": "", "auth": "authenticated", "plan": "Claude Pro Subscription",
        "models": [["claude-opus-5-5", "Claude Opus 5.5"], ["openrouter/~anthropic/claude-opus-latest", "Claude Opus (latest)"]],
    }]


def test_the_email_never_reaches_the_output_or_the_cache(tmp_path):
    cache = tmp_path / "cache"
    _, text = run(tmp_path, {"claudeAgent_2.json": CLAUDE, "grok.json": GROK_EMAIL_LABEL}, cache_home=cache)
    stored = (cache / "kuwai" / "providers.json").read_text()
    for s in (text, stored):
        assert EMAIL not in s
        assert WORKSPACE not in s
        assert "@" not in s


def test_a_value_that_is_an_email_is_dropped_not_shown(tmp_path):
    doc, _ = run(tmp_path, {"grok.json": GROK_EMAIL_LABEL})
    g = by_id(doc)["grok"]
    assert g["plan"] == "" and g["reason"] == ""
    assert g["accent"] == "", "a colour that isn't #rrggbb is not guessed"
    assert g["status"] == "ready"


def test_health_comes_through_in_plain_words(tmp_path):
    doc, _ = run(tmp_path, {"codex_2.json": CODEX_SIGNED_OUT, "pi.json": PI_OFF})
    p = by_id(doc)
    assert p["codex_2"]["status"] == "warning" and p["codex_2"]["auth"] == "unauthenticated"
    assert p["codex_2"]["reason"] == "Sign in with ChatGPT to use Codex."
    assert p["pi"]["status"] == "disabled" and p["pi"]["enabled"] is False


def test_a_malformed_or_reshaped_file_says_unavailable(tmp_path):
    reshaped = dict(CODEX_SIGNED_OUT)
    del reshaped["driver"]
    odd_status = dict(PI_OFF, status="sleeping")
    doc, _ = run(tmp_path, {"codex_2.json": reshaped, "pi.json": odd_status, "list.json": [1, 2]},
                 raw={"broken.json": '{"displayName": "Half', "claudeAgent_2.json": json.dumps(CLAUDE)})
    p = by_id(doc)
    assert doc["state"] == "ok"
    for gone in ("codex_2", "pi", "list", "broken"):
        assert p[gone] == {"id": gone, "status": "unavailable"}
    assert p["claudeAgent_2"]["status"] == "ready"


def test_only_unreadable_files_is_unavailable_not_empty(tmp_path):
    doc, _ = run(tmp_path, raw={"broken.json": "not json"})
    assert doc == {"state": "unavailable", "providers": [{"id": "broken", "status": "unavailable"}]}


def test_no_t3_is_none(tmp_path):
    assert run(tmp_path)[0] == {"state": "none", "providers": []}
    assert run(tmp_path, raw={"acp-auth-0123.json": '{"binding": "x", "authenticated": true}'})[0] == {"state": "none", "providers": []}


def test_a_huge_file_is_not_read(tmp_path):
    doc, _ = run(tmp_path, raw={"big.json": '{"pad": "' + "x" * (9 * 1024 * 1024) + '"}'})
    assert by_id(doc)["big"]["status"] == "unavailable"


def test_an_unchanged_file_is_not_parsed_again(tmp_path):
    cache = tmp_path / "cache"
    run(tmp_path, {"claudeAgent_2.json": CLAUDE}, cache_home=cache)
    f = tmp_path / "t3" / "caches" / "claudeAgent_2.json"
    st = f.stat()
    f.write_text(json.dumps(dict(CLAUDE, displayName="Claude-X")))
    assert f.stat().st_size == st.st_size
    os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns))
    doc, _ = run(tmp_path, cache_home=cache)
    assert by_id(doc)["claudeAgent_2"]["name"] == "Claude-2", "same size and time: the cached reading"
    os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
    doc, _ = run(tmp_path, cache_home=cache)
    assert by_id(doc)["claudeAgent_2"]["name"] == "Claude-X"


def test_a_corrupt_own_cache_is_read_past(tmp_path):
    cache = tmp_path / "cache"
    (cache / "kuwai").mkdir(parents=True)
    (cache / "kuwai" / "providers.json").write_text("{nope")
    doc, _ = run(tmp_path, {"pi.json": PI_OFF}, cache_home=cache)
    assert by_id(doc)["pi"]["name"] == "Pi"
