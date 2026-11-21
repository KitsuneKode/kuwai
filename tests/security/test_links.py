"""A link from outside the shell opens only once it is known to be the web.

xdg-open hands a file:// path or an app's own scheme (vscode://, t3code://)
to whatever claims it. A panel that opens a link it read from a helper, a
feed or a reply goes through services/links.mjs (`Links.safeLink`) first.
This finds the shape that skipped it before: a link taken from data
(`modelData.link`, `….url`) passed straight to xdg-open or
Qt.openUrlExternally, or Apps.open (which hands it to xdg-open).
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OPENS = re.compile(r"""(?:execDetached\(\[\s*"xdg-open",\s*|openUrlExternally\(|Apps\.open\()\s*([\w.]+(?:\.(?:link|url|href))\b)""")


def unchecked(path):
    for i, line in enumerate(path.read_text().split("\n"), 1):
        for m in OPENS.finditer(line):
            if "safeLink(" not in line and "webLink(" not in line:
                yield f"{path.relative_to(REPO)}:{i}: {m.group(1)}"


def test_links_from_data_are_checked_before_they_open():
    found = [hit for f in sorted((REPO / "shell").rglob("*.qml")) for hit in unchecked(f)]
    assert not found, "a link from data opened without Links.safeLink:\n" + "\n".join(found)
