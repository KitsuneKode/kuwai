---
name: security-audit
description: Audit this computer or a codebase for security problems and explain real risks with concrete fixes. Use for "is my system secure", "audit", "harden", "check for secrets / vulnerabilities".
---

# Security audit

Work through it with update_plan. Report only what you actually found, with the evidence.

## This computer
1. Call `system_audit` (read-only).
2. Look for, in this order:
   - Ports listening on `0.0.0.0` / `[::]` (reachable from the network) vs `127.0.0.1` (local only). For each
     public one, say which program it is and whether it needs to be public.
   - No firewall service active while ports are public.
   - SSH: `PermitRootLogin yes`, `PasswordAuthentication yes` with sshd active.
   - Many pending updates (security fixes wait in them).
   - Docker publishing ports on `0.0.0.0` (Docker bypasses most firewalls).
   - Unknown autostart entries, user services or cron jobs.
3. For each finding: severity (high / medium / low), why it matters in one line, the exact fix command.
   Fixes that change the system are the user's to run; offer them, don't run them.

## A codebase (copy it into the sandbox or read it in place)
- Secrets: `gitleaks detect --no-git -s <dir> -v` (in the sandbox, on a copy) or grep for keys/tokens.
- Python: `bandit -r <dir> -q` and `pip-audit -r requirements.txt` (needs network).
- Shell: `shellcheck <files>`.
- JavaScript: `npm audit --omit=dev` in the project folder (in the sandbox).
- Then read the flagged code yourself: false positives are common; say which findings are real.

Never print a secret you find in full: show the file, the line and the first 4 characters.
