---
name: delete-comment
description: Triage, categorize, and delete code comments under kuwai's comment ratchet — deleting Tautology/Stale comments, filing GitHub issues for Excuses, moving Decision Records into docs/decisions/ ADRs, and lowering docs/comments-baseline.json.
argument-hint: "[path ...]"
allowed-tools:
  - read
  - edit
  - write
  - grep
  - glob
  - exec
triggers:
  - user
  - model
---

# Delete Comments (Ratchet Burn-Down)

Eliminate every non-exempt code comment in the target paths (`$ARGUMENTS`), preserving architectural rationale in ADRs and turning hack excuses into tracked GitHub issues.

## 1. Pick Scope and Check Live-Session Safety

- If paths were provided, scan them with `bin/kuwai-comments --json <paths...>`.
- If no paths were provided, inspect `docs/comments-baseline.json` (or `bin/kuwai-comments --stats`) and pick one cohesive directory or subsystem slice (e.g., `shell/services/`, `shell/components/`, `shell/modules/<name>/`, or `tests/<suite>/`).
- If any target path is under `shell/`, run `qs list --all --json` to check whether the owner's live desktop runs from this checkout; if it does, perform the edits in `.worktrees/<name>/` and verify before bringing them over.
- Check whether any target script reads its own header comments (`sed -n ... "$0"` or similar); convert those to an explicit `usage()` heredoc before deleting comments.

**Done when:** Every non-exempt comment block in scope has been listed with its surrounding code.

## 2. Categorize Every Comment Block

Inspect every block in scope against its surrounding code and assign exactly one category:

| Category | Definition | Required Action |
|---|---|---|
| **Tautology** | Repeats what the code already expresses | Delete |
| **Stale** | References removed files, old renames, obsolete behavior, or contradicts current code | Delete |
| **Excuse** | Justifies a hack, sleep/race workaround, inflated gate, brittle scraper, or deferred cleanup | Delete comment **and** file a GitHub issue |
| **Decision Record** | Captures a non-obvious constraint, hardware/driver measurement, security invariant, or trade-off | Move into an ADR under `docs/decisions/`, then delete |

Leave exempted items untouched (enforced automatically by `bin/kuwai-comments`):
- Line-1 shebangs (`#!`)
- JSDoc type blocks (`/** ... */` with `@param`, `@returns`, `@typedef`, `@type`, etc.) needed by `tsconfig.check.json`
- Tool/runner directives (`# noqa`, `# type:`, `# shellcheck`, `# what:`, `// eslint-`, `// @ts-`, `// qmllint`, `-- luacheck:`)
- Python docstrings

**Done when:** Every comment block in scope is accounted for in one of the four categories.

## 3. Act Before Deleting

1. **Decision Records → ADRs (`docs/decisions/`)**:
   - Inspect existing ADRs and `docs/decisions/README.md` to either extend an existing subsystem ADR or create the next sequential `ADR-NNN-<slug>.md` (sections: `Status`, `Date`, `Context`, `Decision`, `Alternatives Considered`, `Consequences`).
   - Preserve exact measurements, kernel/driver/tool quirks, security boundaries, and affected file paths; update `docs/decisions/README.md` when adding a new ADR.
2. **Excuses → GitHub Issues (`KitsuneKode/kuwai`)**:
   - Run `gh issue list --state open --limit 100` first to avoid filing duplicates; comment on an existing issue if the hack is already tracked.
   - For each distinct untracked hack, file a concise issue with `gh issue create --title "..." --label bug|enhancement --body "..."` citing the exact file(s), current workaround, and target fix.

**Done when:** Every Decision Record is recorded in `docs/decisions/` and every Excuse has an open GitHub issue.

## 4. Delete Comments and Ratchet Down

1. Delete all categorized standalone and inline comments from the target files without leaving runs of excessive blank lines or trailing whitespace.
2. Verify zero non-exempt comments remain in scope:
   ```sh
   bin/kuwai-comments --list <paths...>
   ```
3. Lower the baseline (ratchet only moves down):
   ```sh
   bin/kuwai-comments --update
   bin/kuwai-comments --check
   ```

## 5. Verify Everything Still Passes

Run the checks matching the touched paths:
- `bin/kuwai-comments --check` and `bin/kuwai-tokens --check`
- `python -m pytest -q -p no:cacheprovider tests`
- `bun test`
- `for t in tests/hypr/test_*.lua; do lua "$t"; done` (if `hypr/` changed)
- Syntax checks: `bash -n`, `luac -p`, `py_compile`, and `/usr/lib/qt6/bin/qmllint --bare -W 0 --max-warnings -1 --syntax error` for QML files

Report: files cleaned, comment counts by category, ADRs created/updated, GitHub issue URLs filed, lines shed in this pass, and remaining baseline from `bin/kuwai-comments --stats`.
