#!/usr/bin/env bash
set -uo pipefail

usage() {
cat <<'KUWAI_USAGE'
tests/fresh/vm.sh [options]: the same checks as tests/fresh/run.sh, in a virtual
machine: a real boot, real logind and PAM, a real login session on tty1 (the one
the login screen would start), Hyprland on a virtual KMS display (bochs VGA), and with
--suspend a real suspend and resume while locked. It is the only way to run
Hyprland 0.57 without a GPU or a screen: a container has no KMS device.

Nothing is downloaded but packages: the guest's disk is built from the
archlinux:latest docker image plus the linux-zen kernel (once, about 3 GB sparse,
kept in the cache directory), each run boots a copy-on-write overlay of it, and
the guest installs kuwai the way a stranger would (./install.sh --deps --yes).
Test files go in on a second disk; logs and screenshots come back the same way.

  --rebuild        build the base disk again (pulls the newest archlinux image)
  --cache DIR      where the base disk lives (default ~/.cache/kuwai-fresh-vm)
  --out DIR        logs (default /tmp/kuwai-fresh-vm-TIMESTAMP)
  --mem MB         guest memory (default 6144)
  --cpus N         guest CPUs (default 4)
  --suspend        suspend the guest while the session is locked and wake it
                   over QMP; then check the lock held and the shell survived
  --interactive    keep the VM up with a window (GTK) when the checks are done:
                   it's a fresh machine with kuwai installed, user kuwaitest
  --only install   install and uninstall only (no session)
  --no-hostcache   don't share this machine's /var/cache/pacman/pkg (read-only, 9p)
  --no-kvm         run without KVM (very slow)
  -h, --help

Needs docker (builds the disk), qemu-system-x86_64, qemu-img, e2fsprogs,
python3, and a readable /boot-independent kernel from the linux-zen package
(the build installs its own). Exit 0 when every check passed, 1 when one
failed, 2 when it couldn't start.
KUWAI_USAGE
exit "${1:-2}"
}

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/kuwai-fresh-vm; OUT=""; MEM=6144; CPUS=4; SUSPEND=0; INTERACTIVE=0; KVM=1; REBUILD=0; HOSTCACHE=1; ONLY=""
while [ $# -gt 0 ]; do
    case $1 in
        --rebuild) REBUILD=1 ;;
        --cache) shift; CACHE=${1:-} ;;
        --out) shift; OUT=${1:-} ;;
        --mem) shift; MEM=${1:-} ;;
        --cpus) shift; CPUS=${1:-} ;;
        --suspend) SUSPEND=1 ;;
        --interactive) INTERACTIVE=1 ;;
        --only) shift; ONLY=${1:-} ;;
        --no-hostcache) HOSTCACHE=0 ;;
        --no-kvm) KVM=0 ;;
        -h|--help) usage 0 ;;
        *) usage ;;
    esac
    shift
done

for c in docker qemu-system-x86_64 qemu-img mke2fs debugfs python3; do
    command -v "$c" >/dev/null || { echo "vm: needs $c" >&2; exit 2; }
done
docker info >/dev/null 2>&1 || { echo "vm: can't talk to docker (it builds the disk)" >&2; exit 2; }
ACCEL=(-enable-kvm -cpu host)
if [ $KVM = 1 ] && [ ! -w /dev/kvm ]; then echo "vm: /dev/kvm isn't writable (your user in the kvm group?); --no-kvm runs without it" >&2; exit 2; fi
[ $KVM = 1 ] || ACCEL=(-cpu max)

[ -n "$OUT" ] || OUT=/tmp/kuwai-fresh-vm-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT" "$CACHE" || exit 2
OUT=$(cd "$OUT" && pwd); CACHE=$(cd "$CACHE" && pwd)

if [ $REBUILD = 1 ] || [ ! -f "$CACHE/base.img" ] || [ ! -f "$CACHE/vmlinuz" ] || [ ! -f "$CACHE/initramfs.img" ]; then
    echo "vm: building the base disk (once; a few minutes)"
    docker volume create kuwai-fresh-pkgcache >/dev/null
    hc=(); [ $HOSTCACHE = 1 ] && [ -r /var/cache/pacman/pkg ] && hc=(-v /var/cache/pacman/pkg:/hostcache:ro)
    rm -f "$CACHE/base.img" "$CACHE/vmlinuz" "$CACHE/initramfs.img"
    cat >"$CACHE/build.sh" <<'BUILD'
set -eu
trap 'chown -R "$HUID:$HGID" /w; chmod a+r /w/* 2>/dev/null' EXIT
[ -d /hostcache ] && sed -i 's|^#\?CacheDir.*|CacheDir = /var/cache/pacman/pkg/\nCacheDir = /hostcache/|' /etc/pacman.conf
pacman -Syu --noconfirm --needed linux-zen mkinitcpio e2fsprogs >/dev/null
kver=$(ls /usr/lib/modules | head -1)
cp "/usr/lib/modules/$kver/vmlinuz" /w/vmlinuz
mkinitcpio -k "$kver" -g /w/initramfs.img -S autodetect >/dev/null 2>&1
mkdir -p /rootfs
tar -c --one-file-system --exclude=./w --exclude=./hostcache --exclude=./rootfs --exclude=./var/cache/pacman/pkg -f - -C / . | tar -x -C /rootfs
cd /rootfs
mkdir -p proc sys dev run tmp var/cache/pacman/pkg hostcache in
echo kuwai-fresh >etc/hostname
echo '127.0.0.1 localhost' >etc/hosts
echo 'nameserver 10.0.2.3' >etc/resolv.conf
: >etc/machine-id
printf '[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n' >etc/systemd/network/20-dhcp.network
mkdir -p etc/systemd/system/multi-user.target.wants etc/systemd/system/network-online.target.wants
ln -sf /usr/lib/systemd/system/systemd-networkd.service etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /usr/lib/systemd/system/systemd-networkd-wait-online.service etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
printf 'passwd: files\ngroup: files\nshadow: files\ngshadow: files\nhosts: files dns\n' >etc/nsswitch.conf
install -m 0755 /w/boot.sh usr/local/sbin/kuwai-fresh-boot
cat >etc/systemd/system/kuwai-fresh.service <<'UNIT'
[Unit]
Description=kuwai fresh install test
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kuwai-fresh-boot
TimeoutStartSec=infinity
StandardOutput=journal+console
StandardError=journal+console
[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/kuwai-fresh.service etc/systemd/system/multi-user.target.wants/kuwai-fresh.service
mke2fs -q -t ext4 -L kuwairoot -d /rootfs /w/base.img 12G
BUILD
    cat >"$CACHE/boot.sh" <<'BOOT'
#!/bin/bash
exec >/dev/ttyS1 2>&1
mkdir -p /in /hostcache
mount -t ext4 /dev/disk/by-label/KWSEED /in || { echo "KUWAI-FRESH-DONE rc=2"; poweroff; }
mount -t 9p -o trans=virtio,version=9p2000.L,ro,msize=1048576 hostcache /hostcache 2>/dev/null && hc=1 || hc=0
mkdir -p /in/out
rm -rf /out
ln -sfn /in/out /out
KUWAI_FRESH_MODE=vm KUWAI_FRESH_THROWAWAY=1 KUWAI_FRESH_HOSTCACHE=$hc KUWAI_FRESH_ONLY="$(cat /in/only 2>/dev/null)" KUWAI_FRESH_SUSPEND="$(cat /in/suspend 2>/dev/null)" bash /in/inside.sh /in
rc=$?
sync
echo "KUWAI-FRESH-DONE rc=$rc"
[ -e /in/interactive ] || { umount /in; poweroff; }
BOOT
    docker run --rm -e HUID="$(id -u)" -e HGID="$(id -g)" "${hc[@]}" -v kuwai-fresh-pkgcache:/var/cache/pacman/pkg -v "$CACHE:/w" archlinux:latest bash /w/build.sh || { echo "vm: building the base disk failed" >&2; rm -f "$CACHE/base.img"; exit 2; }
    chmod a+r "$CACHE"/vmlinuz "$CACHE"/initramfs.img "$CACHE"/base.img 2>/dev/null
fi

qemu_pid=""
w=$CACHE/run-$$
mkdir -p "$w/seed"
trap 'kill $qemu_pid 2>/dev/null; rm -rf "$w"' EXIT
(cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - -czf "$w/seed/src.tar.gz")
cp "$ROOT/tests/fresh/inside.sh" "$w/seed/inside.sh"
printf '%s' "$ONLY" >"$w/seed/only"
printf '%s' "$SUSPEND" >"$w/seed/suspend"
[ $INTERACTIVE = 1 ] && : >"$w/seed/interactive"
mkdir -p "$w/seed/out"
mke2fs -q -t ext4 -L KWSEED -d "$w/seed" "$w/seed.img" 1G || exit 2
qemu-img create -q -f qcow2 -F raw -b "$CACHE/base.img" "$w/disk.qcow2" || exit 2

qmp=$w/qmp.sock
fs=()
[ $HOSTCACHE = 1 ] && [ -r /var/cache/pacman/pkg ] && fs=(-virtfs "local,path=/var/cache/pacman/pkg,mount_tag=hostcache,security_model=none,readonly=on")
display=(-display none)
[ $INTERACTIVE = 1 ] && display=(-display gtk)
qemu-system-x86_64 "${ACCEL[@]}" -machine q35 -m "$MEM" -smp "$CPUS" \
    -kernel "$CACHE/vmlinuz" -initrd "$CACHE/initramfs.img" \
    -append "root=LABEL=kuwairoot rw console=ttyS0 net.ifnames=0 systemd.show_status=0 quiet loglevel=3" \
    -drive file="$w/disk.qcow2",if=virtio,format=qcow2 -drive file="$w/seed.img",if=virtio,format=raw \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -device VGA -device qemu-xhci -device usb-kbd -device usb-tablet \
    "${fs[@]}" -serial "file:$OUT/console.log" -serial "file:$OUT/serial.log" -qmp "unix:$qmp,server=on,wait=off" \
    "${display[@]}" -no-reboot &
qemu_pid=$!
echo "vm: booted (qemu $qemu_pid); the test's output: $OUT/serial.log, the boot console: $OUT/console.log"

qmp_cmd() {
    python3 - "$qmp" "$1" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(sys.argv[1]); f = s.makefile("rw")
f.readline(); f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush(); f.readline()
f.write(json.dumps({"execute": sys.argv[2]}) + "\n"); f.flush()
while True:
    line = f.readline()
    if not line: break
    d = json.loads(line)
    if "return" in d or "error" in d:
        print(json.dumps(d.get("return", d))); break
PY
}

start=$SECONDS; woke=0; shown=0
until grep -aq 'KUWAI-FRESH-DONE' "$OUT/serial.log" 2>/dev/null; do
    kill -0 "$qemu_pid" 2>/dev/null || { echo "vm: qemu exited before the test finished" >&2; break; }
    [ $((SECONDS - start)) -gt 5400 ] && { echo "vm: gave up after 90 minutes" >&2; break; }
    if [ $SUSPEND = 1 ] && grep -aq 'KUWAI-FRESH-SUSPEND' "$OUT/serial.log" 2>/dev/null && qmp_cmd query-status 2>/dev/null | grep -q '"suspended"'; then
        [ $woke = 0 ] && echo "vm: the guest is suspended; waking it"
        sleep 2; qmp_cmd system_wakeup >/dev/null 2>&1; woke=$((woke + 1))
    fi
    n=$(grep -acE '^(== |PASS  |FAIL  |SKIP  |INFO  )' "$OUT/serial.log" 2>/dev/null); n=${n:-0}
    if [ "$n" != "$shown" ]; then grep -aE '^(== |PASS  |FAIL  |SKIP  |INFO  )' "$OUT/serial.log" | tail -n +$((shown + 1)); shown=$n; fi
    sleep 3
done
grep -aE '^(== |PASS  |FAIL  |SKIP  |INFO  )' "$OUT/serial.log" | tail -n +$((shown + 1))
rc=$(sed -n 's/.*KUWAI-FRESH-DONE rc=\([0-9]*\).*/\1/p' "$OUT/serial.log" | tail -1)
if [ $INTERACTIVE = 1 ]; then echo "vm: left running; log in as kuwaitest (a console login: password isn't set; use the serial log). Ctrl-C to stop."; wait "$qemu_pid"; fi
kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null
debugfs -R "rdump /out $OUT" "$w/seed.img" >/dev/null 2>&1
echo "vm: logs and screenshots in $OUT/out, the test's output in $OUT/serial.log"
[ "${rc:-2}" = 0 ]
