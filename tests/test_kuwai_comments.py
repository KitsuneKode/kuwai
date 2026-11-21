"""Unit tests for bin/kuwai-comments lexers, exemptions, and ratchet behavior."""
import importlib.machinery
import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def load_linter():
    path = str(REPO / "bin" / "kuwai-comments")
    loader = importlib.machinery.SourceFileLoader("kuwai_comments", path)
    spec = importlib.util.spec_from_loader("kuwai_comments", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_python_scanner_exempts_shebang_directives_and_docstrings():
    m = load_linter()
    src = (
        "#!/usr/bin/env python3\n"
        '"""Module docstring."""\n'
        "# real comment\n"
        "x = '# not a comment'  # inline comment\n"
        "y = 1  # noqa: E501\n"
        "z = 2  # type: ignore[arg-type]\n"
    )
    hits = m.scan_py(src)
    assert [(h["start_line"], h["standalone"], h["text"]) for h in hits] == [
        (3, True, "# real comment"),
        (4, False, "# inline comment"),
    ]


def test_cstyle_scanner_handles_strings_regexes_jsdoc_and_directives():
    m = load_linter()
    src = (
        "#!/usr/bin/env bun\n"
        "/**\n"
        " * @param {string} x\n"
        " * @returns {boolean}\n"
        " */\n"
        "export function ok(x) {\n"
        "  const url = 'https://example.com//not-a-comment';\n"
        "  const re = /^https?:\\/\\/foo/i;\n"
        "  // real line comment\n"
        "  /* block\n"
        "     comment */\n"
        "  // eslint-disable-next-line\n"
        "  return re.test(x) && url.length > 0; // trailing\n"
        "}\n"
    )
    hits = m.scan_cstyle(src, allow_js_regex=True)
    assert [(h["start_line"], h["end_line"], h["standalone"]) for h in hits] == [
        (9, 9, True),
        (10, 11, True),
        (13, 13, False),
    ]


def test_lua_scanner_handles_long_strings_and_long_comments():
    m = load_linter()
    src = (
        "local s = [[-- not a comment]]\n"
        "-- line comment\n"
        "--[[\n"
        "  block comment\n"
        "]]\n"
        "-- luacheck: ignore\n"
        "return s -- inline\n"
    )
    hits = m.scan_lua(src)
    assert [(h["start_line"], h["end_line"], h["standalone"]) for h in hits] == [
        (2, 2, True),
        (3, 5, True),
        (7, 7, False),
    ]


def test_sh_scanner_handles_heredocs_param_expansion_and_directives():
    m = load_linter()
    src = (
        "#!/usr/bin/env bash\n"
        "# shellcheck disable=SC2034\n"
        "# real comment\n"
        'n=${#foo}\n'
        'url="http://a#b"\n'
        "cat <<'EOF'\n"
        "# inside heredoc\n"
        "EOF\n"
        "echo ok # trailing\n"
    )
    hits = m.scan_sh(src)
    assert [(h["start_line"], h["standalone"], h["text"]) for h in hits] == [
        (3, True, "# real comment"),
        (9, False, "# trailing"),
    ]


def test_ratchet_blocks_new_comments_and_never_raises_baseline(tmp_path, monkeypatch):
    m = load_linter()
    base_file = tmp_path / "comments-baseline.json"
    monkeypatch.setattr(m, "BASE", str(base_file))
    m.save_baseline({"a.py": 3})
    loaded = m.load_baseline()
    assert loaded == {"a.py": 3}

    now = {"a.py": 2, "b.py": 1}
    new_base = {p: min(n, loaded.get(p, 0)) for p, n in now.items()}
    saved = m.save_baseline(new_base)
    assert saved["files"] == {"a.py": 2}
