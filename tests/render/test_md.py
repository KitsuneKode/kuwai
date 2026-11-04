"""bin/rice_md.py: chat Markdown → Qt rich text, Streamdown-style."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import rice_md as md  # noqa: E402


def test_bold_line_and_list_right_under_it():
    h = md.render("**Web & Information:**\n- Search\n- Read")
    assert h == '<p><b>Web &amp; Information:</b></p><ul style="-qt-list-indent: 1"><li>Search</li><li>Read</li></ul>'


def test_nested_and_numbered_lists():
    h = md.render("1. One\n   - sub\n2. Two")
    assert h == ('<ol style="-qt-list-indent: 1"><li>One<ul style="-qt-list-indent: 2"><li>sub</li></ul></li>'
                 '<li>Two</li></ol>')


def test_loose_list_stays_one_list():
    assert md.render("- a\n\n- b").count("<ul") == 1


def test_inline_code_is_not_formatted():
    assert md.render("use `**not bold**` here") == "<p>use <code>**not bold**</code> here</p>"


def test_links_and_bare_urls():
    h = md.render("see [docs](https://a.b/c) or https://x.y/z.")
    assert '<a href="https://a.b/c">docs</a>' in h and '<a href="https://x.y/z">https://x.y/z</a>.' in h


def test_table_alignment():
    h = md.render("| a | b |\n|:-:|--:|\n| 1 | 2 |")
    assert '<th align="center">a</th>' in h and '<td align="right">2</td>' in h


def test_html_is_escaped():
    assert md.render("<script>x</script>") == "<p>&lt;script&gt;x&lt;/script&gt;</p>"


def test_line_breaks_kept_in_prose():
    assert md.render("line one\nline two") == "<p>line one<br>line two</p>"


def test_heal_closes_open_markup():
    assert md.heal("so **bold") == "so **bold**"
    assert md.heal("run `ls") == "run `ls`"
    assert md.heal("see [the docs](https://exa") == "see the docs"
    assert md.heal("a ~~gone") == "a ~~gone~~"
    assert md.heal("done **ok** and *fine*") == "done **ok** and *fine*"


def test_math_star_is_not_emphasis():
    assert md.render("5 * 3 = 15") == "<p>5 * 3 = 15</p>"
    assert md.heal("5 * 3") == "5 * 3"
