"""File tools for the assistant, after pi's (badlogic/pi-mono coding-agent):
read / write / edit / ls / find / grep, with limits sized for a 16k window
and truncation notes that say exactly what to call next.

Paths: relative ones are the chat's sandbox folder (its own workspace);
`~/…` or `/…` are your files. Reading yours is free (except secrets);
writing or editing yours asks first (the caller handles approval).
"""
import difflib
import os
import re
import shutil
import subprocess
import unicodedata
from pathlib import Path

MAX_LINES = 250
MAX_BYTES = 12_000
LINE_CAP = 400
HOME = Path.home()
# Never read these, even if asked: keys and secrets.
SECRET = [HOME / ".ssh", HOME / ".gnupg", HOME / ".local/share/keyrings", HOME / ".password-store",
          HOME / ".config/rice/secrets", HOME / ".aws", HOME / ".kube", HOME / ".mozilla", HOME / ".zen",
          HOME / ".config/chromium", HOME / ".config/google-chrome", HOME / ".config/BraveSoftware",
          HOME / ".config/gh", HOME / ".docker", HOME / ".gcloud", HOME / ".config/gcloud", HOME / ".azure",
          HOME / ".local/share/kwalletd", HOME / ".pki", HOME / ".cert"]
# Keys, tokens and password stores by name, anywhere.
SECRET_NAME = re.compile(r"(^id_[a-z0-9]+$|\.pem$|\.key$|\.p12$|\.pfx$|^\.env(\..*)?$|^credentials(\.json)?$|\.kdbx$"
                         r"|^\.netrc$|^\.git-credentials$|^\.npmrc$|^\.pypirc$|^cookies(\.sqlite)?$|^login data$"
                         r"|^key[34]\.db$|^logins\.json$|^hosts\.ya?ml$|^auth\.json$|token)", re.I)


class FileError(Exception):
    pass


def resolve(path, sandbox_dir):
    """(absolute Path, is_sandbox). Relative → the sandbox folder."""
    p = str(path or "").strip()
    if not p:
        raise FileError("No path given")
    sb = Path(sandbox_dir).resolve()
    if p.startswith("/work/"):              # the sandbox's own view of its folder
        p = p.split("/", 3)[3] if p.count("/") >= 3 else ""
    if p.startswith("~"):
        full = Path(os.path.expanduser(p)).resolve()
    elif p.startswith("/"):
        full = Path(p).resolve()
    else:
        full = (sb / p).resolve()
    inside = full == sb or sb in full.parents
    return full, inside


def check_readable(full):
    for s in SECRET:
        if full == s or s in full.parents:
            raise FileError(f"{full} holds secrets; it isn't read")
    if SECRET_NAME.search(full.name):
        raise FileError(f"{full.name} looks like a key or secrets file; it isn't read")


def show(full):
    s = str(full)
    h = str(HOME)
    return "~" + s[len(h):] if s.startswith(h) else s


# ── read ─────────────────────────────────────────────────────────────────

def read(full, offset=None, limit=None):
    check_readable(full)
    if full.is_dir():
        raise FileError(f"{show(full)} is a folder; use ls")
    if not full.is_file():
        raise FileError(f"No such file: {show(full)}")
    with open(full, "rb") as f:
        raw = f.read(4_000_000)
    if b"\0" in raw[:8192]:
        raise FileError(f"{show(full)} is a binary file")
    lines = raw.decode("utf-8", errors="replace").split("\n")
    total = len(lines)
    start = max(1, int(offset or 1))
    if start > total:
        raise FileError(f"Offset {start} is beyond end of file ({total} lines total)")
    want = int(limit) if limit else MAX_LINES
    out, size, i = [], 0, start - 1
    while i < total and len(out) < min(want, MAX_LINES):
        line = lines[i]
        if len(line) > LINE_CAP * 4:
            line = line[:LINE_CAP * 4] + " … [line cut]"
        if size + len(line) + 1 > MAX_BYTES and out:
            break
        out.append(line)
        size += len(line) + 1
        i += 1
    text = "\n".join(out)
    end = start + len(out) - 1
    if end < total:
        text += f"\n\n[Showing lines {start}-{end} of {total}. Use offset={end + 1} to continue.]"
    return text


# ── write / edit ─────────────────────────────────────────────────────────

def label(full, sandbox_dir):
    """How to name a path to the model: relative inside its sandbox folder, ~/… outside."""
    sb = Path(sandbox_dir).resolve()
    return str(full.relative_to(sb)) if sb in full.parents else show(full)


def write(full, content, name=None):
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")
    n = content.count("\n") + (1 if content and not content.endswith("\n") else 0)
    return f"Wrote {name or show(full)} ({n} lines)"


def _fold(s):
    """pi's fuzzy match space: NFKC, smart quotes/dashes to ASCII, no trailing spaces."""
    s = unicodedata.normalize("NFKC", s)
    s = s.translate(str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-", " ": " "}))
    return "\n".join(l.rstrip() for l in s.split("\n"))


def _find(text, old):
    """(start, end) of old in text: exact, else line-wise fuzzy; raises on 0 or >1."""
    n = text.count(old)
    if n == 1:
        i = text.index(old)
        return i, i + len(old)
    if n > 1:
        raise FileError(f"Found {n} occurrences of the text. The text must be unique. "
                        "Please provide more context to make it unique.")
    lines, want = text.split("\n"), _fold(old).split("\n")
    folded = [_fold(l) for l in lines]
    hits = [i for i in range(len(lines) - len(want) + 1) if folded[i:i + len(want)] == want]
    if len(hits) != 1:
        if hits:
            raise FileError(f"Found {len(hits)} occurrences of the text. The text must be unique. "
                            "Please provide more context to make it unique.")
        raise FileError("Could not find the exact text. The old text must match exactly including all "
                        "whitespace and newlines; read the file again and copy it.")
    a = sum(len(l) + 1 for l in lines[:hits[0]])
    b = a + sum(len(l) + 1 for l in lines[hits[0]:hits[0] + len(want)]) - 1
    return a, b


def plan_edit(full, edits):
    """The new text for edits [{oldText, newText}], matched against the original
    (not one after another, as pi does). Returns (old, new)."""
    check_readable(full)
    if not full.is_file():
        raise FileError(f"No such file: {show(full)} (use write to create it)")
    text = full.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not edits:
        raise FileError("No edits given")
    spans = []
    for k, e in enumerate(edits):
        old, new = str(e.get("oldText") or ""), str(e.get("newText") or "")
        if not old:
            raise FileError(f"edits[{k}].oldText must not be empty")
        try:
            a, b = _find(text, old.replace("\r\n", "\n"))
        except FileError as err:
            raise FileError(f"edits[{k}] in {show(full)}: {err}")
        spans.append((a, b, new, k))
    spans.sort()
    for (a1, b1, _, k1), (a2, _, _, k2) in zip(spans, spans[1:]):
        if a2 < b1:
            raise FileError(f"edits[{k1}] and edits[{k2}] overlap in {show(full)}. Merge them into one edit.")
    out, last = [], 0
    for a, b, new, _ in spans:
        out.append(text[last:a])
        out.append(new)
        last = b
    out.append(text[last:])
    new_text = "".join(out)
    if new_text == text:
        raise FileError(f"No changes made to {show(full)}: the replacement is the same text.")
    return text, new_text


def diff(full, old, new, limit=4000):
    d = "".join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                     fromfile=show(full), tofile=show(full), n=2))
    return d if len(d) <= limit else d[:limit] + "\n… (diff cut)"


def apply_edit(full, new_text, count, name=None):
    full.write_text(new_text, encoding="utf-8")
    return f"Successfully replaced {count} block(s) in {name or show(full)}."


# ── ls / find / grep ─────────────────────────────────────────────────────

def ls(full, limit=200):
    check_readable(full)
    if not full.is_dir():
        raise FileError(f"Not a folder: {show(full)}")
    names = sorted(full.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    out = [p.name + ("/" if p.is_dir() else "") for p in names[:limit]]
    if len(names) > limit:
        out.append(f"[{len(names) - limit} more. Use limit={len(names)} to see all.]")
    return "\n".join(out) or "(empty folder)"


def find(pattern, full, limit=200):
    check_readable(full)
    fd = shutil.which("fd") or shutil.which("fdfind")
    if fd:
        p = subprocess.run([fd, "--glob", "--color", "never", "--max-results", str(limit + 1), pattern, str(full)],
                           capture_output=True, text=True, timeout=15)
        hits = [l for l in p.stdout.splitlines() if l]
    else:
        hits = [str(x) for x in list(full.rglob(pattern))[:limit + 1]]
    more = len(hits) > limit
    hits = [show(Path(h)) for h in hits[:limit]]
    if not hits:
        return "No files found"
    return "\n".join(hits) + (f"\n[More than {limit} results. Refine the pattern.]" if more else "")


def grep(pattern, full, glob=None, ignore_case=False, literal=False, limit=60):
    check_readable(full)
    rg = shutil.which("rg")
    if not rg:
        raise FileError("ripgrep (rg) isn't installed")
    argv = [rg, "--line-number", "--no-heading", "--color", "never", "--max-columns", str(LINE_CAP),
            "--max-columns-preview", "--glob", "!.git"]
    for s in SECRET:
        argv += ["--glob", f"!{s.name}/**"]
    if ignore_case:
        argv.append("-i")
    if literal:
        argv.append("-F")
    if glob:
        argv += ["--glob", glob]
    argv += ["--", pattern, str(full)]
    p = subprocess.run(argv, capture_output=True, text=True, timeout=20)
    if p.returncode == 2:
        raise FileError(p.stderr.strip()[:300] or "grep failed")
    lines = p.stdout.splitlines()
    h = str(HOME)
    lines = [("~" + l[len(h):]) if l.startswith(h) else l for l in lines]
    more = len(lines) > limit
    out = "\n".join(lines[:limit]) or "No matches"
    if more:
        out += f"\n[{len(lines)} matches, showing {limit}. Use limit={min(len(lines), 300)} for more, or refine the pattern.]"
    return out


# ── command output (Codex's head + tail) ─────────────────────────────────

def head_tail(text, budget=8000):
    """Keep the start and the end of long output; the middle goes."""
    text = text or ""
    if len(text) <= budget:
        return text
    half = budget // 2
    cut = len(text) - 2 * half
    lines = text.count("\n") + 1
    return (f"[Output was {len(text):,} characters, {lines:,} lines; the middle is cut]\n"
            + text[:half] + f"\n… {cut:,} characters cut …\n" + text[-half:])
