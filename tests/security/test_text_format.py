"""No text element may decide for itself that a string is markup.

Qt's Text defaults to AutoText: a string that looks like HTML is rendered as
HTML, and an <img src="https://…"> in it is fetched. Song titles, window and
tab titles, device names, tool output and model answers all reach the shell
from outside it. Every bare `Text` whose text isn't a fixed string must say
what it is (`textFormat:`); components/Label.qml is PlainText already.
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HEAD = re.compile(r"^(\s*)(?:\w+: *)?Text \{(.*)$")
LITERAL = re.compile(r"""("([^"\\]|\\.)*"|'[^']*')\s*(;.*)?""")


def undeclared(path):
    lines = path.read_text().split("\n")
    for i, line in enumerate(lines):
        m = HEAD.match(line)
        if not m:
            continue
        indent, rest = len(m.group(1)), m.group(2)
        if rest.strip().endswith("}") and rest.count("{") + 1 == rest.count("}"):
            block = rest
        else:
            body, j = [rest], i + 1
            while j < len(lines) and not re.match(r"^\s{%d}\}" % indent, lines[j]):
                body.append(lines[j])
                j += 1
            block = "\n".join(body)
        t = re.search(r"\btext: *(.*)", block)
        if t and "textFormat" not in block and not LITERAL.fullmatch(t.group(1).strip()):
            yield f"{path.relative_to(REPO)}:{i + 1}"


def test_every_dynamic_text_declares_its_format():
    found = [hit for d in ("shell", "shell-auth") for f in sorted((REPO / d).rglob("*.qml")) for hit in undeclared(f)]
    assert not found, "Text with outside text and no textFormat (use Label, or textFormat: Text.PlainText):\n" + "\n".join(found)


def test_label_is_plain_text():
    assert "textFormat: Text.PlainText" in (REPO / "shell/components/Label.qml").read_text()
