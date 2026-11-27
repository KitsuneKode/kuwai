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
_HOME_SECRETS = (
    ".ssh", ".gnupg", ".password-store", ".aws", ".kube", ".mozilla", ".zen",
    ".docker", ".gcloud", ".azure", ".pki", ".cert", ".t3", ".codex",
    ".claude", ".claude.json", ".cursor",
)
_CONFIG_SECRETS = (
    "kuwai/secrets", "kuwai/feeds", "chromium", "google-chrome", "BraveSoftware",
    "gh", "gcloud", "op", "rclone", "Cursor", "devin", "sops", "age",
)
_DATA_SECRETS = (
    "keyrings", "kwalletd", "devin", "fish/fish_history", "kuwai-data/clipboard",
    "voxtype", "gnupg", "password-store",
)
_STATE_SECRETS = ("kuwai", "voxtype")
_CACHE_SECRETS = ("kuwai/clip", "cliphist")
_RUNTIME_SECRETS = ("kuwai", "keyring", "gnupg", "gcr", "p11-kit", "ssh-agent.socket")
_TOOL_ENV_VARS = (
    "GNUPGHOME", "PASSWORD_STORE_DIR", "DOCKER_CONFIG",
    "AWS_SHARED_CREDENTIALS_FILE", "AWS_CONFIG_FILE", "GH_CONFIG_DIR",
    "CLOUDSDK_CONFIG", "AZURE_CONFIG_DIR", "RCLONE_CONFIG",
    "CLAUDE_CONFIG_DIR", "CODEX_HOME", "T3CODE_HOME",
)
_USER_DIR_RE = re.compile(r'^\s*XDG_(DESKTOP|DOWNLOAD|TEMPLATES|PUBLICSHARE|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR\s*=\s*"?([^"\n]+)"?\s*$')


def home_dir():
    return Path(os.environ.get("HOME") or Path.home())


def _abs_env_path(raw, home):
    val = (raw or "").strip()
    if not val:
        return None
    if val.startswith("$HOME"):
        val = str(home) + val[5:]
    elif val.startswith("${HOME}"):
        val = str(home) + val[7:]
    p = Path(os.path.expanduser(val))
    return p if p.is_absolute() else None


def _xdg_bases(env_var, default_rel, home):
    bases = [home / default_rel]
    custom = _abs_env_path(os.environ.get(env_var), home)
    if custom and custom not in bases:
        bases.append(custom)
    return bases


def user_dirs(home=None):
    """Resolved XDG user-dirs (Documents, Downloads, …) from user-dirs.dirs and env."""
    h = home or home_dir()
    found = {}
    for key in ("DESKTOP", "DOWNLOAD", "TEMPLATES", "PUBLICSHARE", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS"):
        p = _abs_env_path(os.environ.get(f"XDG_{key}_DIR"), h)
        if p:
            found[key] = p
    for cfg in _xdg_bases("XDG_CONFIG_HOME", ".config", h):
        f = cfg / "user-dirs.dirs"
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = _USER_DIR_RE.match(line)
            if m:
                p = _abs_env_path(m.group(2), h)
                if p:
                    found[m.group(1)] = p
    return found


def _expand_resolved(paths):
    out = []
    seen = set()
    for p in paths:
        for cand in (p, p.resolve()):
            if cand not in seen:
                seen.add(cand)
                out.append(cand)
    return out


def secret_paths():
    """Denied paths for the current HOME and relocated XDG / tool environment directories."""
    h = home_dir()
    h_res = h.resolve()
    raw = [h / rel for rel in _HOME_SECRETS]
    for cfg in _xdg_bases("XDG_CONFIG_HOME", ".config", h):
        raw.extend(cfg / rel for rel in _CONFIG_SECRETS)
    for data in _xdg_bases("XDG_DATA_HOME", ".local/share", h):
        raw.extend(data / rel for rel in _DATA_SECRETS)
    for st in _xdg_bases("XDG_STATE_HOME", ".local/state", h):
        raw.extend(st / rel for rel in _STATE_SECRETS)
    for cache in _xdg_bases("XDG_CACHE_HOME", ".cache", h):
        raw.extend(cache / rel for rel in _CACHE_SECRETS)
    rt_bases = [Path(f"/run/user/{os.getuid()}")]
    rt_custom = _abs_env_path(os.environ.get("XDG_RUNTIME_DIR"), h)
    if rt_custom and rt_custom not in rt_bases:
        rt_bases.append(rt_custom)
    for rt in rt_bases:
        rt_res = rt.resolve()
        if rt_res not in (Path("/"), Path("/tmp"), h, h_res) and rt_res not in h_res.parents:
            raw.append(rt)
        raw.extend(rt / rel for rel in _RUNTIME_SECRETS)
    for var in _TOOL_ENV_VARS:
        p = _abs_env_path(os.environ.get(var), h)
        if p:
            raw.append(p)
    kube = os.environ.get("KUBECONFIG") or ""
    for item in kube.split(os.pathsep):
        p = _abs_env_path(item, h)
        if p:
            raw.append(p)
    return _expand_resolved(raw)


SECRET = secret_paths()
SECRET_NAME = re.compile(r"(^id_[a-z0-9]+$|\.pem$|\.key$|\.p12$|\.pfx$|^\.env(\..*)?$|^credentials(\.(json|toml|ya?ml))?$|\.kdbx$"
                         r"|^\.netrc$|^\.git-credentials$|^\.npmrc$|^\.pypirc$|^cookies(\.sqlite)?$|^login data$|^\.pgpass$|^\.wakatime\.cfg$|_history$|^\.histfile$"
                         r"|^key[34]\.db$|^logins\.json$|^hosts\.ya?ml$|^auth\.json$|token)", re.I)


class FileError(Exception):
    pass


def resolve(path, sandbox_dir):
    """(absolute Path, is_sandbox). Relative → the sandbox folder."""
    p = str(path or "").strip()
    if not p:
        raise FileError("No path given")
    sb = Path(sandbox_dir).resolve()
    if p.startswith("/work/"):
        p = p.split("/", 3)[3] if p.count("/") >= 3 else ""
    if p.startswith("~"):
        full = Path(os.path.expanduser(p)).resolve()
    elif p.startswith("/"):
        full = Path(p).resolve()
    else:
        full = (sb / p).resolve()
    inside = full == sb or sb in full.parents
    return full, inside


def _name_parts(p, home):
    for base in (home, home.resolve()):
        try:
            return p.relative_to(base).parts
        except ValueError:
            pass
    return p.parts[1:]


def check_readable(full):
    """Refuse secrets places and secret-named files, and any file under a secret-named folder
    (review finding 02: ~/x/credentials/notes.txt was refused by grep but readable by path).
    Judged on the path as given and where it really leads."""
    full = Path(full)
    h = home_dir()
    secrets = secret_paths()
    for p in {full, full.resolve()}:
        for s in secrets:
            if p == s or s in p.parents:
                raise FileError(f"{p} holds secrets; it isn't read")
        for part in _name_parts(p, h):
            if SECRET_NAME.search(part):
                raise FileError(f"{part} looks like a key or secrets place; it isn't read")


def is_secret(path, root):
    """A descendant `path` found under `root` (the folder already checked):
    secret if it, or any folder between root and it, is a secrets place or
    has a secrets name. Followed links are judged by where they land too."""
    path = Path(path)
    root = Path(root)
    h = home_dir()
    secrets = secret_paths()
    resolved = path.resolve()
    for p in {path, resolved}:
        if any(p == s or s in p.parents for s in secrets):
            return True
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        parts = path.parts[-1:]
    if any(SECRET_NAME.search(x) for x in parts):
        return True
    try:
        res_parts = resolved.relative_to(root.resolve()).parts
    except ValueError:
        res_parts = _name_parts(resolved, h)
    return any(SECRET_NAME.search(x) for x in res_parts)


def show(full):
    s = str(full)
    h = str(home_dir())
    return "~" + s[len(h):] if s.startswith(h) else s


def read(full, offset=None, limit=None, raw=None, name=None):
    """A file's lines with pi's notes. `raw` is given when the caller already read the bytes
    safely (sandbox files: through the no-follow walker)."""
    if raw is None:
        check_readable(full)
        if full.is_dir():
            raise FileError(f"{show(full)} is a folder; use ls")
        if not full.is_file():
            raise FileError(f"No such file: {show(full)}")
        with open(full, "rb") as f:
            raw = f.read(4_000_000)
    if b"\0" in raw[:8192]:
        raise FileError(f"{name or show(full)} is a binary file")
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
    if str(pattern).startswith("-"):
        raise FileError("A file pattern can't start with '-'")
    check_readable(full)
    fd = shutil.which("fd") or shutil.which("fdfind")
    if fd:
        p = subprocess.run([fd, "--glob", "--color", "never", "--max-results", str(limit + 1), "--", pattern, str(full)],
                           capture_output=True, text=True, timeout=15)
        hits = [l for l in p.stdout.splitlines() if l]
    else:
        hits = [str(x) for x in list(full.rglob(pattern))[:limit + 1]]
    hits = [h for h in hits if not is_secret(h, full)]
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
    argv = [rg, "--null", "--line-number", "--no-heading", "--color", "never", "--max-columns", str(LINE_CAP),
            "--max-columns-preview", "--glob", "!.git"]
    full_res = full.resolve()
    excluded = set()
    for s in secret_paths():
        for base in (full, full_res):
            try:
                rel = s.relative_to(base).as_posix()
            except ValueError:
                continue
            if rel and rel != "." and rel not in excluded:
                excluded.add(rel)
                argv += ["--glob", f"!{rel}", "--glob", f"!{rel}/**"]
    if ignore_case:
        argv.append("-i")
    if literal:
        argv.append("-F")
    if glob:
        argv += ["--glob", glob]
    argv += ["--", pattern, str(full)]
    p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    got = []
    try:
        for raw in p.stdout:
            got.append(raw.rstrip("\n"))
            if len(got) > max(limit * 5, 500):
                break
    finally:
        if p.poll() is None:
            p.kill()
        p.wait()
    p.stdout = "\n".join(got)
    p.stderr = p.stderr.read() if p.stderr and not p.stderr.closed else ""
    if p.returncode == 2:
        raise FileError(p.stderr.strip()[:300] or "grep failed")
    h = str(home_dir())
    lines, cache = [], {}
    single = full.is_file()
    for raw in p.stdout.splitlines():
        path, sep, rest = raw.partition("\0")
        if not sep:
            path, rest = str(full), raw
        if path not in cache:
            cache[path] = not single and is_secret(path, full)
        if cache[path]:
            continue
        line = path + ":" + rest if not single else rest
        lines.append(("~" + line[len(h):]) if line.startswith(h) else line)
    more = len(lines) > limit
    out = "\n".join(lines[:limit]) or "No matches"
    if more:
        out += f"\n[{len(lines)} matches, showing {limit}. Use limit={min(len(lines), 300)} for more, or refine the pattern.]"
    return out


def run_bounded(argv, timeout, keep=65536, stdin_text=None):
    """(exit code or None on timeout, text, total bytes). stdout and stderr merged."""
    import collections
    import select
    import time as _t
    p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL)
    if stdin_text is not None:
        try:
            p.stdin.write(stdin_text.encode())
            p.stdin.close()
        except OSError:
            pass
    head, tail, total = bytearray(), collections.deque(), 0
    tail_size, half = 0, keep // 2
    deadline = _t.monotonic() + timeout
    fd = p.stdout.fileno()
    while True:
        left = deadline - _t.monotonic()
        if left <= 0:
            p.kill()
            p.wait()
            return None, _join(head, tail, total, keep), total
        r, _, _ = select.select([fd], [], [], min(left, 0.5))
        if not r:
            if p.poll() is not None:
                break
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        total += len(chunk)
        if len(head) < half:
            take = half - len(head)
            head += chunk[:take]
            chunk = chunk[take:]
        if chunk:
            tail.append(chunk)
            tail_size += len(chunk)
            while tail and tail_size - len(tail[0]) >= half:
                tail_size -= len(tail.popleft())
    return p.wait(), _join(head, tail, total, keep), total


def _join(head, tail, total, keep):
    t = b"".join(tail)
    if total <= keep:
        return (bytes(head) + t).decode("utf-8", errors="replace")
    t = t[-(keep // 2):]
    cut = total - len(head) - len(t)
    return (bytes(head).decode("utf-8", errors="replace") + f"\n… {cut:,} bytes cut …\n"
            + t.decode("utf-8", errors="replace"))


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
