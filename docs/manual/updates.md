# Software update

## Flow

`kuwai update` runs `kuwai-update` (jsonl in `$XDG_RUNTIME_DIR/kuwai/update.jsonl`). Island **Software Update** panel shows phases.

## Orange “stopped before finishing”

Usually the job died before a `done` line (password cancel, crash, shell reload). Check the jsonl log; re-run update.

## Root

Only `kuwai-update-root` (narrow argv, tested in `tests/root`).
