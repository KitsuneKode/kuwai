# Software update

## Flow

`rice update` runs `rice-update` (jsonl in `$XDG_RUNTIME_DIR/rice/update.jsonl`). Island **Software Update** panel shows phases.

## Orange “stopped before finishing”

Usually the job died before a `done` line (password cancel, crash, shell reload). Check the jsonl log; re-run update.

## Root

Only `rice-update-root` (narrow argv, tested in `tests/root`).
