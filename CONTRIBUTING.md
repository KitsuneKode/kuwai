# Contributing

## Layout

| Path | What |
| --- | --- |
| `hypr/` | The Hyprland half, in Lua (`hypr/init.lua`, `hypr/kuwai/*.lua`) |
| `shell/` | The Quickshell shell: `config/` (Theme, Paths), `components/`, `services/`, `modules/` |
| `bin/` | Commands (`kuwai`, `kuwai-ctl`, `kuwai-check`, …) and the assistant's Python |
| `lib/` | What commands share: `brightness/` (the DDC/backlight daemon), `look/`, `dispatch.sh` |
| `tests/` | Python tests (`pytest`), shell JS tests (`bun test`), and Hyprland Lua tests |
| `docs/` | Design notes, the manual, research |

## Channels

Your session runs the **stable** copy (`~/.local/share/kuwai`, the `stable`
branch). Edit in the repo (**dev**), commit, then `kuwai promote`: it checks the
running shell, lints the changed QML, parses the candidate's Lua, loads the new
shell and login screen offscreen, then fast-forwards stable and restarts. If
Hyprland or the shell fails to load, it rolls back.

## Before a pull request

```sh
PYTHONDONTWRITEBYTECODE=1 python -m pytest -q -p no:cacheprovider tests
bun test
for t in tests/hypr/test_*.lua; do lua "$t"; done
bin/kuwai-loadtest HEAD && bin/kuwai-loadtest HEAD greeter.qml
bin/kuwai-tokens --check
bin/kuwai-comments --check
```

CI (`.github/workflows/shell-check.yml`) runs the syntax checks and tests above;
what it can't run (a live shell, Hyprland itself) is on you: `kuwai-check` and
`kuwai doctor`.

## Conventions

- Use Theme tokens for sizes, durations and colours; `kuwai-tokens --check` only lets the hand-typed ones go down.
- No hardcoded `~/Projects/rice`: `Paths.bin` in QML, `K.bin` in Lua, the script's own folder in shell scripts.
- Long-lived helper processes start with `setpriv --pdeathsig KILL --` (promote refuses ones that don't).
- Tests use temporary homes and stub tools; never the live session, real notifications or synthetic typing.
- Commit messages say what changed for the person using it, then why.
