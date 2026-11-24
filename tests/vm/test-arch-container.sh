#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-$(command -v podman || command -v docker || true)}"
[ -n "$RUNTIME" ] || { echo "test-arch-container: podman or docker required" >&2; exit 2; }

exec "$RUNTIME" run --rm -v "$ROOT:/src:ro" archlinux:base bash -euo pipefail -c '
    pacman -Sy --noconfirm --needed git python lua jq >/dev/null
    useradd -m tester
    su - tester -c "
        set -euo pipefail
        mkdir -p ~/kuwai
        cp -a /src/. ~/kuwai/
        cd ~/kuwai
        ./install.sh --yes --no-services
        ./install.sh --yes --no-services
        bin/kuwai-look init --no-apply >/dev/null
        bin/kuwai-home --dry-run >/dev/null
        ./install.sh --uninstall
    "
    echo "arch-container-smoke: ok"
'
