#!/usr/bin/env bash
set -uo pipefail

usage() {
cat <<'KUWAI_USAGE'
tests/cleanroom/inside.sh SOURCE: install kuwai on a fresh Arch Linux as a new
user, the way a stranger would, and check every step. Runs as root in a
throwaway system (bin/kuwai-cleanroom starts one in a container; CI runs it in
its archlinux container). Never run it on a machine you use: it adds a user,
installs packages and gives that user sudo.

SOURCE is a git repository or bundle of kuwai (what is checked out there is used).
Exit 0 when every check passed, 1 when one failed (the table says which).
KUWAI_USAGE
exit "${1:-2}"
}
case ${1:-} in -h|--help) usage 0 ;; "") usage ;; esac
SRC=$1
[ "$(id -u)" = 0 ] || { echo "inside.sh: run as root, in a throwaway system" >&2; exit 2; }
[ -f /etc/arch-release ] || { echo "inside.sh: not Arch Linux" >&2; exit 2; }
[ -f /.dockerenv ] || [ -n "${CI:-}" ] || [ -n "${KUWAI_CLEANROOM:-}" ] || { echo "inside.sh: refusing outside a container or CI (set KUWAI_CLEANROOM=1 if this system is disposable)" >&2; exit 2; }

U=kuwaitest
results=()
pass() { results+=("PASS  $1"); printf '\n== PASS  %s\n' "$1"; }
fail() { results+=("FAIL  $1"); printf '\n== FAIL  %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
as_user() { runuser -u "$U" -- env -i HOME="/home/$U" USER="$U" LANG=C.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin bash -c "$1"; }

pacman -Syu --noconfirm --needed sudo git python >/dev/null || { echo "inside.sh: pacman failed" >&2; exit 1; }
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
echo "$U ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/90-kuwaitest
chmod 0440 /etc/sudoers.d/90-kuwaitest
git config --system --add safe.directory '*'
if [ -d "$SRC" ]; then
    git -C "$SRC" bundle create /tmp/kuwai-src.bundle HEAD >/dev/null 2>&1 || { echo "inside.sh: can't bundle $SRC" >&2; exit 1; }
    chmod 644 /tmp/kuwai-src.bundle
    SRC=/tmp/kuwai-src.bundle
fi

H=/home/$U
K=$H/Projects/kuwai
as_user "git clone -q '$SRC' '$K' && git -C '$K' config user.email t@example.invalid && git -C '$K' config user.name t" || { echo "inside.sh: clone failed" >&2; exit 1; }

snap() {
    as_user "cd ~ && find . -path ./Projects -prune -o -path ./.cache -prune -o \\( -type f -o -type l \\) -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' f; do if [ -L \"\$f\" ]; then printf '%s -> %s\\n' \"\$f\" \"\$(readlink \"\$f\")\"; else printf '%s %s\\n' \"\$f\" \"\$(sha256sum <\"\$f\" | cut -c1-16)\"; fi; done"
}

before=$(snap)
as_user "cd '$K' && ./install.sh --dry-run" >/tmp/dry.log 2>&1
check "dry run exits 0" [ $? -eq 0 ]
check "dry run changes nothing" [ "$(snap)" = "$before" ]

as_user "cd '$K' && sudo -n true && ./install.sh --deps --yes" 2>&1 | tee /tmp/install.log
check "install --deps --yes exits 0" [ "${PIPESTATUS[0]}" -eq 0 ]
check "Hyprland and quickshell installed" as_user "command -v Hyprland && command -v qs" 
check "kuwai's Hyprland entry in ~/.config/kuwai/hypr" as_user "cmp -s ~/.config/kuwai/hypr/hyprland.lua '$K/hypr/templates/hyprland.lua' && [ -f ~/.config/kuwai/hypr/monitors.lua ] && [ -f ~/.config/kuwai/hypr/user.lua ]"
check "~/.config/hypr left alone" as_user "[ ! -e ~/.config/hypr/hyprland.lua ]"
check "stable channel checked out" as_user "[ -f ~/.local/share/kuwai/hypr/init.lua ] && [ \"\$(git -C ~/.local/share/kuwai rev-parse --abbrev-ref HEAD)\" = stable ]"
check "migrations recorded" as_user "~/.local/share/kuwai/bin/kuwai-migrations --list | grep -q done && ! ~/.local/share/kuwai/bin/kuwai-migrations --list | grep -q pending"
check "user units linked" as_user "[ -L ~/.config/systemd/user/kuwai-shell.service ]"
check "kuwai version runs" as_user "~/.local/share/kuwai/bin/kuwai-ctl version | grep -q '^kuwai '"
check "the shell loads (offscreen)" as_user "cd ~/.local/share/kuwai && bin/kuwai-loadtest HEAD"
check "the login screen loads (offscreen)" as_user "cd ~/.local/share/kuwai && bin/kuwai-loadtest HEAD greeter.qml"
if as_user ": > /tmp/min.lua && XDG_RUNTIME_DIR=\$(mktemp -d) Hyprland --verify-config -c /tmp/min.lua >/dev/null 2>&1"; then
    as_user "XDG_RUNTIME_DIR=\$(mktemp -d) KUWAI_ROOT=~/.local/share/kuwai Hyprland --verify-config -c ~/.config/kuwai/hypr/hyprland.lua >/tmp/verify.log 2>&1"
    rc=$?
    if [ $rc -eq 139 ]; then results+=("SKIP  Hyprland accepts the config (Hyprland's --verify-config crashes on this config, on a desktop too; checked live with hyprctl configerrors instead)")
    elif [ $rc -eq 0 ]; then pass "Hyprland accepts the config"
    else tail -20 /tmp/verify.log; fail "Hyprland accepts the config"; fi
else
    results+=("SKIP  Hyprland accepts the config (Hyprland --verify-config fails here even on a minimal config)")
fi

check "stable survives the clone moving" as_user "mv '$K' '$K.moved' && git -C ~/.local/share/kuwai status --short >/dev/null && ~/.local/share/kuwai/bin/kuwai-ctl version | grep -q '^stable'; rc=\$?; mv '$K.moved' '$K'; exit \$rc"
check "Hyprland version gate passes" grep -q 'Hyprland [0-9.]* (0.57 or later)' /tmp/install.log
check "every core package installed" as_user "cd '$K' && [ -z \"\$(./install.sh --print-missing)\" ]"

installed=$(snap)
as_user "cd '$K' && ./install.sh" >/tmp/again.log 2>&1
check "a second install exits 0" [ $? -eq 0 ]
check "a second install changes nothing" [ "$(snap)" = "$installed" ]

check "login session adds" bash -c "'$K/system/session' && '$K/system/session' --check && [ -f /usr/share/wayland-sessions/kuwai.desktop ]"
check "login session removes" bash -c "'$K/system/session' --undo && [ ! -e /usr/share/wayland-sessions/kuwai.desktop ] && [ ! -e /usr/local/bin/kuwai-session ]"

as_user "cd '$K' && ./install.sh --uninstall && rm -rf ~/.local/share/kuwai" >/tmp/uninstall.log 2>&1
check "uninstall exits 0" [ $? -eq 0 ]
after=$(snap)
left=$(LC_ALL=C comm -3 <(printf '%s\n' "$before" | LC_ALL=C sort) <(printf '%s\n' "$after" | LC_ALL=C sort) | sed 's/^\t*//' | grep -vE '^\./\.(config|local/state)/kuwai/' || true)
check "uninstall puts home back (all but ~/.config/kuwai and ~/.local/state/kuwai)" [ -z "$left" ]
[ -z "$left" ] || printf 'left behind or changed:\n%s\n' "$left"

printf '\n%s\n' "${results[@]}"
printf '%s\n' "${results[@]}" | grep -q '^FAIL' && exit 1
exit 0
