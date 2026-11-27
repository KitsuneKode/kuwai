#!/usr/bin/env bash
set -uo pipefail

usage() {
cat <<'KUWAI_USAGE'
tests/fresh/run.sh [options]: install kuwai on a fresh Arch Linux as a new user,
start a headless Hyprland session as that user, and check what a first login
needs (the shell loads, the island and lock answer, clipboard and feeds stay off,
the default theme and wallpaper are there), then uninstall and check the home
folder is put back. Everything happens in a throwaway container (systemd as its
init); nothing of this machine's home, config or session is read or written.

  --committed     test the committed HEAD (git bundle), not the working tree
  --out DIR       keep the logs, the table and screenshots in DIR
                  (default: /tmp/kuwai-fresh-TIMESTAMP)
  --keep          leave the container running afterwards (docker exec -it NAME bash)
  --gpu           pass this machine's /dev/dri/renderD128 in (hardware GL for the
                  headless compositor instead of software rendering)
  --image IMAGE   the base image (default archlinux:latest)
  --no-hostcache  don't use this machine's /var/cache/pacman/pkg as a read-only
                  package source (it makes a run minutes shorter on a slow line)
  --drop-cache    delete the container package cache volume first
  --only PHASE    run the machine and install phases plus PHASE only
                  (install, session, lock, consent, look, uninstall)
  -h, --help

Needs docker (your user in the docker group). First run downloads about 1 GB of
packages into the volume kuwai-fresh-pkgcache; later runs reuse it.
Exit 0 when every check passed, 1 when one failed, 2 when it couldn't start.
KUWAI_USAGE
exit "${1:-2}"
}

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
COMMITTED=0; KEEP=0; GPU=0; IMAGE=archlinux:latest; HOSTCACHE=1; DROP=0; ONLY=""; OUT=""
while [ $# -gt 0 ]; do
    case $1 in
        --committed) COMMITTED=1 ;;
        --keep) KEEP=1 ;;
        --gpu) GPU=1 ;;
        --no-hostcache) HOSTCACHE=0 ;;
        --drop-cache) DROP=1 ;;
        --image) shift; IMAGE=${1:-} ;;
        --out) shift; OUT=${1:-} ;;
        --only) shift; ONLY=${1:-} ;;
        -h|--help) usage 0 ;;
        *) usage ;;
    esac
    shift
done

command -v docker >/dev/null || { echo "fresh: needs docker" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "fresh: can't talk to docker (is your user in the docker group, is the daemon running?)" >&2; exit 2; }
[ -n "$OUT" ] || OUT=/tmp/kuwai-fresh-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT" || exit 2
OUT=$(cd "$OUT" && pwd)

NAME=kuwai-fresh-$$
VOL=kuwai-fresh-pkgcache
stage=$(mktemp -d)
cleanup() {
    rm -rf "$stage"
    if [ "$KEEP" = 1 ]; then echo "fresh: container $NAME left running: docker exec -it $NAME bash   (docker rm -f $NAME when done)"
    else docker rm -f "$NAME" >/dev/null 2>&1; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

[ "$DROP" = 1 ] && docker volume rm "$VOL" >/dev/null 2>&1
docker volume create "$VOL" >/dev/null || exit 2
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull -q "$IMAGE" >/dev/null || { echo "fresh: can't get $IMAGE" >&2; exit 2; }

if [ "$COMMITTED" = 1 ]; then
    git -C "$ROOT" bundle create "$stage/kuwai.bundle" HEAD >/dev/null 2>&1 || { echo "fresh: can't bundle $ROOT" >&2; exit 2; }
    echo "fresh: testing committed $(git -C "$ROOT" rev-parse --short HEAD)"
else
    (cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - -czf "$stage/src.tar.gz" 2>/dev/null) || { echo "fresh: can't pack $ROOT" >&2; exit 2; }
    echo "fresh: testing the working tree of $(git -C "$ROOT" rev-parse --short HEAD) (uncommitted changes included)"
fi
cp "$ROOT/tests/fresh/inside.sh" "$stage/inside.sh"
chmod -R a+rX "$stage"

args=(--name "$NAME" --detach --cgroupns=private --tmpfs /run --tmpfs /run/lock --tmpfs /tmp:exec
      --security-opt writable-cgroups=true --shm-size=1g
      -v "$VOL:/var/cache/pacman/pkg")
[ "$HOSTCACHE" = 1 ] && [ -r /var/cache/pacman/pkg ] && args+=(-v /var/cache/pacman/pkg:/hostcache:ro)
[ "$GPU" = 1 ] && args+=(--device /dev/dri/renderD128)
docker run "${args[@]}" "$IMAGE" /usr/lib/systemd/systemd >/dev/null || { echo "fresh: couldn't start the container" >&2; exit 2; }
for _ in $(seq 50); do
    docker exec "$NAME" systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded' && break
    sleep 0.2
done
docker cp "$stage/." "$NAME:/in" >/dev/null || exit 2

env_args=(-e "KUWAI_FRESH_ONLY=$ONLY" -e "KUWAI_FRESH_GPU=$GPU" -e "KUWAI_FRESH_HOSTCACHE=$HOSTCACHE" -e "KUWAI_FRESH_COMMITTED=$COMMITTED")
docker exec "${env_args[@]}" "$NAME" bash /in/inside.sh /in 2>&1 | tee "$OUT/run.log" | grep --line-buffered -E '^(== |PASS  |FAIL  |FAILED  |SKIP  |INFO  )'
rc=${PIPESTATUS[0]}
docker cp "$NAME:/out/." "$OUT/" >/dev/null 2>&1
echo "fresh: logs and screenshots in $OUT"
exit "$rc"
