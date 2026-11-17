"""Every Theme.<name> the shell uses is declared in shell/config/Theme.qml.

A misspelt token in a panel isn't an error: panels compile when first opened
(the offscreen load test never reaches them) and a missing property reads as
`undefined`, so a size falls to 0 or a duration to an instant cut with no
message. The same goes for the keys of Theme's map tokens (Theme.duskPalette.sky).
Also: no property is declared twice (two workers once each added `undoMs`; a
duplicate stops the whole shell loading).
"""
import re
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "shell"
THEME = SHELL / "config" / "Theme.qml"

# Theme's own members sit one level in (4 spaces); deeper ones belong to its
# FileViews and adapters and aren't reachable as Theme.<name>.
DECL = re.compile(r"^ {4}(?:readonly\s+)?property\s+[\w.<>]+\s+(\w+)\b", re.M)
FUNC = re.compile(r"^ {4}function\s+(\w+)\s*\(", re.M)
USE = re.compile(r"(?<![\w.])Theme\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?")
MAP = re.compile(r"^ {4}readonly\s+property\s+var\s+(\w+)\s*:\s*\(\{(.*?)\}\)", re.M | re.S)
KEY = re.compile(r"(?:^|[{,])\s*([A-Za-z_]\w*)\s*:")
# Members every QML object has (Theme is a Singleton); not tokens.
BUILTIN = {"objectName", "toString", "destroy"}


def strip_comments(text):
    """Drop // comments (outside strings) so prose about a token isn't a use."""
    out = []
    for line in text.split("\n"):
        q = None
        for i, ch in enumerate(line):
            if q:
                if ch == "\\":
                    continue
                if ch == q:
                    q = None
            elif ch in "\"'`":
                q = ch
            elif line.startswith("//", i):
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def theme():
    text = strip_comments(THEME.read_text(encoding="utf-8"))
    names = DECL.findall(text)
    maps = {}
    for name, body in MAP.findall(text):
        # Top-level keys only: drop nested arrays/objects before reading keys.
        flat, depth = [], 0
        for ch in body:
            if ch in "[{(":
                depth += 1
            elif ch in "]})":
                depth -= 1
            elif depth == 0:
                flat.append(ch)
        maps[name] = set(KEY.findall("".join(flat)))
    return names, set(FUNC.findall(text)), maps


def uses():
    for path in sorted(SHELL.rglob("*")):
        if path.suffix not in {".qml", ".js", ".mjs"} or path == THEME:
            continue
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for m in USE.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            yield path.relative_to(ROOT), line, m.group(1), m.group(2)


class ThemeNames(unittest.TestCase):
    def test_no_property_is_declared_twice(self):
        names, _, _ = theme()
        twice = sorted(n for n, k in Counter(names).items() if k > 1)
        self.assertEqual(twice, [], "declared more than once in Theme.qml")

    def test_every_theme_name_used_exists(self):
        names, funcs, _ = theme()
        known = set(names) | funcs | BUILTIN
        missing = [f"{p}:{n}  Theme.{name}" for p, n, name, _ in uses() if name not in known]
        self.assertEqual(missing, [], "not declared in shell/config/Theme.qml")

    def test_every_map_key_used_exists(self):
        _, _, maps = theme()
        missing = [f"{p}:{n}  Theme.{name}.{key}" for p, n, name, key in uses()
                   if key and name in maps and maps[name] and key not in maps[name]]
        self.assertEqual(missing, [], "not a key of that Theme map")

    def test_the_guard_reads_theme(self):
        names, funcs, maps = theme()
        # If the patterns stop matching, the tests above pass vacuously.
        self.assertIn("pressMs", names)
        self.assertIn("tracking", funcs)
        self.assertIn("sky", maps.get("duskPalette", set()))


if __name__ == "__main__":
    unittest.main()
