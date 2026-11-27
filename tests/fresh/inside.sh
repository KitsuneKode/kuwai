#!/usr/bin/env bash
set -uo pipefail

usage() {
cat <<'KUWAI_USAGE'
tests/fresh/inside.sh SRCDIR: the fresh-install test, inside a throwaway Arch Linux
(a container that runs systemd as its init, or a virtual machine). Runs as
root: adds a user, installs packages, gives that user sudo, and in a VM logs
that user into a real session. Never run it on a machine you use.

SRCDIR holds src.tar.gz (the working tree) or kuwai.bundle (a git bundle).
Writes logs and screenshots to /out. Exit 0 when every check passed, 1 when one
failed. tests/fresh/run.sh (container) and tests/fresh/vm.sh start it.

Environment: KUWAI_FRESH_MODE=container|vm, KUWAI_FRESH_THROWAWAY=1 (outside a
container), KUWAI_FRESH_HOSTCACHE=1, KUWAI_FRESH_ONLY=install (skip the session),
KUWAI_FRESH_SUSPEND=1 (VM: suspend and resume once the lock is up).
KUWAI_USAGE
exit "${1:-2}"
}
case ${1:-} in -h|--help) usage 0 ;; "") usage ;; esac
IN=$1
[ "$(id -u)" = 0 ] || { echo "inside.sh: run as root, in a throwaway system" >&2; exit 2; }
[ -f /etc/arch-release ] || { echo "inside.sh: not Arch Linux" >&2; exit 2; }
[ -f /.dockerenv ] || [ -n "${KUWAI_FRESH_THROWAWAY:-}" ] || { echo "inside.sh: refusing outside a container or VM (set KUWAI_FRESH_THROWAWAY=1 if this system is disposable)" >&2; exit 2; }

MODE=${KUWAI_FRESH_MODE:-container}
ONLY=${KUWAI_FRESH_ONLY:-}
U=kuwaitest
UID_=1000
H=/home/$U
K=$H/Projects/kuwai
STABLE=$H/.local/share/kuwai
STATE=$H/.local/state/kuwai
RT=/run/user/$UID_
OUT=/out
mkdir -p "$OUT"

results=()
pass() { results+=("PASS  $1"); printf '\nPASS  %s\n' "$1"; }
fail() { results+=("FAIL  $1"); printf '\nFAIL  %s\n' "$1"; }
skip() { results+=("SKIP  $1"); printf '\nSKIP  %s\n' "$1"; }
info() { printf '\nINFO  %s\n' "$1"; }
phase() { printf '\n== %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
finish() {
    local p f k
    p=$(printf '%s\n' "${results[@]}" | grep -c '^PASS') f=$(printf '%s\n' "${results[@]}" | grep -c '^FAIL') k=$(printf '%s\n' "${results[@]}" | grep -c '^SKIP')
    printf '\n== summary: %s passed, %s failed, %s skipped\n' "$p" "$f" "$k"
    [ "$f" = 0 ] || printf '%s\n' "${results[@]}" | grep '^FAIL' | sed 's/^FAIL /FAILED/'
    echo "KUWAI-FRESH-RESULT fail=$f"
    [ "$f" = 0 ]
    exit $?
}

BASE_ENV=(HOME="$H" USER="$U" LOGNAME="$U" LANG=C.UTF-8 PATH="$H/.local/bin:/usr/local/bin:/usr/bin:/bin"
          XDG_RUNTIME_DIR="$RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$RT/bus")
as_user() { runuser -u "$U" -- env -i "${BASE_ENV[@]}" bash -c "$1"; }
SIG=""; WLD=""
as_sess() {
    runuser -u "$U" -- env -i "${BASE_ENV[@]}" WAYLAND_DISPLAY="$WLD" HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
        XDG_SESSION_TYPE=wayland KUWAI_ROOT="$STABLE" bash -c "$1"
}
snap() {
    as_user "cd ~ && find . -path ./Projects -prune -o -path ./.cache -prune -o \\( -type f -o -type l \\) -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' f; do if [ -L \"\$f\" ]; then printf '%s -> %s\\n' \"\$f\" \"\$(readlink \"\$f\")\"; else printf '%s %s\\n' \"\$f\" \"\$(sha256sum <\"\$f\" | cut -c1-16)\"; fi; done"
}
sys_snap() { find /usr/share/wayland-sessions /usr/local /etc/systemd/system /etc/sudoers.d /etc/pam.d \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort; }
wait_for() {
    local secs=$1; shift
    local end=$((SECONDS + secs))
    while [ "$SECONDS" -lt "$end" ]; do "$@" && return 0; sleep 1; done
    "$@"
}
qs_ipc() { as_sess "qs ipc -p '$STABLE/shell' call $*" 2>&1; }
qs_log() { as_sess "qs log -p '$STABLE/shell' 2>&1" | sed 's/\x1b\[[0-9;]*m//g'; }

phase "the machine: a fresh Arch ($MODE), a new user"
if [ "${KUWAI_FRESH_HOSTCACHE:-0}" = 1 ] && [ -d /hostcache ]; then
    sed -i 's|^#\?CacheDir.*|CacheDir = /var/cache/pacman/pkg/\nCacheDir = /hostcache/|' /etc/pacman.conf
fi
pkgs=(sudo git python)
if [ "$MODE" = container ]; then
    pacman -Rdd --noconfirm dbus-broker-units dbus-broker >/dev/null 2>&1
    pkgs+=(dbus-daemon-units)
fi
pacman -Syu --noconfirm --needed "${pkgs[@]}" >/dev/null 2>"$OUT/pacman-base.err" || { echo "inside.sh: pacman failed"; cat "$OUT/pacman-base.err"; exit 1; }
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash -u $UID_ "$U"
echo "$U ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/90-kuwaitest
chmod 0440 /etc/sudoers.d/90-kuwaitest
git config --system --add safe.directory '*'

if [ "$MODE" = container ]; then
    install -d -m 700 -o "$U" -g "$U" "$RT"
    systemd-run -q --unit=kuwai-fresh-usermanager --property=User="$U" --property=Delegate=yes \
        --setenv=XDG_RUNTIME_DIR="$RT" /usr/lib/systemd/systemd --user >/dev/null 2>&1
else
    loginctl enable-linger "$U"
    systemctl start "user@$UID_.service"
fi
user_manager_up() { [ "$(as_user 'systemctl --user is-system-running' 2>/dev/null)" = running ]; }
check "the user's systemd manager runs" wait_for 40 user_manager_up

mkdir -p "$H/Projects" && chown "$U:$U" "$H/Projects"
if [ -f "$IN/kuwai.bundle" ]; then
    as_user "git clone -q '$IN/kuwai.bundle' '$K'" || { echo "inside.sh: clone failed" >&2; exit 1; }
else
    install -d -o "$U" -g "$U" "$K"
    tar -xzf "$IN/src.tar.gz" -C "$K" && chown -R "$U:$U" "$K"
    as_user "cd '$K' && git init -q -b main && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -q -m 'working tree under test'" || { echo "inside.sh: can't commit the tree" >&2; exit 1; }
fi
as_user "git -C '$K' config user.email t@example.invalid; git -C '$K' config user.name t"

before=$(snap)
sys_before=$(sys_snap)
dirs_snap() { find /usr/local /usr/share/wayland-sessions /etc/systemd/system /etc/sudoers.d /var/lib/kuwai-greeter /etc/greetd -type d 2>/dev/null | LC_ALL=C sort; }
dirs_before=$(dirs_snap)
pkgs_before=$(pacman -Qq | LC_ALL=C sort)
MARK=/run/kuwai-fresh-mark
touch "$MARK"
sleep 1

phase "install: ./install.sh --deps --yes as the new user"
as_user "cd '$K' && ./install.sh --dry-run" >"$OUT/dry.log" 2>&1
check "dry run exits 0" [ $? -eq 0 ]
check "dry run changes nothing" [ "$(snap)" = "$before" ]

as_user "cd '$K' && ./install.sh --deps --yes" 2>&1 | tee "$OUT/install.log"
check "install --deps --yes exits 0" [ "${PIPESTATUS[0]}" -eq 0 ]
check "Hyprland and quickshell installed" as_user "command -v Hyprland && command -v qs"
check "Hyprland version gate (0.57 or later) passed" grep -q 'Hyprland [0-9.]* (0.57 or later)' "$OUT/install.log"
check "every core package installed" as_user "[ -z \"\$(cd '$K' && ./install.sh --print-missing)\" ]"
check "the stable channel is checked out" as_user "[ -f '$STABLE/hypr/init.lua' ] && [ \"\$(git -C '$STABLE' rev-parse --abbrev-ref HEAD)\" = stable ]"
check "migrations recorded, none pending" as_user "'$STABLE/bin/kuwai-migrations' --list | grep -q done && ! '$STABLE/bin/kuwai-migrations' --list | grep -q pending"
check "kuwai's Hyprland entry is in ~/.config/kuwai/hypr; ~/.config/hypr is untouched" as_user "cmp -s ~/.config/kuwai/hypr/hyprland.lua '$K/hypr/templates/hyprland.lua' && [ ! -e ~/.config/hypr/hyprland.lua ]"
check "the kuwai command is linked in ~/.local/bin and runs" as_user "[ -L ~/.local/bin/kuwai ] && ~/.local/bin/kuwai version | grep -q '^kuwai '"
check "the environment.d drop-in puts ~/.local/bin on the session's systemd PATH" as_user "[ -e ~/.config/environment.d/kuwai.conf ] && systemctl --user show-environment | grep -q '^PATH=.*$H/.local/bin'"
check "user units linked" as_user "for u in kuwai-shell kuwai-auth kuwai-wallpaper kuwai-clipboard kuwai-feeds kuwai-backup; do [ -L ~/.config/systemd/user/\$u.service ] || exit 1; done"
installed_snap=$(snap)
as_user "cd '$K' && ./install.sh" >"$OUT/install2.log" 2>&1
check "a second install exits 0" [ $? -eq 0 ]
check "a second install changes nothing" [ "$(snap)" = "$installed_snap" ]

as_user "sudo '$K/system/session' --trust-clone" >"$OUT/session-add.log" 2>&1
check "\"Kuwai\" is added to the login screen (system/session)" bash -c "[ -f /usr/share/wayland-sessions/kuwai.desktop ] && '$K/system/session' --check"
as_user "'$STABLE/bin/kuwai' auth pin" >"$OUT/auth-pin.log" 2>&1
PINNED=/usr/local/share/kuwai/shell-auth
check "kuwai auth pin: root's copy of the password prompt exists and no account but root can change it" bash -c "[ -f $PINNED/shell.qml ] && [ -z \"\$(find $PINNED \\( ! -user root -o -perm /022 \\))\" ] && [ -z \"\$(find $PINNED ! -type f ! -type d)\" ]"
exec_line=$(sed -n 's/^Exec=//p' /usr/share/wayland-sessions/kuwai.desktop | head -1)
check "the login entry's Exec ($exec_line) is an executable that exists" bash -c "command -v ${exec_line%% *} >/dev/null"

unowned_new() {
    local skip=(/proc /sys /dev /run /tmp /in /out /hostcache /var/cache /var/lib/pacman /var/log /var/tmp "$H")
    local prune=() d
    for d in "${skip[@]}"; do prune+=(-path "$d" -o); done
    find / -xdev \( "${prune[@]}" -false \) -prune -o \( -type f -o -type l \) -newer "$MARK" -print | LC_ALL=C sort >"$OUT/new-files.txt"
    pacman -Qlq | LC_ALL=C sort -u >"$OUT/owned-files.txt"
    LC_ALL=C comm -23 "$OUT/new-files.txt" "$OUT/owned-files.txt"
}
EXPECTED_OUTSIDE='^/usr/(local/bin/kuwai-session|local/share/kuwai/shell-auth/|share/wayland-sessions/kuwai\.desktop$)'
SYSTEM_AREAS='^/(root|opt|srv|boot|usr/local|etc/(pam\.d|sudoers\.d|greetd|systemd/system|polkit-1|udev|sysctl\.d|modprobe\.d|ssh)|var/lib/kuwai|home/)|kuwai'
outside=$(unowned_new)
printf '%s\n' "$outside" >"$OUT/outside-expected.txt"
stray=$(printf '%s\n' "$outside" | grep -E "$SYSTEM_AREAS" | grep -vE "$EXPECTED_OUTSIDE|^/etc/sudoers\.d/90-kuwaitest$|^/home/$U/" || true)
check "install wrote nothing to the system but its login entry (stray: ${stray:-none})" [ -z "$stray" ]
printf '%s\n' "$outside" | grep -E "$EXPECTED_OUTSIDE" | grep -v shell-auth/ | while read -r f; do info "outside the home, from system/session (sudo, asked): $f"; done
info "outside the home, from kuwai auth pin (sudo, asked): $(printf '%s\n' "$outside" | grep -c shell-auth/) files in /usr/local/share/kuwai/shell-auth"
others=$(printf '%s\n' "$outside" | grep -vE "$SYSTEM_AREAS" | grep -c . || true)
info "$others other files appeared outside the home that no package owns: package scriptlets and caches (pipewire's units, lastlog), listed in outside-expected.txt"

phase "first-run state: clipboard and feeds off, the default theme and wallpaper in place"
check "collect.conf says clipboard=off and feeds=off" as_user "grep -qx clipboard=off ~/.config/kuwai/collect.conf && grep -qx feeds=off ~/.config/kuwai/collect.conf"
no_enabled() { ! as_user 'systemctl --user is-enabled kuwai-clipboard.service kuwai-feeds.service' 2>/dev/null | grep -q '^enabled'; }
check "the clipboard and feeds units are not enabled" no_enabled
no_helpers() { ! pgrep -u "$U" -f 'wl-paste|cliphist|kuwai-feeds|gh api' >/dev/null; }
check "no clipboard watcher or feed helper runs" no_helpers
check "no clipboard history exists (~/.cache/cliphist)" as_user "[ ! -e ~/.cache/cliphist ]"
as_user "'$STABLE/bin/kuwai-look' init --no-apply" >"$OUT/look-init.log" 2>&1
check "the look initialises (kuwai-look init)" as_user "'$STABLE/bin/kuwai-look' status | jq -e '.initialized == true' >/dev/null"
default_theme=$(as_user "'$STABLE/bin/kuwai-look' status | jq -r '.state.theme // .palette.source.name // empty'")
check "the default theme is Kuwai Night (got: ${default_theme:-none})" bash -c "printf '%s' '$default_theme' | grep -qi 'kuwai.night'"
wall=$(as_user "readlink -f '$STATE/wallpaper'")
check "the default wallpaper is a real image ($wall)" as_user "[ -s '$wall' ] && file -b --mime-type '$wall' | grep -Eq '^image/(jpeg|png|webp)\$'"
check "the wallpaper's credits are beside it" as_user "[ -s '$STATE/wallpapers/CREDITS.txt' ]"
as_user "cd '$STABLE' && bin/kuwai-loadtest HEAD" >"$OUT/loadtest-shell.log" 2>&1
check "the shell loads offscreen (kuwai-loadtest)" [ $? -eq 0 ]
as_user "cd '$STABLE' && bin/kuwai-loadtest HEAD greeter.qml" >"$OUT/loadtest-greeter.log" 2>&1
check "the login face loads offscreen" [ $? -eq 0 ]
as_user "'$STABLE/bin/kuwai' doctor" >"$OUT/doctor-nosession.log" 2>&1
doctor_rc=$?
info "kuwai doctor with no session: exit $doctor_rc (log: doctor-nosession.log)"
sed 's/\x1b\[[0-9;]*m//g' "$OUT/doctor-nosession.log" | grep '✗' | sed 's/^ *//' | while read -r l; do info "expected with no session: $l"; done
unexpected=$(sed 's/\x1b\[[0-9;]*m//g' "$OUT/doctor-nosession.log" | grep '✗' | grep -vE 'verify-config crashed|polkit agent|Notifications owner|shell is not running|shell compile check' || true)
check "kuwai doctor with no session fails only on what needs a session (other: ${unexpected:-none})" [ -z "$unexpected" ]

phase "unlock: the PAM path the lock screen uses, with the test user's password"
PW="kuwai-fresh-$RANDOM-$RANDOM"
echo "$U:$PW" | chpasswd
check "the test user has a password (chpasswd)" bash -c "[ \"\$(passwd -S $U | cut -d' ' -f2)\" = P ]"
check "the login PAM stack the lock names exists (/etc/pam.d/login)" [ -f /etc/pam.d/login ]
pam_result() {
    as_user "cd '$K/tests/fresh/pamcheck' && KUWAI_PAM_USER=$U KUWAI_PAM_PASSWORD=$(printf %q "$1") QT_QPA_PLATFORM=offscreen timeout -k 2 25 qs -p . 2>&1" \
        | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/.*PAM-RESULT //p' | tail -1
}
r_wrong=$(pam_result "not-the-password")
echo "$r_wrong" >"$OUT/pam-wrong.txt"
check "Quickshell's PamContext on 'login' refuses a wrong password (got: ${r_wrong:-nothing})" [ "$r_wrong" = failed ]
r_empty=$(pam_result "")
check "and an empty one (got: ${r_empty:-nothing})" [ "$r_empty" = failed ]
r_right=$(pam_result "$PW")
echo "$r_right" >"$OUT/pam-right.txt"
check "and accepts the right one (got: ${r_right:-nothing})" [ "$r_right" = success ]

session_possible=0
if [ "$ONLY" = install ]; then skip "the session phase (KUWAI_FRESH_ONLY=install)"
elif [ "$MODE" = vm ]; then session_possible=1
else skip "headless Hyprland session: a container has no KMS device, and Hyprland 0.57's Aquamarine needs a seat + DRM backend or a parent compositor with xdg-shell v6 (sway/weston/labwc stop at v5): run tests/fresh/vm.sh"
fi

if [ $session_possible = 1 ]; then
phase "session: Hyprland started the way the login screen starts it (a logind session on tty1)"
cat >/etc/systemd/system/kuwai-fresh-session.service <<UNIT
[Unit]
Description=kuwai fresh test: the Kuwai session on tty1
After=systemd-user-sessions.service
Conflicts=getty@tty1.service
After=getty@tty1.service
[Service]
User=$U
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYReset=yes
TTYVHangup=yes
UtmpIdentifier=tty1
UtmpMode=user
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_SESSION_CLASS=user
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=XDG_SESSION_DESKTOP=Hyprland
Environment=LIBGL_ALWAYS_SOFTWARE=1
Environment=WLR_RENDERER_ALLOW_SOFTWARE=1
ExecStart=$exec_line
UNIT
systemctl daemon-reload
systemctl start kuwai-fresh-session.service
sock_up() {
    SIG=$(find "$RT/hypr" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
    [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ]
}
check "Hyprland's socket comes up" wait_for 60 sock_up
if [ -z "$SIG" ]; then
    journalctl -u kuwai-fresh-session -n 80 --no-pager >"$OUT/session-start-failure.log" 2>&1
    tail -30 "$OUT/session-start-failure.log"
    fail "Hyprland never started (journal: session-start-failure.log)"
    finish
fi
WLD=$(find "$RT" -maxdepth 1 -regex '.*/wayland-[0-9]+' -printf '%f\n' | head -1)
mon_up() { as_sess "hyprctl -j monitors" | jq -e 'length > 0' >/dev/null 2>&1; }
check "a monitor exists" wait_for 30 mon_up
SCREEN=$(as_sess "hyprctl -j monitors" | jq -r '.[0].name')
check "the session's loginctl state is a graphical session on seat0" bash -c "loginctl list-sessions --no-legend | grep -q $U"
check "no config errors in the live Hyprland (hyprctl configerrors)" bash -c "[ -z \"\$(runuser -u $U -- env -i ${BASE_ENV[*]} WAYLAND_DISPLAY=$WLD HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl configerrors | tr -d '[:space:]')\" ]"

shell_loaded() { qs_log | grep -q 'Configuration Loaded'; }
check "the shell loads (Configuration Loaded in its log)" wait_for 90 shell_loaded
qs_log >"$OUT/shell.qslog.txt"
check "no 'Failed to load' in the shell's log" bash -c "! grep -q 'Failed to load' '$OUT/shell.qslog.txt'"
check "kuwai-shell.service is the one running the shell" as_user "systemctl --user is-active kuwai-shell.service | grep -qx active"
VM_ERRORS='Failed to find render device|Failed to connect pipewire context|Could not find an available backend'
grep -E 'WARN|ERROR' "$OUT/shell.qslog.txt" | sort | uniq -c | sort -rn | head -20 >"$OUT/shell-warnings.txt"
shell_errors() { qs_log | grep -E '(^| )ERROR' | grep -vE "$VM_ERRORS"; }
check "the shell's log has no ERROR lines beyond this VM's own (no GPU render node, no network manager, no audio server)" bash -c "! grep -E '(^| )ERROR' '$OUT/shell.qslog.txt' | grep -vE '$VM_ERRORS'"
grep -E '(^| )ERROR' "$OUT/shell.qslog.txt" | grep -E "$VM_ERRORS" | sed 's/^/        /' | while read -r l; do info "expected here: ${l#"${l%%[![:space:]]*}"}"; done
grep -E 'WARN: Quickshell was built against' "$OUT/shell.qslog.txt" >/dev/null && info "Quickshell's package is built against an older Qt than the system's (the Arch package needs a rebuild; crashes are likely until then)"
as_user "systemctl --user is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service 2>&1" >"$OUT/audio-units.txt"
info "audio user units on a fresh install: $(tr '\n' ' ' <"$OUT/audio-units.txt")"

phase "the island: every panel opens as a preview and closes"
island_ready() { [ "$(qs_ipc island state)" = none ]; }
check "the island answers over qs ipc (island state = none)" wait_for 30 island_ready
panels="activities calendar power launcher settings system theme keys switcher updates media agents usage read cleanup notifications controls welcome"
bad=""
for p in $panels; do
    qs_ipc test preview "$p" "$SCREEN" >/dev/null
    sleep 0.5
    st=$(qs_ipc island state)
    case $st in "$p "*|"$p") ;; *) bad="$bad $p($st)" ;; esac
    qs_ipc island close >/dev/null
done
check "all $(wc -w <<<"$panels") panels open on $SCREEN (wrong:${bad:- none})" [ -z "$bad" ]
panel_errors() { [ -z "$(shell_errors)" ]; }
check "the panels left no ERROR lines in the shell's log" panel_errors
as_sess "grim -t ppm '$OUT/island.ppm'" >/dev/null 2>&1
if [ -s "$OUT/island.ppm" ]; then
    colours=$(python3 - "$OUT/island.ppm" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
parts = d.split(b"\n", 3)
px = parts[3] if len(parts) > 3 else b""
print(len({px[i:i+3] for i in range(0, min(len(px), 3_000_000), 3)}))
PY
)
    check "a screenshot of the session isn't one flat colour ($colours colours)" [ "${colours:-0}" -gt 20 ]
else
    fail "grim can take a screenshot of the session"
fi

phase "the lock: lock over qs ipc, read the state, survive a shell restart"
qs_ipc lock lock >/dev/null
lock_state() { [ "$(qs_ipc lock state)" = locked ]; }
check "lock lock → lock state becomes 'locked' (the compositor confirmed)" wait_for 20 lock_state
as_sess "grim -t ppm '$OUT/locked.ppm'" >/dev/null 2>&1
as_user "systemctl --user restart kuwai-shell.service" >/dev/null 2>&1
check "the shell is back after a restart" wait_for 60 shell_loaded
check "the session is still locked after the shell restarted" wait_for 30 lock_state

phase "unlock: the password typed into the lock (this session is the test user's own: wtype is allowed here)"
pacman -S --needed --noconfirm wtype >/dev/null 2>&1
type_in() { as_sess "wtype -s 60 -- $(printf %q "$1") && wtype -k Return"; }
type_in "not-the-password"
sleep 3
check "a wrong password leaves the session locked" lock_state
as_sess "grim -t ppm '$OUT/locked-wrong.ppm'" >/dev/null 2>&1
check "the lock shows the refusal (its screen differs from the plain locked one)" bash -c "[ -s '$OUT/locked-wrong.ppm' ] && ! cmp -s '$OUT/locked.ppm' '$OUT/locked-wrong.ppm'"
type_in "$PW"
unlocked() { [ "$(qs_ipc lock state)" = unlocked ]; }
check "the right password unlocks it (lock state becomes 'unlocked')" wait_for 20 unlocked
qs_log >"$OUT/shell.after-unlock.qslog.txt"
check "the unlock left no 'Failed to load' or ERROR lines of its own" bash -c "! grep -E 'Failed to load' '$OUT/shell.after-unlock.qslog.txt' && ! grep -E '(^| )ERROR' '$OUT/shell.after-unlock.qslog.txt' | grep -vE '$VM_ERRORS'"
qs_ipc lock lock >/dev/null
check "it locks again after an unlock" wait_for 20 lock_state

if [ "${KUWAI_FRESH_SUSPEND:-0}" = 1 ]; then
    phase "suspend and resume while locked"
    journalctl -f -n0 -o short-monotonic -p info >/dev/ttyS0 2>&1 &
    pid_before=$(as_user "systemctl --user show -p MainPID --value kuwai-shell.service")
    n_before=$(journalctl -k -b --no-pager | grep -c 'PM: suspend entry')
    echo "KUWAI-FRESH-SUSPEND"
    systemctl suspend >"$OUT/suspend.log" 2>&1
    check "systemctl suspend returned after the guest woke (rc=$?)" [ $? -eq 0 ]
    sleep 3
    n_after=$(journalctl -k -b --no-pager | grep -c 'PM: suspend entry')
    check "the kernel really suspended and resumed (PM: suspend entry $n_before → $n_after)" [ "$n_after" -gt "$n_before" ]
    check "the shell survived suspend and resume (pid $pid_before)" bash -c "[ \"\$(runuser -u $U -- env -i ${BASE_ENV[*]} systemctl --user show -p MainPID --value kuwai-shell.service)\" = '$pid_before' ]"
    check "the session is still locked after resume" wait_for 20 lock_state
fi

type_in "$PW"
check "the right password unlocks it again (after the suspend, when there was one)" wait_for 20 unlocked

phase "consent in a live session: clipboard and feeds only start when asked"
as_sess "wl-copy 'kuwai-fresh-secret-1'" >/dev/null 2>&1
sleep 2
check "copying text with clipboard=off stores nothing" as_user "! { [ -d ~/.cache/cliphist ] && ls -A ~/.cache/cliphist | grep -q .; }"
check "no wl-paste watcher runs" bash -c "! pgrep -u $U -x wl-paste >/dev/null"
check "the clipboard unit stays inactive" bash -c "! runuser -u $U -- env -i ${BASE_ENV[*]} systemctl --user is-active kuwai-clipboard.service | grep -qx active"
as_sess "kuwai collect clipboard on" >"$OUT/collect-on.log" 2>&1
clip_on() { pgrep -u "$U" -x wl-paste >/dev/null; }
check "kuwai collect clipboard on starts the watchers" wait_for 15 clip_on
as_sess "kuwai collect clipboard off" >"$OUT/collect-off.log" 2>&1
clip_off() { ! pgrep -u "$U" -x wl-paste >/dev/null; }
check "kuwai collect clipboard off stops them" wait_for 15 clip_off
check "the feeds helper never ran" bash -c "! pgrep -u $U -f 'kuwai-feeds' >/dev/null"

phase "health: kuwai doctor and kuwai-check in the live session"
as_sess "'$STABLE/bin/kuwai' doctor" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' >"$OUT/doctor.log"
as_sess "'$STABLE/bin/kuwai-check'" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' >"$OUT/kuwai-check.log"
PERF='✗ (memory|cpu|wakeups):'
hard=$(grep '✗' "$OUT/doctor.log" "$OUT/kuwai-check.log" | sed 's/^[^:]*://' | grep -vE "$PERF" | sort -u)
helpers_extra=$(sed -n '/✗ helpers:/,/^  [✓✗•]/p' "$OUT/kuwai-check.log" | grep -E '^ +[0-9]+ \(' | grep -v 'brightness-client' || true)
[ -z "$helpers_extra" ] && hard=$(printf '%s\n' "$hard" | grep -v '✗ helpers:')
check "kuwai doctor and kuwai-check: nothing failed beyond the GPU-sized budgets (hard: ${hard:- none})" [ -z "$(printf '%s' "$hard" | tr -d '[:space:]')" ]
grep -hE "$PERF" "$OUT/kuwai-check.log" | sort -u | while read -r l; do info "software rendering: $l"; done
grep -q 'brightness-client' "$OUT/kuwai-check.log" && info "kuwai-check flags brightness-client.py (watch --part osd) as a stray child of the shell on a machine with no backlight"

phase "log out"
as_sess "hyprctl dispatch 'hl.dsp.exit()'" >/dev/null 2>&1
gone() { ! pgrep -u "$U" -x Hyprland >/dev/null; }
check "Hyprland exits and the session ends" wait_for 30 gone
sleep 3
no_orphans() { ! pgrep -u "$U" -f "$STABLE/shell|kuwai-" -a | grep -v 'systemd' | grep -q .; }
if no_orphans; then pass "nothing of kuwai's keeps running after logout"
else fail "kuwai helpers outlive the session: $(pgrep -u "$U" -a | grep -iE 'kuwai|qs ' | head -5 | tr '\n' ';')"; fi
journalctl -u kuwai-fresh-session --no-pager >"$OUT/session.journal" 2>&1
fi

phase "greeter: greeter/install --yes writes the login screen's config here, then --undo puts it back"
G=/var/lib/kuwai-greeter
g_hash() { { sha256sum /etc/pam.d/greetd /etc/greetd/config.toml 2>&1; readlink -f /etc/systemd/system/display-manager.service 2>&1; } | sed 's/ \+/ /g'; }
pacman -S --needed --noconfirm greetd rsync >/dev/null 2>"$OUT/pacman-greetd.err"
check "greetd and rsync install from the official repos" bash -c "pacman -Q greetd rsync >/dev/null"
g_before=$(g_hash)
yes | as_user "cd '$K' && sudo ./greeter/install --trust-clone --yes" >"$OUT/greeter-install.log" 2>&1
check "greeter/install --yes exits 0" [ "${PIPESTATUS[1]}" -eq 0 ]
check "/etc/greetd/config.toml starts the greeter's compositor as user greeter on vt 1" bash -c "grep -qx 'command = \"$G/compositor-start\"' /etc/greetd/config.toml && grep -qx 'user = \"greeter\"' /etc/greetd/config.toml && grep -qx 'vt = 1' /etc/greetd/config.toml"
check "/etc/pam.d/greetd includes the system login stack" bash -c "grep -q 'auth *include *system-login' /etc/pam.d/greetd"
check "the greeter's code is root's: root-owned, no links, start scripts executable" bash -c "[ -z \"\$(find $G/shell $G/start $G/session-start $G/compositor-start $G/keys $G/hyprland.lua ! -user root)\" ] && [ -z \"\$(find $G/shell ! -type f ! -type d)\" ] && [ -x $G/compositor-start ] && [ -x $G/start ]"
check "the greeter's code is the committed revision ($(cut -c1-9 "$G/code-revision" 2>/dev/null))" bash -c "[ \"\$(cut -c1-40 $G/code-revision)\" = \"\$(git -C '$K' rev-parse HEAD)\" ]"
check "the login screen can read the user's name as the greeter account" bash -c "runuser -u greeter -- test -r $G/home/.kuwai-user && [ \"\$(runuser -u greeter -- cat $G/home/.kuwai-user)\" = $U ]"
check "greetd.service is enabled for the next boot" bash -c "systemctl is-enabled greetd.service | grep -qx enabled"
as_user "cd '$K' && sudo ./greeter/install --trust-clone --code" >"$OUT/greeter-code.log" 2>&1
check "greeter/install --code (just the code, again) exits 0" [ $? -eq 0 ]
yes | as_user "cd '$K' && sudo ./greeter/install --trust-clone --undo" >"$OUT/greeter-undo.log" 2>&1
check "greeter/install --undo exits 0" [ "${PIPESTATUS[1]}" -eq 0 ]
check "greetd is off again and its package config is as it was" bash -c "! systemctl is-enabled greetd.service 2>/dev/null | grep -qx enabled"
g_after=$(g_hash)
check "/etc/pam.d/greetd, /etc/greetd/config.toml and the display manager link are as before" [ "$g_after" = "$g_before" ]
check "greeter/install --undo took root's copy of the login screen ($G) with it" bash -c "[ ! -e $G ]"
info "left by greeter/install --undo: the packages greetd and rsync (pacman -Rns greetd rsync removes them)"

phase "uninstall: ./install.sh --uninstall puts back what was there"
as_user "cd '$K' && ./install.sh --uninstall" >"$OUT/uninstall.log" 2>&1
rc=$?
check "uninstall exits 0" [ $rc -eq 0 ]
if [ $rc -ne 0 ]; then
    tail -6 "$OUT/uninstall.log"
    as_user "cd '$K' && ./install.sh --uninstall" >"$OUT/uninstall2.log" 2>&1
    check "running uninstall again, as it says, exits 0" [ $? -eq 0 ]
fi
as_user "'$STABLE/bin/kuwai' auth unpin" >"$OUT/auth-unpin.log" 2>&1
check "kuwai auth unpin removes root's copy" bash -c "[ ! -e $PINNED ]"
as_user "sudo '$K/system/session' --undo" >"$OUT/session-undo.log" 2>&1
check "the login entry is gone" bash -c "[ ! -e /usr/share/wayland-sessions/kuwai.desktop ] && [ ! -e /usr/local/bin/kuwai-session ]"
as_user "rm -rf ~/.local/share/kuwai"
after=$(snap)
norm() { LC_ALL=C sort; }
left=$(LC_ALL=C comm -13 <(printf '%s\n' "$before" | norm) <(printf '%s\n' "$after" | norm) | grep -vE '^\./\.(config|local/state)/kuwai/' || true)
changed=$(LC_ALL=C comm -23 <(printf '%s\n' "$before" | norm) <(printf '%s\n' "$after" | norm) | grep -vE '^\./\.(config|local/state)/kuwai/' || true)
placed=$(LC_ALL=C comm -13 <(printf '%s\n' "$before" | norm) <(printf '%s\n' "$installed_snap" | norm) | grep -vE '^\./\.(config|local/state)/kuwai/' | awk '{print $1}')
mine=""
for f in $placed; do printf '%s\n' "$left" | awk '{print $1}' | grep -qxF -- "$f" && mine="$mine $f"; done
check "everything install placed is gone (left:${mine:- none})" [ -z "$mine" ]
extra=$(printf '%s\n' "$left" | awk 'NF {print $1}' | grep -vxF -f <(printf '%s\n' "$placed") || true)
[ -z "$extra" ] || info "files that appeared during the run and aren't from install.sh (the session's own, e.g. caches, crash reports): $(printf '%s' "$extra" | tr '\n' ' ')"
if [ -n "$changed" ]; then printf '%s\n' "$changed" >"$OUT/uninstall-changed.txt"; fail "files that were there before were changed or removed: $(printf '%s' "$changed" | head -5 | tr '\n' ' ')"
else pass "every file that was there before is as it was"; fi
sys_snap >"$OUT/sys-after.txt"; printf '%s\n' "$sys_before" >"$OUT/sys-before.txt"
sys_new=$(comm -13 "$OUT/sys-before.txt" "$OUT/sys-after.txt" | grep -vE 'kuwai-fresh|90-kuwaitest' | while read -r f; do pacman -Qo "$f" >/dev/null 2>&1 || echo "$f"; done)
check "system paths (login entries, units, /usr/local) are as before (new:${sys_new:- none})" [ -z "$sys_new" ]

dirs_after=$(dirs_snap)
left_dirs=$(LC_ALL=C comm -13 <(printf '%s\n' "$dirs_before") <(printf '%s\n' "$dirs_after") | grep -vE '^/etc/greetd$|^/etc/systemd/system/.*\.wants$' | while read -r d; do pacman -Qo "$d" >/dev/null 2>&1 || echo "$d"; done)
check "no directories left behind outside the home (left:${left_dirs:- none})" [ -z "$left_dirs" ]
{
    echo "what is left after install, the login entry, the pinned prompt and the greeter were each put back:"
    echo "-- the home folder: kuwai's own folders (kept on purpose; install.sh says so)"
    as_user "cd ~ && find .config/kuwai .local/state/kuwai .local/share/kuwai-data .cache/kuwai .config/gtk-3.0 .config/gtk-4.0 .config/qt6ct -type f 2>/dev/null | LC_ALL=C sort" || true
    echo "-- the home folder: anything else new"
    printf '%s\n' "$left" | awk 'NF {print $1}'
    echo "-- outside the home"
    find /var/lib/kuwai-greeter /usr/local/share/kuwai /usr/local/bin/kuwai-session /usr/share/wayland-sessions/kuwai.desktop -maxdepth 0 2>/dev/null
    echo "-- packages added (install.sh --deps never removes packages)"
    LC_ALL=C comm -13 <(printf '%s\n' "$pkgs_before") <(pacman -Qq | LC_ALL=C sort)
} >"$OUT/remains.txt"
info "left behind: $(grep -c . "$OUT/remains.txt") lines in remains.txt (home: $(as_user 'cd ~ && find .config/kuwai .local/state/kuwai -type f 2>/dev/null | wc -l') files of kuwai's own settings and records; outside the home: $(find /var/lib/kuwai-greeter /usr/local/share/kuwai /usr/local/bin/kuwai-session /usr/share/wayland-sessions/kuwai.desktop -maxdepth 0 2>/dev/null | wc -l) paths; packages added: $(LC_ALL=C comm -13 <(printf '%s\n' "$pkgs_before") <(pacman -Qq | LC_ALL=C sort) | wc -l))"

finish
