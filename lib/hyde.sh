# lib/hyde.sh — is HyDE here, for kuwai's shell scripts. Source it:
#   . "$KUWAI/lib/hyde.sh"
# The same rule everywhere (docs/design/WITHOUT-HYDE.md): HyDE is installed when
# its scripts are, ~/.local/lib/hyde/globalcontrol.sh (hypr/kuwai/core.lua K.hyde,
# shell/services/Hyde.qml, bin/kuwai-themes hyde_here). Its `hyde-shell` command
# is asked for separately where a script runs it.
# shellcheck shell=bash

hyde_here() { [ -f "$HOME/.local/lib/hyde/globalcontrol.sh" ]; }

# Waybar, if it isn't running: HyDE's (its config and theme) when hyde-shell is
# there, else plain waybar with its own config. 1 when neither can run.
waybar_start() {
    pgrep -x waybar >/dev/null && return 0
    if command -v hyde-shell >/dev/null; then setsid -f hyde-shell waybar >/dev/null 2>&1 </dev/null
    elif command -v waybar >/dev/null; then setsid -f waybar >/dev/null 2>&1 </dev/null
    else return 1
    fi
}
