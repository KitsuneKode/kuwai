"""kuwai_redact: one rule for what counts as a secret, for every path text takes to a model or a log
(clipboard, selection, window snapshot, terminal command and output, sandbox audit)."""
import re

SECRET_TOKEN = re.compile(r"\b(sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"
                          r"|glpat-[A-Za-z0-9_-]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}"
                          r"|npm_[A-Za-z0-9]{30,}|hf_[A-Za-z0-9]{30,})\b"
                          r"|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*"
                          r"|-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)")


def _entropy(s):
    import math
    from collections import Counter
    n = len(s)
    return -sum(c / n * math.log2(c / n) for c in Counter(s).values()) if n else 0.0


def without_secrets(text):
    """Text for the model with anything secret-shaped replaced, by the same rules the
    clipboard panel masks with: known token shapes, JWTs, private keys, and one long
    random-looking word."""
    out = SECRET_TOKEN.sub("[secret removed]", text)
    t = out.strip()
    if re.fullmatch(r"\S{24,200}", t) and not re.match(r"(https?:|file:|/|~)", t) and re.search(r"[a-z]", t) \
            and re.search(r"[A-Z]", t) and re.search(r"\d", t) and _entropy(t) > 4.0:
        return "[secret removed]"
    return out


LONG_RANDOM = re.compile(r"\b[A-Za-z0-9+/]{40,}={0,2}\b")


def looks_secret(text):
    """Whether text carries anything secret-shaped (used where a whole block is dropped)."""
    return bool(text) and (bool(SECRET_TOKEN.search(text)) or bool(LONG_RANDOM.search(text))
                           or without_secrets(text) != text)
