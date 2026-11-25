# Extending Kuwai without changing it

Two small contracts, both checked by `bin/kuwai-ext` before anything reaches
the shell. Neither needs a fork or a restart.

## A search provider

Put a manifest in `~/.config/kuwai/providers/NAME.json`:

```json
{ "prefix": "gh", "title": "GitHub", "glyph": "", "command": ["/home/you/bin/gh-search"] }
```

Type `gh something` in Search (Super+A): Kuwai runs the command with
`something` as its last argument and lists what it prints, either a JSON array
or one JSON object per line:

```json
{ "title": "kuwai #41", "sub": "Pull request · merged", "url": "https://github.com/…" }
{ "title": "Rebuild the docs", "sub": "make docs", "run": ["make", "-C", "/home/you/site", "docs"] }
```

Enter opens the `url` (web or mail links only) or runs `run` (an argument list, no
shell). The rules: the command is an absolute path to a file you own that no
one else can write; it gets 2 seconds and nothing on stdin; at most 20 results;
titles and lines are trimmed.

## A capsule of your own

Any script can put a capsule beside the island (right side, after the system's):

```sh
kuwai capsule set deploy --text "Deploy 3/5" --tone green --glyph "" --ttl 600 --url https://ci.example/run/42
kuwai capsule clear deploy
kuwai capsule list
```

A click opens `--url` or runs `--run CMD ARGS…`; swiping it up clears it. At
most eight are kept (the newest shows, with "+N"), each for an hour unless
`--ttl` says otherwise; the file is `$XDG_RUNTIME_DIR/kuwai/capsules.json`,
yours only, and gone at logout.
