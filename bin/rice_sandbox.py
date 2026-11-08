"""The assistant's sandbox: one long-lived Docker container (`rice-sandbox`)
where the model can write files and run code without approval, because it
can't reach anything of yours.

- Runs as your uid, `--cap-drop ALL`, `no-new-privileges`, read-only root,
  /tmp as tmpfs, memory / CPU / process caps.
- Only ~/.local/share/rice/sandbox is mounted, at /work. Each chat works in
  /work/<chat>; /work/.home is $HOME (pip --user and npm packages persist).
- Network is on (pip, curl); RICE_SANDBOX_NET=none turns it off.
- Built from sandbox/Dockerfile: `rice-ollama sandbox build`.
"""
import os
import re
import stat
import subprocess
from pathlib import Path

IMAGE = os.environ.get("RICE_SANDBOX_IMAGE", "rice-sandbox")
NAME = os.environ.get("RICE_SANDBOX_NAME", "rice-sandbox")
DOCKER = os.environ.get("RICE_DOCKER", "docker")
ROOT = Path(__file__).resolve().parents[1]


class SandboxError(Exception):
    pass


def host_root():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(os.environ.get("RICE_SANDBOX_DIR") or Path(base) / "rice" / "sandbox")


def chat_slug(chat):
    # No leading dots: "..", "." and ".home" would name the parent, the root
    # or the sandbox's $HOME instead of a chat folder.
    return re.sub(r"[^A-Za-z0-9_.-]", "", str(chat or "")).lstrip(".")[:64] or "scratch"


JOB_ID = re.compile(r"j[0-9a-f]{6}")
JOB_LOG_MAX = 256_000      # the tail of a job's log the host reads


def workspace(chat):
    """The chat's folder on the host (created). Everything under the sandbox
    root is writable from inside the container, so the folder must still be a
    real folder: a link put in its place would aim host-side writes elsewhere."""
    root = host_root()
    root.mkdir(parents=True, exist_ok=True)
    for d in (root / chat_slug(chat), root / ".home"):
        try:
            d.mkdir(exist_ok=True)
        except FileExistsError:
            pass
        if d.is_symlink() or not d.is_dir():
            raise SandboxError(f"{d} isn't a plain folder any more (a link or file replaced it); refusing to use it")
    return root / chat_slug(chat)


# ── Host-side access to container-writable files ────────────────────────
# The container can turn any name under /work into a link, a FIFO or a hard
# link, so the host never opens those paths by name: it walks down from the
# sandbox root one descriptor at a time, refusing links at every step.

_DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def _walk(chat, parts, create=False):
    """A descriptor for <root>/<chat>/<parts...> (a folder), no links followed."""
    fd = os.open(host_root(), os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in (chat_slug(chat), *parts):
            if part in ("", ".", "..") or "/" in part:
                raise SandboxError(f"Bad path part {part!r}")
            if create:
                try:
                    os.mkdir(part, 0o755, dir_fd=fd)
                except FileExistsError:
                    pass
            try:
                nfd = os.open(part, _DIR, dir_fd=fd)
            except OSError as e:
                raise SandboxError(f"{part} isn't a plain folder in the sandbox ({e.strerror})")
            os.close(fd)
            fd = nfd
        return fd
    except BaseException:
        os.close(fd)
        raise


def _open_file(dir_fd, name, flags, mode=0o644):
    try:
        f = os.open(name, flags | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, mode, dir_fd=dir_fd)
    except OSError as e:
        raise SandboxError(f"Can't open {name} in the sandbox ({e.strerror})")
    st = os.fstat(f)
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
        os.close(f)
        raise SandboxError(f"{name} in the sandbox isn't a plain file; refusing it")
    return f


def read_file(chat, parts, limit=None):
    """Text of a sandbox file (its last `limit` bytes), or None if it's absent."""
    d = _walk(chat, parts[:-1])
    try:
        try:
            f = _open_file(d, parts[-1], os.O_RDONLY)
        except SandboxError:
            if not _exists(d, parts[-1]):
                return None
            raise
        with os.fdopen(f, "rb") as fh:
            if limit:
                size = os.fstat(fh.fileno()).st_size
                if size > limit:
                    fh.seek(size - limit)
            data = fh.read(limit or -1)
        return data.decode("utf-8", errors="replace")
    finally:
        os.close(d)


def write_file(chat, parts, data):
    """Write (replace) a sandbox file, creating folders, never through a link."""
    d = _walk(chat, parts[:-1], create=True)
    try:
        f = _open_file(d, parts[-1], os.O_WRONLY | os.O_CREAT)
        with os.fdopen(f, "wb") as fh:
            fh.truncate(0)
            fh.write(data if isinstance(data, bytes) else data.encode("utf-8"))
    finally:
        os.close(d)


def copy_in(chat, parts, src):
    """Copy a host file into the sandbox (an attachment); the source is the user's."""
    with open(src, "rb") as fh:
        write_file(chat, parts, fh.read())


def _exists(dir_fd, name):
    try:
        os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
        return True
    except FileNotFoundError:
        return False


def _job(jid):
    jid = str(jid or "").strip()
    if not JOB_ID.fullmatch(jid):
        raise SandboxError(f"No job {jid}" if jid else "No job id given")
    return jid


def resolve(chat, path):
    """A path the model gave, inside the chat's folder. Relative paths and
    /work/<chat>/… both work; anything that escapes is refused."""
    ws = workspace(chat)
    p = str(path or "").strip()
    if not p:
        raise SandboxError("No path given")
    for prefix in (f"/work/{chat_slug(chat)}/", "/work/"):
        if p.startswith(prefix):
            p = p[len(prefix):]
            break
    full = (ws / p.lstrip("/")).resolve()
    if full != ws.resolve() and ws.resolve() not in full.parents:
        raise SandboxError("That path is outside the sandbox folder")
    return full


def _docker(*args, timeout=30, input_text=None):
    try:
        return subprocess.run([DOCKER, *args], capture_output=True, text=True, timeout=timeout, input=input_text)
    except FileNotFoundError:
        raise SandboxError("Docker isn't installed")
    except subprocess.TimeoutExpired:
        raise SandboxError("Docker didn't answer")


def image_exists():
    return _docker("image", "inspect", IMAGE, timeout=10).returncode == 0


def build(stream=None):
    p = subprocess.run([DOCKER, "build", "-t", IMAGE, str(ROOT / "sandbox")],
                       stdout=stream, stderr=subprocess.STDOUT if stream else None)
    return p.returncode


def state():
    """'running', 'stopped', 'missing' (no container) or 'no-image'."""
    p = _docker("inspect", "-f", "{{.State.Running}}", NAME, timeout=10)
    if p.returncode != 0:
        return "missing" if image_exists() else "no-image"
    return "running" if p.stdout.strip() == "true" else "stopped"


def ensure():
    s = state()
    if s == "running":
        return
    if s == "no-image":
        raise SandboxError("The sandbox image isn't built yet: run `rice-ollama sandbox build`")
    if s == "stopped":
        if _docker("start", NAME).returncode == 0:
            return
        _docker("rm", "-f", NAME)
    root = host_root()
    (root / ".home").mkdir(parents=True, exist_ok=True)
    net = os.environ.get("RICE_SANDBOX_NET") or "bridge"
    p = _docker(
        "run", "-d", "--name", NAME, "--init",
        "--user", f"{os.getuid()}:{os.getgid()}",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "--read-only", "--tmpfs", "/tmp:rw,exec,size=512m",
        "--memory", os.environ.get("RICE_SANDBOX_MEMORY", "2g"),
        "--cpus", os.environ.get("RICE_SANDBOX_CPUS", "4"),
        "--pids-limit", "512",
        "--network", net,
        "-v", f"{root}:/work",
        "--label", "rice.sandbox=1",
        IMAGE, "sleep", "infinity", timeout=60)
    if p.returncode != 0:
        raise SandboxError(f"Couldn't start the sandbox: {p.stderr.strip()[:300]}")


def run(chat, command, timeout=120):
    """Run a bash command in the chat's folder. Returns (exit code, output).
    The command is killed after `timeout` seconds (inside the container)."""
    ensure()
    ws = workspace(chat)
    cwd = f"/work/{ws.name}"
    p = _docker("exec", "-w", cwd, "-e", "TERM=dumb", NAME,
                "timeout", "-k", "5", str(int(timeout)), "bash", "-lc", command, timeout=timeout + 15)
    out = (p.stdout or "") + (("\n" + p.stderr) if p.stderr.strip() else "")
    code = p.returncode
    if code == 124:
        out = (out + "\n" if out else "") + f"(stopped after {int(timeout)} s)"
    return code, out.strip()


# ── Background jobs: they run on after the turn; files in <chat>/.jobs/ ──
# <id>.cmd the command, <id>.log its output, <id>.status its exit code when done,
# <id>.notified once the desktop said so. The folder is mounted, so the host
# reads them directly.

def start_job(chat, command):
    import secrets
    ensure()
    jid = "j" + secrets.token_hex(3)
    ws = workspace(chat)
    write_file(chat, [".jobs", f"{jid}.cmd"], command)
    script = f"( {command} ) > .jobs/{jid}.log 2>&1; echo $? > .jobs/{jid}.status"
    p = _docker("exec", "-d", "-w", f"/work/{ws.name}", "-e", "TERM=dumb", NAME, "bash", "-lc", script)
    if p.returncode != 0:
        raise SandboxError(f"Couldn't start it: {p.stderr.strip()[:200]}")
    return jid


def job_state(chat, jid):
    """(state 'running'|'done', exit code or None, output, command)."""
    jid = _job(jid)
    workspace(chat)
    cmd = read_file(chat, [".jobs", f"{jid}.cmd"], limit=64_000)
    if cmd is None:
        raise SandboxError(f"No job {jid}")
    out = read_file(chat, [".jobs", f"{jid}.log"], limit=JOB_LOG_MAX) or ""
    code = read_file(chat, [".jobs", f"{jid}.status"], limit=64)
    if code is not None:
        code = code.strip()
        return "done", int(code) if code.lstrip("-").isdigit() else None, out, cmd
    return "running", None, out, cmd


def stop_job(chat, jid):
    jid = _job(jid)
    workspace(chat)
    if read_file(chat, [".jobs", f"{jid}.cmd"], limit=1) is None:
        raise SandboxError(f"No job {jid}")
    ensure()
    _docker("exec", NAME, "pkill", "-f", f".jobs/{jid}.log", timeout=10)
    write_file(chat, [".jobs", f"{jid}.status"], "143")


def finished_unnotified():
    """Every chat's jobs that finished and haven't been announced; marks them announced."""
    out = []
    root = host_root()
    try:
        chats = [e.name for e in os.scandir(root) if e.is_dir(follow_symlinks=False)
                 and not e.name.startswith(".") and chat_slug(e.name) == e.name]
    except FileNotFoundError:
        return out
    for chat in chats:
        try:
            d = _walk(chat, [".jobs"])
        except SandboxError:
            continue
        try:
            names = os.listdir(d)
        finally:
            os.close(d)
        for name in names:
            jid, ext = os.path.splitext(name)
            if ext != ".status" or not JOB_ID.fullmatch(jid) or f"{jid}.notified" in names:
                continue
            try:
                code = read_file(chat, [".jobs", name], limit=64)
                write_file(chat, [".jobs", f"{jid}.notified"], "")
                cmd = read_file(chat, [".jobs", f"{jid}.cmd"], limit=64_000) or ""
            except SandboxError:
                continue
            out.append({"chat": chat, "id": jid, "command": cmd[:120], "exit": (code or "").strip()})
    return out


def stop():
    _docker("rm", "-f", NAME, timeout=30)


def render_page(url, timeout=25):
    """A page's DOM after its JavaScript ran (headless Chromium in the sandbox)."""
    ensure()
    p = _docker("exec", NAME, "timeout", str(timeout), "chromium-headless-shell",
                "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", "--hide-scrollbars",
                "--virtual-time-budget=8000", "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/141.0 Safari/537.36", "--dump-dom", url, timeout=timeout + 10)
    if p.returncode != 0 or not p.stdout.strip():
        raise SandboxError(f"The browser couldn't load it ({(p.stderr or '').strip()[-200:]})")
    return p.stdout
