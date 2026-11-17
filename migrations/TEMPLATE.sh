#!/usr/bin/env bash
# what: (one line: what this changes, shown by --list and --dry-run)
#
# A migration that does nothing: copy it to the next free NNNN-what.sh and
# fill it in. It runs once per machine under `bash -euo pipefail`, as you,
# with no input, $TMPDIR private, and writes allowed only under the four XDG
# folders (migrations/README.md has the rules). This file itself never runs:
# only names that start with four digits do.
#
# Available: $XDG_CONFIG_HOME $XDG_STATE_HOME $XDG_CACHE_HOME $XDG_DATA_HOME
# (always set), $KUWAI_ROOT (the copy being migrated to), $KUWAI_MIGRATION
# (this one's name), PATH with kuwai's bin first.

f="$XDG_STATE_HOME/kuwai/example.json"

# 1. Nothing to do? Say nothing and succeed (a fresh install, or already done).
[ -f "$f" ] || exit 0
jq -e 'has("oldKey")' "$f" >/dev/null 2>&1 || exit 0

# 2. Change a copy, then put it in place in one rename (never edit in place).
# jq '.newKey = .oldKey' "$f" >"$f.new" && mv -- "$f.new" "$f"

# 3. One line about what changed (the runner prints the last line).
# echo "example.json: oldKey copied to newKey"
