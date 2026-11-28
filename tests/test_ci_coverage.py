"""What CI lints and type-checks covers every place the code lives, so a new folder or a module that
declares itself checked cannot sit outside the gate."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIPPED = {"refs", "node_modules", ".git", ".worktrees", "tests", "site", "packages", "sandbox"}


def test_qmllint_reaches_every_folder_that_has_qml():
    workflow = (ROOT / ".github/workflows/shell-check.yml").read_text()
    line = next(l for l in workflow.splitlines() if "find " in l and "*.qml" in l)
    linted = set(re.search(r"find (.*?) -name", line).group(1).split())
    holders = {p.relative_to(ROOT).parts[0] for p in ROOT.glob("*/**/*.qml") if p.relative_to(ROOT).parts[0] not in SKIPPED}
    assert holders <= linted, f"qmllint skips {sorted(holders - linted)}"
    assert {"shell", "shell-auth", "shell-saver", "greeter"} <= linted


def test_every_module_that_says_ts_check_is_in_the_type_check():
    text = re.sub(r"^\s*//.*$", "", (ROOT / "tsconfig.check.json").read_text(), flags=re.M)
    files = set(json.loads(text)["files"])
    declared = {str(p.relative_to(ROOT)) for p in (ROOT / "shell").rglob("*.mjs")
                if not p.name.endswith(".test.mjs") and p.read_text()[:200].lstrip().startswith("// @ts-check")}
    assert declared <= files, f"declared checked but not in tsconfig.check.json: {sorted(declared - files)}"
