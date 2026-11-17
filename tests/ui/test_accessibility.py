"""Everything a pointer can do in the shell, a screen reader can find and do.

Every pointer handler (`MouseArea {`, `TapHandler {`) in shell/ and shell-auth/
that acts on a press acts on an item: the handler itself, or its parent when
the handler fills it (a TapHandler always acts on its parent). That item must
say what it is and what it's called (`Accessible.role` and `Accessible.name`),
or say it is decoration that forwards to a named neighbour
(`Accessible.ignored: true`). Handlers that only hover, swallow a click or
scroll a view don't act and aren't counted.

The ratchet: tests/ui/accessibility-baseline.txt lists the handlers left
unnamed, each with a reason. A new unnamed handler fails; so does a baseline
line that no longer matches (the list only shrinks).

Second guard: every `Accessible.<property>` and `Accessible.<Role>` the shell
uses is set on a real item under Qt's own qml runner, offscreen. Panels
compile when first opened, so a misspelt attached property would otherwise
only fail on the owner's desktop.

Run as a script for the inventory: python tests/ui/test_accessibility.py [-v]
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("accessibility-baseline.txt")
ROOTS = ("shell", "shell-auth")
HANDLERS = ("MouseArea", "TapHandler")
ACTS = re.compile(r"\bon(Clicked|Pressed|Released|DoubleClicked|PressAndHold|Tapped|SingleTapped|DoubleTapped|LongPressed)\s*:\s*(.*)")
SWALLOW = re.compile(r"^(\{\s*\}|\w+\s*=>\s*\{?\s*\w+\.accepted\s*=\s*(true|false)\s*;?\s*\}?|\(\)\s*=>\s*\{\s*\}|;?)\s*;?\s*(\}.*)?$")


def blank(src):
    """Comments and string contents become spaces; line numbers stay."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j])); i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            body = src[i + 1:j]
            out.append(c + "".join(ch if ch == "\n" else "_" for ch in body) + c); i = j + 1
        else:
            out.append(c); i += 1
    return "".join(out)


OBJECT_HEAD = re.compile(r"(?:^|[\s;{}:])((?:[a-z]\w*\.)*[A-Z]\w*)(?:\s+on\s+[\w.]+)?\s*$")


class Obj:
    def __init__(self, typ, line, parent):
        self.type, self.line, self.parent = typ, line, parent
        self.own, self.children = [], []
        self.id = None

    def text(self):
        return "".join(self.own)

    def chain_id(self):
        o = self
        while o is not None:
            if o.id:
                return o.id
            o = o.parent
        return "root"


def parse(src):
    """A QML file as a tree of objects; each object's own text excludes its children."""
    text = blank(src)
    root = Obj("<file>", 0, None)
    stack = [root]             # objects and JS blocks (None) in order
    objs = []
    line, seg = 1, 0
    owner = lambda: next(o for o in reversed(stack) if o is not None)
    for i, c in enumerate(text):
        if c == "{":
            owner().own.append(text[seg:i + 1])
            seg = i + 1
            start = max(text.rfind("\n", 0, i), text.rfind(";", 0, i), text.rfind("{", 0, i), text.rfind("}", 0, i))
            head = text[start + 1:i]
            m = OBJECT_HEAD.search(head)
            # "prop: Type {" is an object; "onX: {" and "=> {" are code.
            if m and not re.search(r"(=>|\)|\bfunction\b[^{]*)\s*$", head):
                o = Obj(m.group(1).split(".")[-1], line, owner())
                owner().children.append(o)
                stack.append(o); objs.append(o)
            else:
                stack.append(None)
        elif c == "}":
            owner().own.append(text[seg:i])
            seg = i
            if len(stack) > 1:
                stack.pop()
        elif c == "\n":
            line += 1
    for o in objs:
        m = re.search(r"(?:^|[\s;{])id\s*:\s*(\w+)", o.text())
        o.id = m.group(1) if m else None
    return objs


def acts(handler):
    """Does this handler do something on a press (not just hover, swallow or scroll)?"""
    t = handler.text()
    if handler.type == "MouseArea" and re.search(r"\bdrag\.target\s*:", t):
        return True
    for m in ACTS.finditer(t):
        if not SWALLOW.match(m.group(2).strip()):
            return True
    if handler.type == "TapHandler" and not ACTS.search(t):
        return False
    return False


def target(handler):
    """The item a handler acts for: its parent when it fills the parent or a
    sibling (the hit area of the drawn part), else the handler itself."""
    if handler.type == "TapHandler":
        return handler.parent
    near = [handler.parent.id] + [c.id for c in handler.parent.children if c is not handler]
    parent = r"(parent|" + "|".join(re.escape(i) for i in near if i) + r")\b"
    if re.search(r"\banchors\.fill\s*:\s*" + parent, handler.text()) or re.search(r"\banchors\s*\{[^}]*\bfill\s*:\s*" + parent, handler.text()):
        return handler.parent
    return handler


# Roles that hold other things: their handler closes or steps back (a scrim, a
# backdrop), and the way to do that is the named button or key beside it.
CONTAINERS = ("Pane", "Dialog", "PopupMenu", "Grouping")


def declared(item):
    """Role, name and a way to act (press, toggle, increase), or a container role,
    or `Accessible.ignored: true`."""
    t = item.text()
    if re.search(r"\bAccessible\.ignored\s*:\s*true\b", t):
        return True
    role = re.search(r"\bAccessible\.role\s*:\s*(.*)", t)
    if not role or not re.search(r"\bAccessible\.name\s*:", t):
        return False
    if re.search(r"\bAccessible\.on(Press|Toggle|Increase)Action\s*:", t):
        return True
    return re.fullmatch(r"Accessible\.(%s)\s*;?\s*" % "|".join(CONTAINERS), role.group(1).strip()) is not None


def inventory():
    """[(key, path:line, acts, named)] for every pointer handler."""
    rows = []
    for d in ROOTS:
        for f in sorted((REPO / d).rglob("*.qml")):
            rel = f.relative_to(REPO).as_posix()
            seen = {}
            for h in parse(f.read_text()):
                if h.type not in HANDLERS:
                    continue
                t = target(h)
                stem = f"{rel}#{h.id or t.chain_id()}:{h.type}"
                seen[stem] = seen.get(stem, 0) + 1
                key = f"{stem}:{seen[stem]}"
                rows.append((key, f"{rel}:{h.line}", acts(h), declared(t) or declared(h)))
    return rows


def load_baseline():
    out = {}
    for n, line in enumerate(BASELINE.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, reason = line.partition(" # ")
        out[key.strip()] = (reason.strip(), n)
    return out


def test_every_acting_pointer_handler_is_named():
    base = load_baseline()
    rows = inventory()
    missing = [(k, where) for k, where, a, named in rows if a and not named]
    new = [f"{where}  ({k})" for k, where in missing if k not in base]
    assert not new, ("Pointer handlers whose item has no Accessible.role + Accessible.name "
                     "(or Accessible.ignored: true when it forwards to a named item):\n" + "\n".join(new))


def test_baseline_only_shrinks():
    base = load_baseline()
    unnamed = {k for k, _, a, named in inventory() if a and not named}
    stale = [f"line {n}: {k}" for k, (_, n) in base.items() if k not in unnamed]
    assert not stale, "Named now (or gone): remove from accessibility-baseline.txt:\n" + "\n".join(stale)
    reasonless = [f"line {n}: {k}" for k, (r, n) in base.items() if not r]
    assert not reasonless, "Every baseline line needs ' # <reason>':\n" + "\n".join(reasonless)


def test_parser_finds_the_known_patterns():
    objs = parse("""Item {
    id: card
    Accessible.role: Accessible.Button
    Accessible.name: "Close {x}"
    Accessible.onPressAction: go()
    onClicked: { if (a) { b() } }
    MouseArea { anchors.fill: parent; onClicked: card.go() }
    Rectangle { TapHandler { onTapped: x() } }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true }
    MouseArea { anchors.fill: parent; onClicked: {} }
    Behavior on x { NumberAnimation {} }
}
""")
    hs = [o for o in objs if o.type in HANDLERS]
    assert [h.type for h in hs] == ["MouseArea", "TapHandler", "MouseArea", "MouseArea"]
    assert declared(target(hs[0])) and target(hs[0]).id == "card"
    assert acts(hs[0]) and acts(hs[1]) and not acts(hs[2]) and not acts(hs[3])
    assert target(hs[1]).type == "Rectangle" and not declared(target(hs[1]))
    assert {o.type for o in objs} >= {"Behavior", "NumberAnimation"}


# --- every Accessible.* the shell uses exists in this Qt --------------------

QML = shutil.which("qml6") or next((p for p in ("/usr/lib/qt6/bin/qml",) if os.access(p, os.X_OK)), None)
USE = re.compile(r"\bAccessible\.([a-zA-Z]\w*)")
SIGNALS = {"onPressAction", "onToggleAction", "onIncreaseAction", "onDecreaseAction",
           "onScrollUpAction", "onScrollDownAction", "onScrollLeftAction", "onScrollRightAction",
           "onPreviousPageAction", "onNextPageAction", "onShowOnScreenAction"}


def used_names():
    props, roles = set(), set()
    for d in ROOTS:
        for f in (REPO / d).rglob("*.qml"):
            for name in USE.findall(blank(f.read_text())):
                (roles if name[0].isupper() else props).add(name)
    return props, roles


@pytest.mark.skipif(QML is None, reason="Qt's qml runner is not installed")
def test_every_accessible_name_used_exists_in_qt():
    props, roles = used_names()
    values = {"role": "Accessible.Button", "name": '"n"', "description": '"d"', "id": '"i"'}
    lines = []
    for p in sorted(props):
        if p in SIGNALS:
            lines.append(f"Accessible.{p}: {{}}")
        elif p not in ("labelledBy", "labelFor"):
            lines.append(f"Accessible.{p}: {values.get(p, 'true')}")
    checks = " && ".join(f"typeof Accessible.{r} === 'number'" for r in sorted(roles)) or "true"
    qml = ("import QtQuick\nItem {\n    " + "\n    ".join(lines) +
           f"\n    Component.onCompleted: {{ console.log(({checks}) ? 'A11Y_OK' : 'A11Y_BAD_ROLE'); Qt.quit() }}\n}}\n")
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "probe.qml"
        probe.write_text(qml)
        env = {"PATH": "/usr/bin:/bin", "HOME": tmp, "QT_QPA_PLATFORM": "offscreen", "QT_FORCE_STDERR_LOGGING": "1"}
        out = subprocess.run([QML, str(probe)], env=env, capture_output=True, text=True, timeout=30)
    log = out.stdout + out.stderr
    assert "A11Y_OK" in log, f"Accessible names that Qt doesn't have ({sorted(props)}, roles {sorted(roles)}):\n{log}\n{qml}"


if __name__ == "__main__":
    rows = inventory()
    acting = [r for r in rows if r[2]]
    named = [r for r in acting if r[3]]
    print(f"pointer handlers: {len(rows)}; acting: {len(acting)}; named: {len(named)}; unnamed: {len(acting) - len(named)}")
    files = {r[1].split(':')[0] for r in rows}
    print(f"files with handlers: {len(files)}")
    if "-v" in sys.argv:
        for key, where, a, n in rows:
            print(f"{'ok ' if n else ('-- ' if not a else 'NO ')} {where:60} {key}")
