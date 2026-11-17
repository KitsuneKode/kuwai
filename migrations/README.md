# Migrations

When a kuwai release changes where or how it keeps something (a setting renamed,
a state file reshaped, a folder moved), a script here changes what the earlier
release left on each machine. `bin/kuwai-migrations` (`kuwai migrations`) runs
the ones a machine hasn't run yet, in order, once each; `kuwai promote` and
`install.sh` run it after the new code is in place.

```sh
kuwai migrations --list      # done (when) or pending
kuwai migrations --dry-run   # what would run; runs and writes nothing
kuwai migrations             # run what's pending
```

## Writing one

Copy `TEMPLATE.sh` to the next free number: `NNNN-what-it-does.sh` (four
digits; only names of that shape run). Then:

- **Idempotent.** It may run on a machine that never had the old shape (a fresh
  install runs every migration), on one where it half-ran and failed, and twice
  if someone deletes its record. Check before you change; do nothing when
  there's nothing to do.
- **Additive while a rollback is possible.** If a migration fails, `kuwai
  promote` puts stable back on the commit before, and the migrations that already
  ran stay done. So each one alone must leave state the previous release can
  still read: copy or add, don't delete what the previous release reads (remove
  it in a later release's migration).
- **Atomic writes.** Write a new file beside the old one and `mv` it over; never
  edit in place (a half-written settings file is worse than an old one).
- **Your folders only.** It runs with the kernel refusing any write outside
  `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME`, `$XDG_CACHE_HOME`, `$XDG_DATA_HOME` (each
  inside `$HOME`); `$TMPDIR` is a private folder in the cache. Never root. No
  input; 5 minutes at most.
- **A file the running shell writes** (launcher.json, settings.json through
  kuwai-settings, clipboard state): `kuwai promote` runs migrations before it
  restarts the shell, so the new shell reads the migrated file. Run by hand
  under a live shell, the old shell may write its copy back over yours; say so
  in the migration if that matters, or run `kuwai restart` right after.
- **One line on stdout** when it changed something (the runner prints the last
  line); nothing when it didn't. Exit non-zero to stop the run: it and all after
  it stay pending, and the reason is printed.
- `# what:` near the top is what `--list` and `--dry-run` show.
- Never rename or renumber a shipped migration: its file name is its record.
  A later number may land below one a machine already ran (see 0001 below):
  the runner runs whatever is pending in number order, so migrations must not
  depend on running before a later-numbered one that's already shipped.

## Numbers

- `0001` is kept free for the rice → kuwai rename. Its mover is
  `bin/kuwai-migrate` (run by `kuwai-shell` before the shell starts, every
  start, a no-op once done). Until it is folded in, the runner refuses to run
  where the rename hasn't moved the folders yet. To fold it in later:
  1. Its folder and unit parts become `0001-rename-rice-to-kuwai.sh` as they
     are: they are already idempotent, write only under `~/.config`,
     `~/.local/state`, `~/.cache` (units: `~/.config/systemd/user`), and a
     machine that already ran the mover runs 0001 once as a no-op and records it.
  2. Its runtime-dir link (`$XDG_RUNTIME_DIR/rice → kuwai`) is not a one-shot
     change (the runtime dir is a tmpfs, gone every login) and is outside the
     fence: it stays in `kuwai-shell`.
  3. `kuwai-shell` calls `kuwai-migrations` where it calls `kuwai-migrate`
     today, before the shell starts, so the record exists before anything reads
     the new folders; 0001 is the lowest number, so it runs before any other
     pending one; the runner's "not moved yet" refusal goes.
  4. The record lives in `~/.local/state/kuwai/migrations`, which the runner
     makes before 0001 runs; the mover already handles a `kuwai` folder that
     exists beside `rice` (it merges entries).
- `0002-launcher-vitals-to-system.sh`: the launcher's frecency for the old
  "Vitals" action goes to "System" (2026-11-17, f7fd72b).

Tests: `tests/install/test_migrations.py` (a temp HOME: order, once only, a
failure stops the run, dry-run changes nothing, a write outside the folders is
refused) and the migrations' own cases.
