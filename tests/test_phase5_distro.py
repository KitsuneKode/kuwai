"""Phase 5 distribution tests: VERSION, kuwai-webapp, kuwai-profile, and kuwai-ctl rollback/help."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def isolated_env(tmp_path):
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(tmp_path / "home"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_STATE_HOME": str(tmp_path / "state"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "XDG_RUNTIME_DIR": str(tmp_path / "run"),
    }


def test_version_file_and_hypr_init_agree():
    ver = (ROOT / "VERSION").read_text().strip()
    assert ver == "0.2.0"
    assert (ROOT / "CHANGELOG.md").is_file()
    lua_code = f"""
package.path = '{ROOT}/hypr/?.lua;' .. package.path
_G.KUWAI_ROOT = '{ROOT}'
_G.hl = setmetatable({{}}, {{ __index = function() return function() end end }})
local K = dofile('{ROOT}/hypr/kuwai/core.lua')
local v = (K.read_line(K.root .. '/VERSION') or ''):gsub('%s+$', '')
assert(v == '{ver}', 'got ' .. v)
print('ver_ok')
"""
    r = subprocess.run(["lua", "-e", lua_code], capture_output=True, text=True, timeout=10)
    assert r.returncode == 0 and "ver_ok" in r.stdout, r.stdout + r.stderr


def test_kuwai_webapp_install_list_remove_and_rejects_bad_urls(tmp_path):
    env = isolated_env(tmp_path)
    env["KUWAI_WEBAPP_BROWSER"] = "chromium"

    r = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-webapp"), "install", "Linear App", "https://linear.app/inbox"],
        env=env, capture_output=True, text=True, timeout=10,
    )
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert d["slug"] == "linear-app"
    desktop = Path(d["desktop"])
    assert desktop.is_file()
    body = desktop.read_text()
    assert 'StartupWMClass=kuwai-webapp-linear-app' in body
    assert '--app="https://linear.app/inbox"' in body

    listed = json.loads(
        subprocess.run([sys.executable, str(ROOT / "bin/kuwai-webapp"), "list"], env=env, capture_output=True, text=True, check=True).stdout
    )
    assert len(listed) == 1 and listed[0]["slug"] == "linear-app"

    bad = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-webapp"), "install", "Bad", "javascript:alert(1)"],
        env=env, capture_output=True, text=True, timeout=10,
    )
    assert bad.returncode != 0

    bad2 = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-webapp"), "install", "Bad2", "https://example.com\nExec=sh"],
        env=env, capture_output=True, text=True, timeout=10,
    )
    assert bad2.returncode != 0

    rem = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-webapp"), "remove", "Linear App"],
        env=env, capture_output=True, text=True, check=True,
    )
    assert json.loads(rem.stdout)["removed"] is True and not desktop.exists()


def test_kuwai_profile_export_redacts_secrets_and_diffs(tmp_path):
    env = isolated_env(tmp_path)
    cfg = tmp_path / "config/kuwai"
    cfg.mkdir(parents=True)
    (cfg / "settings.json").write_text(json.dumps({
        "bar": "island",
        "apiToken": "super-secret-value",
        "nested": {"github_secret": "nope", "safeKey": 42},
    }))
    look_state = tmp_path / "state/kuwai/look"
    look_state.mkdir(parents=True)
    (look_state / "state.json").write_text(json.dumps({"theme": "aurora", "mode": "dark"}))

    manifest = tmp_path / "manifest.json"
    r = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-profile"), "export", str(manifest)],
        env=env, capture_output=True, text=True, timeout=20,
    )
    assert r.returncode == 0, r.stderr
    data = json.loads(manifest.read_text())
    assert data["schema"] == 1 and data["kuwaiVersion"] == "0.2.0"
    assert data["settings"]["bar"] == "island"
    assert "apiToken" not in data["settings"]
    assert "github_secret" not in data["settings"]["nested"]
    assert data["look"] == {"theme": "aurora", "mode": "dark"}

    data["packages"]["repo"].append("nonexistent-pkg-xyz")
    data["settings"]["bar"] = "waybar"
    manifest.write_text(json.dumps(data))

    rd = subprocess.run(
        [sys.executable, str(ROOT / "bin/kuwai-profile"), "diff", str(manifest)],
        env=env, capture_output=True, text=True, timeout=20,
    )
    assert rd.returncode == 0, rd.stderr
    diff = json.loads(rd.stdout)
    assert "nonexistent-pkg-xyz" in diff["missingRepo"]
    assert diff["settingsDiff"]["bar"] == {"saved": "waybar", "current": "island"}


def test_kuwai_ctl_has_rollback_update_self_and_clean_usage():
    r = subprocess.run([str(ROOT / "bin/kuwai-ctl"), "--help"], capture_output=True, text=True, timeout=10)
    out = r.stdout + r.stderr
    for cmd in ("kuwai look", "kuwai webapp", "kuwai export", "kuwai rollback", "kuwai update-self"):
        assert cmd in out
    assert (ROOT / "tests/vm/test-arch-container.sh").is_file()
