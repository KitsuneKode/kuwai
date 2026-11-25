#!/usr/bin/env bash
# what: the wallpaper and palette move from HyDE's cache to kuwai look
# touches: $XDG_STATE_HOME/kuwai/wallpaper
# touches: $XDG_STATE_HOME/kuwai/look
set -euo pipefail

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/kuwai
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

mkdir -p "$STATE"
if [ ! -e "$STATE/wallpaper" ] && [ -e "$CACHE/hyde/wall.set" ]; then
    ln -sfn "$(readlink -f "$CACHE/hyde/wall.set")" "$STATE/wallpaper"
fi
if [ -x "$ROOT/bin/kuwai-look" ]; then
    "$ROOT/bin/kuwai-look" init --no-apply >/dev/null
fi
