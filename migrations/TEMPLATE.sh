#!/usr/bin/env bash
# what: (one line: what this changes, shown by --list and --dry-run)
# touches: $XDG_STATE_HOME/kuwai/example.json

f="$XDG_STATE_HOME/kuwai/example.json"

[ -f "$f" ] || exit 0
jq -e 'has("oldKey")' "$f" >/dev/null 2>&1 || exit 0
