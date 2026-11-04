"""Markdown → Qt rich text for chat answers, after Vercel's Streamdown: made for
text that is still being written. Stdlib only.

- Repairs half-written markup like Streamdown's `remend`: an unclosed `**`,
  `*`, `_`, `~~` or `` ` `` is closed, a link still being typed shows as text.
- Reads Markdown the way models write it: a list or a heading straight after
  a line (no blank line), single newlines kept as line breaks in prose.
- GFM: headings, bold / italic / strikethrough, inline code, links and bare
  URLs, nested bullet and numbered lists, task items, quotes, tables, rules.
- Output is the HTML subset Qt's QTextDocument draws (no CSS layout tricks).

render(text) -> html (a fragment; the caller adds the stylesheet).
"""
import html
import re

_URL = re.compile(r"(?<![\"'=(\[/])\b(https?://[^\s<>()\[\]`]+[^\s<>()\[\]`.,;:!?'\"*_])")
_BULLET = re.compile(r"^(\s*)([-*+])\s+(.*)$")
_NUMBER = re.compile(r"^(\s*)(\d{1,3})[.)]\s+(.*)$")
_HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_RULE = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")


# ── Repair (Streamdown's remend) ─────────────────────────────────────────

def heal(text):
    """Close what a half-written answer leaves open, so it renders as meant."""
    t = text
    # A link being typed: "[label](http…" or "[label" → just the label.
    t = re.sub(r"\[([^\]\n]*)\]\([^)\n]*$", r"\1", t)
    t = re.sub(r"\[([^\]\n]*)$", r"\1", t)
    if t.count("`") % 2:
        t += "`"
    bare = re.sub(r"`[^`]*`", "", t)
    if bare.count("**") % 2:
        t = t.rstrip() + "**"
        bare += "**"
    if bare.count("~~") % 2:
        t = t.rstrip() + "~~"
    single = re.sub(r"\*\*", "", bare)
    if len(re.findall(r"(?<![\w*])\*(?=\S)|(?<=\S)\*(?![\w*])", single)) % 2:
        t = t.rstrip() + "*"
    return t


# ── Inline ───────────────────────────────────────────────────────────────

def inline(s):
    codes = []

    def keep_code(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    s = re.sub(r"`([^`]+)`", keep_code, s)
    links = []

    def keep_link(m):
        links.append((m.group(1), m.group(2)))
        return f"\x01{len(links) - 1}\x01"

    s = re.sub(r"\[([^\]]+)\]\((\S+?)(?:\s+\"[^\"]*\")?\)", keep_link, s)
    s = html.escape(s, quote=False)
    s = _URL.sub(lambda m: f'<a href="{m.group(1)}">{m.group(1)}</a>', s)
    s = re.sub(r"\*\*(?=\S)(.+?)(?<=\S)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<![\w])__(?=\S)(.+?)(?<=\S)__(?![\w])", r"<b>\1</b>", s)
    s = re.sub(r"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])", r"<i>\1</i>", s)
    s = re.sub(r"(?<![\w])_(?=\S)(.+?)(?<=\S)_(?![\w])", r"<i>\1</i>", s)
    s = re.sub(r"~~(?=\S)(.+?)(?<=\S)~~", r"<s>\1</s>", s)
    s = re.sub(r"\x01(\d+)\x01", lambda m: '<a href="{1}">{0}</a>'.format(
        inline(links[int(m.group(1))][0]), html.escape(links[int(m.group(1))][1], quote=True)), s)
    s = re.sub(r"\x00(\d+)\x00", lambda m: "<code>" + html.escape(codes[int(m.group(1))], quote=False) + "</code>", s)
    return s


# ── Blocks ───────────────────────────────────────────────────────────────

def _cells(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def _table(rows, aligns):
    out = ['<table width="100%" cellspacing="0" cellpadding="0">']
    for r, cells in enumerate(rows):
        tag = "th" if r == 0 else "td"
        out.append("<tr>" + "".join(
            f'<{tag} align="{aligns[i] if i < len(aligns) else "left"}">{inline(c)}</{tag}>'
            for i, c in enumerate(cells)) + "</tr>")
    out.append("</table>")
    return "".join(out)


def _list(items):
    """items: [(indent, ordered, start, text)] → nested <ul>/<ol>."""
    out, stack = [], []          # stack of (indent, tag)
    for indent, ordered, start, text in items:
        tag = "ol" if ordered else "ul"
        while stack and indent < stack[-1][0]:
            out.append(f"</li></{stack.pop()[1]}>")
        if not stack or indent > stack[-1][0]:
            attr = f' start="{start}"' if ordered and start != 1 else ""
            # Qt nests by -qt-list-indent, not by the HTML nesting: one level each.
            out.append(f'<{tag}{attr} style="-qt-list-indent: {len(stack) + 1}">')
            stack.append((indent, tag))
        else:
            out.append("</li>")
        box = re.match(r"\[([ xX])\]\s+(.*)$", text)
        if box:
            text = ("☑ " if box.group(1).lower() == "x" else "☐ ") + box.group(2)
        out.append("<li>" + inline(text))
    while stack:
        out.append(f"</li></{stack.pop()[1]}>")
    return "".join(out)


def render(text):
    lines = text.replace("\r\n", "\n").split("\n")
    out, para, items, quote = [], [], [], []
    i = 0

    def flush_para():
        if para:
            out.append("<p>" + "<br>".join(inline(l.strip()) for l in para) + "</p>")
            para.clear()

    def flush_list():
        if items:
            out.append(_list(items))
            items.clear()

    def flush_quote():
        if quote:
            out.append("<blockquote>" + render("\n".join(quote)) + "</blockquote>")
            quote.clear()

    while i < len(lines):
        line = lines[i]
        if not line.strip():
            flush_para()
            flush_quote()
            # A blank line inside a list doesn't end it if the list carries on.
            nxt = next((l for l in lines[i + 1:] if l.strip()), "")
            if items and (_BULLET.match(nxt) or _NUMBER.match(nxt)):
                i += 1
                continue
            flush_list()
            i += 1
            continue
        if line.lstrip().startswith(">"):
            flush_para()
            flush_list()
            quote.append(re.sub(r"^\s*>\s?", "", line))
            i += 1
            continue
        flush_quote()
        h = _HEAD.match(line)
        if h:
            flush_para()
            flush_list()
            level = min(len(h.group(1)), 4)
            out.append(f"<h{level}>{inline(h.group(2))}</h{level}>")
            i += 1
            continue
        if _RULE.match(line) and not para:
            flush_list()
            out.append("<hr>")
            i += 1
            continue
        if "|" in line and i + 1 < len(lines) and _TABLE_SEP.match(lines[i + 1]):
            flush_para()
            flush_list()
            aligns = []
            for c in _cells(lines[i + 1]):
                aligns.append("center" if c.startswith(":") and c.endswith(":") else "right" if c.endswith(":") else "left")
            rows = [_cells(line)]
            i += 2
            while i < len(lines) and "|" in lines[i] and lines[i].strip():
                rows.append(_cells(lines[i]))
                i += 1
            out.append(_table(rows, aligns))
            continue
        b, n = _BULLET.match(line), _NUMBER.match(line)
        if b or n:
            flush_para()            # models put a list right under a line: that starts a list
            m = b or n
            items.append((len(m.group(1).expandtabs(4)), bool(n), int(n.group(2)) if n else 1, m.group(3)))
            i += 1
            continue
        if items and line.startswith(("  ", "\t")):
            ind, o, st, t = items[-1]
            items[-1] = (ind, o, st, t + " " + line.strip())
            i += 1
            continue
        flush_list()
        para.append(line)
        i += 1
    flush_para()
    flush_list()
    flush_quote()
    return "".join(out)
