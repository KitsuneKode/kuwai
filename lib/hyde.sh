# shellcheck shell=bash

hyde_here() { [ -f "$HOME/.local/lib/hyde/globalcontrol.sh" ]; }

waybar_start() {
    pgrep -x waybar >/dev/null && return 0
    if command -v hyde-shell >/dev/null; then setsid -f hyde-shell waybar >/dev/null 2>&1 </dev/null
    elif command -v waybar >/dev/null; then setsid -f waybar >/dev/null 2>&1 </dev/null
    else return 1
    fi
}
