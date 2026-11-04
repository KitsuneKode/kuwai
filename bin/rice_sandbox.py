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
    return re.sub(r"[^A-Za-z0-9_.-]", "", str(chat or ""))[:64] or "scratch"


def workspace(chat):
    """The chat's folder on the host (created)."""
    d = host_root() / chat_slug(chat)
    d.mkdir(parents=True, exist_ok=True)
    (host_root() / ".home").mkdir(parents=True, exist_ok=True)
    return d


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

def jobs_dir(chat):
    d = workspace(chat) / ".jobs"
    d.mkdir(exist_ok=True)
    return d


def start_job(chat, command):
    import secrets
    ensure()
    jid = "j" + secrets.token_hex(3)
    d = jobs_dir(chat)
    (d / f"{jid}.cmd").write_text(command, encoding="utf-8")
    ws = workspace(chat)
    script = f"( {command} ) > .jobs/{jid}.log 2>&1; echo $? > .jobs/{jid}.status"
    p = _docker("exec", "-d", "-w", f"/work/{ws.name}", "-e", "TERM=dumb", NAME, "bash", "-lc", script)
    if p.returncode != 0:
        raise SandboxError(f"Couldn't start it: {p.stderr.strip()[:200]}")
    return jid


def job_state(chat, jid):
    """(state 'running'|'done', exit code or None, output, command)."""
    d = jobs_dir(chat)
    if not (d / f"{jid}.cmd").is_file():
        raise SandboxError(f"No job {jid}")
    status = d / f"{jid}.status"
    log = d / f"{jid}.log"
    out = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    cmd = (d / f"{jid}.cmd").read_text(encoding="utf-8")
    if status.is_file():
        code = status.read_text().strip()
        return "done", int(code) if code.lstrip("-").isdigit() else None, out, cmd
    return "running", None, out, cmd


def stop_job(chat, jid):
    ensure()
    _docker("exec", NAME, "pkill", "-f", f".jobs/{jid}.log", timeout=10)
    (jobs_dir(chat) / f"{jid}.status").write_text("143")


def finished_unnotified():
    """Every chat's jobs that finished and haven't been announced; marks them announced."""
    out = []
    root = host_root()
    for st in root.glob("*/.jobs/*.status"):
        jid, d = st.stem, st.parent
        mark = d / f"{jid}.notified"
        if mark.exists():
            continue
        mark.write_text("")
        cmd = (d / f"{jid}.cmd").read_text(encoding="utf-8", errors="replace") if (d / f"{jid}.cmd").exists() else ""
        code = st.read_text().strip()
        out.append({"chat": d.parent.name, "id": jid, "command": cmd[:120], "exit": code})
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
