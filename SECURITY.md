# Security

kuwai runs as your user session: a Hyprland config, a Quickshell shell, user
services, and an optional local assistant. Some parts touch sensitive things:
the lock screen, notification bodies, clipboard history, screen-share privacy,
the assistant's file and sandbox tools, and one root helper (`bin/rice-update-root`,
reached through pkexec for system updates).

## Reporting

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/KitsuneKode/kuwai/security/advisories/new),
not a public issue. Say what you did, what happened, and the commit you ran.

## What is covered by tests

- The assistant: secrets are refused by read *and* by search; files the sandbox
  container can write are opened without following links
  (`tests/agent/test_file_policy.py`, `tests/agent/test_sandbox_boundary.py`).
- The root helper refuses bad paths, names and symlinks before touching anything
  (`tests/root`). No privileged transaction runs in tests.
- The installer restores the state before the first install and never writes
  through a link (`tests/install`).

What is *not* qualified yet: live lock-screen failure modes, real portal screen
sharing, and the assistant on hardware other than the author's. See
[`docs/manual/security.md`](docs/manual/security.md) for the known gaps.
