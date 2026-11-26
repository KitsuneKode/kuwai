"""An EXIT trap never names a function's own variable.

The trap runs when the script ends, after the function has returned, so a
`local` it names is gone: under `set -u` the script fails on its last line
("src: unbound variable") and the temporary it meant to remove stays behind.
greeter/install did this after every install. Such a trap carries the value,
expanded when it is set: trap "rm -rf -- $(printf %q "$dir")" EXIT.
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TRAP = re.compile(r"""trap\s+'([^']*)'\s+EXIT""")
LOCAL = re.compile(r"""^\s*local\s+(.*)$""")
FUNC = re.compile(r"""^\s*(?:function\s+)?[\w-]+\s*\(\)\s*\{""")


def scripts():
    for d in ("bin", "greeter", "system", "lib"):
        for f in sorted((REPO / d).rglob("*")):
            if f.is_file() and f.read_bytes()[:2] == b"#!":
                head = f.read_text(errors="replace").split("\n", 1)[0]
                if "bash" in head or head.endswith("/sh"):
                    yield f
    if (REPO / "install.sh").exists():
        yield REPO / "install.sh"


def faults(path, root=REPO):
    names: set[str] = set()
    for i, line in enumerate(path.read_text(errors="replace").split("\n"), 1):
        if FUNC.match(line):
            names = set()
        m = LOCAL.match(line)
        if m:
            names |= set(re.findall(r"(?:^|\s)(?:-\w+\s+)*([A-Za-z_]\w*)", m.group(1).split(";")[0]))
        for t in TRAP.finditer(line):
            used = set(re.findall(r"\$\{?([A-Za-z_]\w*)", t.group(1)))
            for name in sorted(used & names):
                yield f"{path.relative_to(root)}:{i}: ${name}"


def test_exit_traps_never_name_a_local():
    found = [hit for f in scripts() for hit in faults(f)]
    assert not found, "an EXIT trap names a function's local, gone by the time it runs:\n" + "\n".join(found)


def test_the_check_finds_the_old_shape(tmp_path):
    f = tmp_path / "x"
    f.write_text("#!/usr/bin/env bash\nset -u\nrun() {\n    local src\n    src=$(mktemp -d)\n    trap 'rm -rf \"$src\"' EXIT\n}\n")
    assert list(faults(f, tmp_path)) == ["x:6: $src"]
