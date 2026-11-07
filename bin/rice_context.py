"""What the assistant knows before you say anything (loaded into every turn):

- About this computer: a short profile (distro, kernel, desktop, shell, editor,
  terminal, browser, GPU, RAM, package managers, your top-level folders),
  built once a day and cached at ~/.cache/rice/assistant/system.md.
- Your instructions: ~/.config/rice/assistant/AGENTS.md, written by you
  (pi / Codex / Claude Code's AGENTS.md idea, one global file).
- Memory: ~/.config/rice/assistant/memory.md, facts it saved with `remember`
  (ChatGPT's memory, as a plain file you can read and edit).

Each is capped, so a big file can't crowd the window.
"""
import re
import os
import shutil
import subprocess
import time
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "rice" / "assistant"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "rice" / "assistant"
MEMORY = CONFIG / "memory.md"
AGENTS = CONFIG / "AGENTS.md"
PROFILE = CACHE / "system.md"


def _out(argv, timeout=3):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip() if p.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _os_name():
    try:
        for line in open("/etc/os-release", encoding="utf-8"):
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return "Linux"


def build_profile():
    lines = [f"- OS: {_os_name()}, kernel {os.uname().release}, host {os.uname().nodename}, user {os.environ.get('USER', '')}"]
    desk = os.environ.get("XDG_CURRENT_DESKTOP") or ("Hyprland" if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else "")
    if desk:
        lines.append(f"- Desktop: {desk} (Wayland)" if os.environ.get("WAYLAND_DISPLAY") or desk == "Hyprland" else f"- Desktop: {desk}")
    shell = os.path.basename(os.environ.get("SHELL", ""))
    editor = os.environ.get("VISUAL") or os.environ.get("EDITOR") or ""
    term = os.environ.get("TERMINAL") or next((t for t in ("kitty", "foot", "alacritty", "wezterm", "ghostty") if shutil.which(t)), "")
    bits = [f"shell {shell}" if shell else "", f"editor {editor}" if editor else "", f"terminal {term}" if term else ""]
    browser = _out(["xdg-settings", "get", "default-web-browser"]).replace(".desktop", "")
    if browser:
        bits.append(f"browser {browser}")
    if any(bits):
        lines.append("- Uses: " + ", ".join(b for b in bits if b))
    cpu = ""
    try:
        for line in open("/proc/cpuinfo", encoding="utf-8"):
            if line.startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    gpu = _out(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"])
    try:
        mem_kb = int(next(l for l in open("/proc/meminfo") if l.startswith("MemTotal")).split()[1])
        ram = f"{round(mem_kb / 1048576)} GB RAM"
    except (OSError, StopIteration, ValueError):
        ram = ""
    hw = ", ".join(x for x in (cpu, f"GPU {gpu}" if gpu else "", ram) if x)
    if hw:
        lines.append(f"- Hardware: {hw}")
    pkgs = [p for p in ("pacman", "yay", "paru", "flatpak", "apt", "dnf", "brew", "pipx", "npm", "cargo", "docker") if shutil.which(p)]
    if pkgs:
        lines.append("- Package managers / tools: " + ", ".join(pkgs))
    dirs = sorted(p.name for p in HOME.iterdir() if p.is_dir() and not p.name.startswith(".") and p.name != "snap")[:16]
    if dirs:
        lines.append("- Home folders: " + ", ".join("~/" + d for d in dirs))
    proj = HOME / "Projects"
    if proj.is_dir():
        names = sorted(p.name for p in proj.iterdir() if p.is_dir() and not p.name.startswith("."))[:20]
        if names:
            lines.append("- ~/Projects: " + ", ".join(names))
    return "\n".join(lines)


def profile():
    """The cached profile; rebuilt when it's a day old."""
    try:
        if PROFILE.is_file() and time.time() - PROFILE.stat().st_mtime < 86400:
            return PROFILE.read_text(encoding="utf-8")[:2000]
    except OSError:
        pass
    text = build_profile()
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        PROFILE.write_text(text, encoding="utf-8")
    except OSError:
        pass
    return text


def _read(path, cap):
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""
    return text if len(text) <= cap else text[:cap] + "\n… (cut)"


def memory():
    return _read(MEMORY, 3000)


def instructions():
    return _read(AGENTS, 4000)


def remember(fact):
    fact = " ".join(str(fact or "").split())[:300]
    if not fact:
        raise ValueError("Nothing to remember")
    CONFIG.mkdir(parents=True, exist_ok=True)
    existing = memory()
    if fact.lower() in existing.lower():
        return "Already remembered."
    with open(MEMORY, "a", encoding="utf-8") as f:
        if not existing:
            f.write("# What the assistant remembers about you (edit freely)\n\n")
        f.write(f"- {fact} ({time.strftime('%Y-%m-%d')})\n")
    return "Saved to memory."


SKILLS = CONFIG / "skills"


# Skills shipped with the rice (assistant/skills/) and your own; yours win on a name clash.
REPO_SKILLS = Path(__file__).resolve().parents[1] / "assistant" / "skills"
# The skills every agent on this machine shares (~/.agents/skills: 150+). Too
# many to list for a 16k-context model (~11k tokens), so only the ones that
# match what was asked go in (relevant_skills).
AGENT_SKILLS = Path.home() / ".agents" / "skills"
_SKILL_CACHE = {}


def _skill_meta(d):
    """(name, description, path) from a SKILL.md's front matter, cached by mtime."""
    f = d / "SKILL.md"
    try:
        mt = f.stat().st_mtime
    except OSError:
        return None
    hit = _SKILL_CACHE.get(str(f))
    if hit and hit[0] == mt:
        return hit[1]
    head = f.read_text(encoding="utf-8", errors="replace")[:2000]
    meta = {}
    if head.startswith("---"):
        for line in head.split("---", 2)[1].splitlines():
            if ":" in line and not line.startswith((" ", "\t")):
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip().strip('"').strip("'")
    val = None if meta.get("disable-model-invocation") == "true" else \
        (meta.get("name") or d.name, (meta.get("description") or "")[:300], str(f))
    _SKILL_CACHE[str(f)] = (mt, val)
    return val


STOP = set("a an the and or of to in on for with is are be it this that you your my me i we can how what do does make use using from as at by into about".split())


def _words(t):
    return {w for w in re.findall(r"[a-z0-9]+", (t or "").lower()) if len(w) > 2 and w not in STOP}


def relevant_skills(query, n=6):
    """The shared skills whose name or description matches the request best
    (a word in the name counts triple). Nothing when nothing matches."""
    q = _words(query)
    if not q:
        return []
    scored = []
    try:
        dirs = sorted(AGENT_SKILLS.iterdir())
    except OSError:
        return []
    for d in dirs:
        m = _skill_meta(d) if (d / "SKILL.md").is_file() else None
        if not m:
            continue
        name_w = _words(m[0].replace("-", " "))
        score = 3 * len(q & name_w) + len(q & _words(m[1]))
        if score >= 2:
            scored.append((score, m))
    scored.sort(key=lambda x: -x[0])
    return [m for _, m in scored[:n]]


def skills():
    """pi's progressive disclosure: name, description and where it lives; the
    model reads SKILL.md only when a task matches. ~/.config/rice/assistant/skills/<name>/SKILL.md
    with `name:` and `description:` in its front matter."""
    out = []
    dirs, seen = [], set()
    for root in (SKILLS, REPO_SKILLS):
        try:
            for d in sorted(root.iterdir()):
                if (d / "SKILL.md").is_file() and d.name not in seen:
                    seen.add(d.name)
                    dirs.append(d)
        except OSError:
            continue
    for d in dirs[:40]:
        head = (d / "SKILL.md").read_text(encoding="utf-8", errors="replace")[:2000]
        meta = {}
        if head.startswith("---"):
            for line in head.split("---", 2)[1].splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip().strip('"')
        if meta.get("disable-model-invocation") == "true":
            continue
        out.append((meta.get("name") or d.name, (meta.get("description") or "")[:300], str(d / "SKILL.md")))
    return out


def block(query=""):
    """The context section of the system prompt. `query`: the latest request,
    to pick the shared skills that fit it."""
    parts = ["\n\nAbout this computer:\n" + profile()]
    ins = instructions()
    if ins:
        parts.append("\n\nThe user's standing instructions (follow them):\n" + ins)
    sk = skills()
    names = {n for n, _, _ in sk}
    sk += [m for m in relevant_skills(query) if m[0] not in names]
    if sk:
        parts.append("\n\nSkills (read the SKILL.md with the read tool when a task matches one, then follow it):\n"
                     + "\n".join(f"- {n}: {d} ({p})" for n, d, p in sk))
    mem = memory()
    if mem:
        parts.append("\n\nWhat you remember about the user (from earlier chats; use it when it helps):\n" + mem)
    return "".join(parts)
