#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-$(command -v podman || command -v docker || true)}"
[ -n "$RUNTIME" ] || { echo "test-release-root: podman or docker required" >&2; exit 2; }
TAR=$(mktemp --suffix=.tar)
trap 'rm -f -- "$TAR"' EXIT
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 -I{} sh -c '[ -e "$1" ] || [ -L "$1" ] && printf "%s\0" "$1"' sh {} | tar --null -cf "$TAR" -T -)
"$RUNTIME" run --rm -v "$TAR:/kuwai-src.tar:ro" -v "$ROOT/tests/vm/release-root-inside.sh:/check.sh:ro" \
    archlinux:latest bash /check.sh
