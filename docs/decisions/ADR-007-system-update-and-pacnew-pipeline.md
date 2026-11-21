# ADR-007: Single-Password System Update Pipeline and Three-Way `.pacnew` Classification

## Status
Accepted

## Date
2026-11-21

## Context
Arch system updates combine repo packages (`pacman`), AUR builds (`makepkg` as
an unprivileged user), Flatpaks, and `.pacnew` config merges. Earlier updater
flows had sharp operational and security edges:

- Prompting for root separately for `pacman -Syu`, AUR build dependencies, and
  installing built AUR packages required multiple password prompts per run.
- Running a root helper directly out of a user-writable home/repo directory
  would let any user-level process rewrite code executed as root.
- Closing the terminal or shell mid-update could send `SIGHUP` and abort
  `pacman` mid-transaction, leaving the system in a broken state.
- Classifying `.pacnew` files with a two-way diff (`current` vs `.pacnew`)
  could not distinguish a setting the package newly added from a default
  setting the user intentionally removed or commented out.
- Reconnecting the UI mid-update previously assumed a repo-only plan and froze
  the progress ring at 97% through every AUR build.

## Decision

1. **Single-password root helper and resilient update phases (`bin/kuwai-update`, `bin/kuwai-update-root`)**:
   - Install `kuwai-update-root` root-owned outside `$HOME` (on first run or
     when updated, the single password prompt installs and launches it) so user
     processes cannot modify code run as root.
   - Ignore `SIGHUP` during update runs, keep `pacman` running even if stdout
     disconnects, and wait on concurrent update locks (e.g., terminal `sysup`)
     instead of failing steps as skipped.
   - Order phases as: pre-flight checks → unprivileged AUR fetch/review/dep
     discovery → single root session for `pacman -Syu` + `--asdeps` repo deps →
     unprivileged AUR builds → single root install of built packages →
     per-installation Flatpak updates → post-update checks.
   - Emit the full `plan` event at the top of the event stream so a shell
     joining mid-run scales progress accurately; record only the final `\r`
     state of progress-bar lines in logs; convert unexpected exceptions into
     structured JSON error events rather than raw UI tracebacks.
   - In AUR PKGBUILD review diffs, blank out version numbers and hashes so
     routine version bumps are not flagged as suspicious edits.

2. **Symlink-free root `.pacnew` operations and three-way classification (`bin/kuwai-update-root`, `bin/kuwai-pacnew`)**:
   - `kuwai-update-root` resolves and rejects symlinks anywhere on the target
     `/etc/` file, its `.pacnew`, or any parent directory before modifying
     system config.
   - `bin/kuwai-pacnew` extracts the previous package default from the pacman
     cache for a three-way comparison: lines the user removed from the old
     default are recognized as deliberate user choices rather than new package
     defaults. When the prior default is no longer cached, it refuses to claim
     the file is untouched and marks it `review`.
   - Always preserve tool-managed files such as `/etc/pacman.d/mirrorlist`
     (maintained by `reflector`).

## Alternatives Considered

- **Running `kuwai-update-root` in-place from the user's git checkout**:
  Rejected on security grounds: root must never execute user-writable code.
- **Two-way `.pacnew` auto-merge**:
  Rejected because it silently restored default settings the user had
  deliberately removed or commented out.

## Consequences
- Full repo + AUR updates complete with a single authentication prompt while
  keeping build execution unprivileged.
- `.pacnew` auto-recommendations stay conservative when pacman cache history
  is missing.
