# ADR-010: Code Comment Policy and Per-File Ratchet Enforcement

## Status
Accepted

## Date
2026-11-21

## Context
Across 470 tracked source files (~86,900 lines), kuwai accumulated 10,975 lines
containing code comments (~4,800 comment blocks; ~9,843 standalone comment
lines, or ~11.3% of the entire codebase). Auditing these comments revealed four
recurring failure modes:

1. **Tautologies**: Comments restating what the next line of code already says,
   adding noise and token overhead.
2. **Stale comments**: Comments contradicting current behavior (e.g., claiming
   `shell-auth/` components are symlinked after they were switched to audited
   vendored copies).
3. **Excuses**: Comments justifying hacky workarounds (sleep races, inflated
   memory/CPU gates, legacy shims, brittle scrapers) so the workaround persists
   indefinitely instead of being tracked and fixed.
4. **Hidden decision records**: Genuine architectural constraints, hardware
   measurements, and security invariants buried inside source files where they
   are hard to discover across subsystems.

Deleting all ~11,000 comment lines in a single PR is unnecessary and risky; a
ratchet lets the codebase burn existing comments down incrementally while
preventing any new ones from entering.

## Decision

1. **Ban non-exempt code comments with a per-file ratchet (`bin/kuwai-comments`, `docs/comments-baseline.json`)**:
   - Every tracked (and newly added untracked) source file in Python, QML,
     JS/MJS/TS, C/C++, GLSL, Lua, and Shell is scanned by `bin/kuwai-comments`.
   - `docs/comments-baseline.json` stores the maximum allowed comment-line
     count per file. Any file absent from the baseline has a budget of `0`.
   - `bin/kuwai-comments --check` fails if *any* file exceeds its per-file
     budget (preventing trading deletions in one file for new comments in
     another). Wired into `bin/kuwai-check` and CI
     (`.github/workflows/shell-check.yml`).
   - `bin/kuwai-comments --update` only lowers per-file budgets (and removes
     files that reach `0`); it never raises a budget.

2. **Explicit exemptions**:
   - Line-1 shebangs (`#!`)
   - JSDoc type annotation blocks (`/** ... */` containing `@param`,
     `@returns`, `@typedef`, `@type`, etc.) required by `tsconfig.check.json`
   - Tool/runner directives (`# noqa`, `# type: ignore`, `# shellcheck`,
     `# what:` in migrations, `// eslint-`, `// @ts-`, `// qmllint`,
     `-- luacheck:`, etc.)
   - Python docstrings (string literals, not `#` comments)

3. **Repeatable triage workflow (`.devin/skills/delete-comment/SKILL.md`)**:
   - Categorize every comment in the target slice as **Tautology**, **Stale**,
     **Excuse**, or **Decision Record**.
   - Delete Tautology and Stale comments directly.
   - Delete Excuse comments and file a GitHub issue to fix the underlying hack.
   - Move Decision Record comments into an ADR under `docs/decisions/`, then
     delete the inline comment.
   - Run `bin/kuwai-comments --update` and verify with `bin/kuwai-comments --check`.

## Alternatives Considered

- **Coarse repo-wide or directory-wide comment count ratchet**:
  Rejected because deleting 10 comments in one file would allow adding 10 new
  comments in another file without tripping the check.
- **Banning JSDoc type blocks too**:
  Rejected because `tsconfig.check.json` relies on JSDoc annotations to
  type-check `.mjs` shell modules without a compile step.

## Consequences
- Non-shell source directories (`bin/`, `hypr/`, `lib/`, `greeter/`,
  `shell-auth/`, `shell-saver/`, `migrations/`, `system/`, `plugins/`,
  `install.sh`) start at 0 non-exempt comments.
- Remaining comments in `shell/` and `tests/` are locked per-file and can be
  eliminated incrementally using `/delete-comment`.
