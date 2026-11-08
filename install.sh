#!/usr/bin/env bash
# kuwai + rice: install, check, or remove, without touching anything it can't
# put back. Run from the repo (wherever you cloned it).
#
#   ./install.sh               install (or update the install) for this user
#   ./install.sh --dry-run     say what it would do; change nothing
#   ./install.sh --deps        also install missing packages (sudo pacman / an AUR helper)
#   ./install.sh --uninstall   put back what was there before the first install
#   ./install.sh --doctor      only check (kuwai doctor + rice-check)
#
# What it does:
#   1. checks the packages the desktop needs (and the optional ones)
#   2. remembers, the first time only, how each path it replaces was (absent, a
#      file, or a link) and whether each service was enabled: ~/.local/state/kuwai/original/
#   3. ~/.config/hypr/hyprland.lua ← hypr/templates/hyprland.lua (your monitors.lua
#      and user.lua beside it are created empty if missing, never overwritten)
#   4. the stable channel: a checkout of the `stable` branch in ~/.local/share/kuwai
#      (your session runs from it; `rice promote` moves it forward)
#   5. user services (password prompt, clipboard history, GitHub/Gmail feeds),
#      linked from the stable checkout and enabled
#   6. the checks
# Never: root, autologin, or your settings. The login screen and alarms that
# wake the laptop are separate, with sudo: greeter/install, system/install.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CFG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/kuwai
STABLE=$DATA/kuwai
UNITS=(rice-auth.service rice-clipboard.service rice-feeds.service)

DRY=0; DEPS=0; MODE=install
for a in "$@"; do
    case $a in
        --dry-run) DRY=1 ;;
        --deps) DEPS=1 ;;
        --uninstall) MODE=uninstall ;;
        --doctor) MODE=doctor ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  • %s\n' "$*"; }
do_()  { if [ $DRY = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

# ── Packages ─────────────────────────────────────────────────────────────
# binary:package. Needed = the desktop doesn't work without; optional = one feature.
NEED="Hyprland:hyprland qs:quickshell cliphist:cliphist wl-copy:wl-clipboard jq:jq grim:grim slurp:slurp
brightnessctl:brightnessctl pw-play:pipewire-audio wpctl:wireplumber notify-send:libnotify curl:curl
setpriv:util-linux gdbus:glib2 python3:python luac:lua playerctl:playerctl git:git"
OPTIONAL="satty:satty(screenshot-editing) tesseract:tesseract(copy-text-from-images) mpv:mpv(live-wallpapers)
magick:imagemagick(thumbnails) pdftoppm:poppler(PDF-previews) kitty:kitty(terminal) secret-tool:libsecret(Gmail-password-in-keyring)
gh:github-cli(GitHub-notifications) wtype:wtype(typing-emoji-into-windows) ydotool:ydotool(tests) ddcutil:ddcutil(external-monitor-brightness)"
FONTS="SF Pro Text:apple-fonts|Symbols Nerd Font:ttf-nerd-fonts-symbols-mono"

check_deps() {
    step "Packages"
    local missing=() aur=()
    for pair in $NEED; do
        b=${pair%%:*}; p=${pair#*:}
        if command -v "$b" >/dev/null; then ok "$b"; else warn "missing: $b (package $p)"; missing+=("$p"); fi
    done
    for pair in $OPTIONAL; do
        b=${pair%%:*}; rest=${pair#*:}; p=${rest%%(*}; why=${rest#*(}; why=${why%)}
        command -v "$b" >/dev/null || warn "optional, not installed: $p — for ${why//-/ }"
    done
    local have; have=$(fc-list : family 2>/dev/null || true)
    IFS='|' read -ra fl <<<"$FONTS"
    for f in "${fl[@]}"; do
        name=${f%%:*}; p=${f#*:}
        if grep -qi -- "$name" <<<"$have"; then ok "font: $name"; else warn "missing font: $name (package $p, AUR)"; aur+=("$p"); fi
    done
    if [ ${#missing[@]} -gt 0 ] || [ ${#aur[@]} -gt 0 ]; then
        if [ $DEPS = 1 ] && [ $DRY = 0 ]; then
            [ ${#missing[@]} -gt 0 ] && sudo pacman -S --needed "${missing[@]}"
            if [ ${#aur[@]} -gt 0 ]; then
                h=$(command -v paru || command -v yay || true)
                if [ -n "$h" ]; then "$h" -S --needed "${aur[@]}"; else warn "no AUR helper (paru/yay) for: ${aur[*]}"; fi
            fi
        else
            [ ${#missing[@]} -gt 0 ] && say "  install: sudo pacman -S --needed ${missing[*]}"
            [ ${#aur[@]} -gt 0 ] && say "  from the AUR: paru -S ${aur[*]}"
            say "  (or rerun with --deps)"
            [ ${#missing[@]} -gt 0 ] && [ $DRY = 0 ] && { say "  (the needed ones first; stopping here)"; exit 1; }
        fi
    fi
    return 0
}

# ── The original state ───────────────────────────────────────────────────
# bin/rice_install.py keeps it: how each path was before the first install
# (later installs don't overwrite that), and what kuwai put there, so
# uninstall can tell your later edits from its own files.
ORIG() { python3 "$REPO/bin/rice_install.py" --state "$STATE" "$@"; }
remember()  { [ $DRY = 1 ] || ORIG remember "$1"; }
installed() { [ $DRY = 1 ] || ORIG installed "$1"; }

# Replace $2 with a copy of $1 (or, with -s, a link to $1) in one rename:
# if $2 is a link, the link is replaced, never the file it points at.
place() {
    local link=0; [ "$1" = -s ] && { link=1; shift; }
    local src=$1 dst=$2 tmp
    if [ $DRY = 1 ]; then printf '  would: %s %s → %s\n' "$([ $link = 1 ] && echo link || echo copy)" "$src" "$dst"; return; fi
    remember "$dst"
    mkdir -p "$(dirname "$dst")"
    tmp=$(dirname "$dst")/.$(basename "$dst").kuwai-new
    rm -f "$tmp"
    if [ $link = 1 ]; then ln -s "$src" "$tmp"; else cp "$src" "$tmp"; fi
    mv -fT "$tmp" "$dst"
    installed "$dst"
}

install_all() {
    check_deps

    step "Stable channel ($STABLE)"
    if git -C "$REPO" show-ref --verify --quiet refs/heads/stable; then ok "branch stable exists"
    else do_ git -C "$REPO" branch stable HEAD; ok "branch stable made at $(git -C "$REPO" rev-parse --short HEAD)"; fi
    if [ -e "$STABLE/hypr/init.lua" ]; then ok "checkout exists ($(git -C "$STABLE" rev-parse --short HEAD 2>/dev/null))"
    else do_ git -C "$REPO" worktree add "$STABLE" stable; fi
    do_ mkdir -p "$STATE"
    [ -f "$STATE/channel" ] || { [ $DRY = 1 ] && say "  would: write stable to $STATE/channel" || echo stable >"$STATE/channel"; }
    ok "channel: $(cat "$STATE/channel" 2>/dev/null || echo stable)"

    step "Hyprland entry point"
    local entry=$CFG/hypr/hyprland.lua
    if [ -f "$entry" ] && cmp -s "$entry" "$REPO/hypr/templates/hyprland.lua"; then ok "$entry is current"
    else
        place "$REPO/hypr/templates/hyprland.lua" "$entry"
        ok "$entry ← hypr/templates/hyprland.lua"
    fi
    for f in monitors.lua user.lua; do
        if [ -e "$CFG/hypr/$f" ]; then ok "$f: yours, kept"
        elif [ $DRY = 1 ]; then say "  would: create an empty $CFG/hypr/$f"
        else mkdir -p "$CFG/hypr"; printf -- '-- %s: yours (kuwai never overwrites it)\n' "$f" >"$CFG/hypr/$f"; fi
    done

    step "User services"
    do_ mkdir -p "$CFG/systemd/user"
    for u in "${UNITS[@]}"; do
        local dst=$CFG/systemd/user/$u src=$STABLE/systemd/$u
        [ -f "$src" ] || src=$REPO/systemd/$u
        if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then ok "$u linked"
        else place -s "$src" "$dst"; ok "$u → $src"; fi
    done
    do_ systemctl --user daemon-reload
    for u in "${UNITS[@]}"; do
        [ $DRY = 1 ] || ORIG unit "$u"
        do_ systemctl --user enable "$u" >/dev/null 2>&1 || warn "couldn't enable $u"
    done

    [ $DRY = 1 ] || { step "Original state"; ok "kept in $STATE/original (./install.sh --uninstall puts it back)"; }

    step "Optional, with sudo"
    say "  sudo $REPO/greeter/install    the login screen (greetd; --undo for SDDM)"
    say "  sudo $REPO/system/install     alarms that wake the laptop from sleep"
    say "  rice feeds gmail-setup        Gmail notifications (the app password goes to your keyring)"

    [ $DRY = 1 ] || doctor
    say ""
    say "Done. Log out and pick Hyprland, or: hyprctl reload && rice restart"
}

uninstall_all() {
    step "Uninstall"
    for u in "${UNITS[@]}"; do do_ systemctl --user disable --now "$u" >/dev/null 2>&1 || true; done
    if [ $DRY = 1 ]; then ORIG restore --dry-run; else ORIG restore; fi
    do_ systemctl --user daemon-reload
    say "  The stable checkout ($STABLE), your settings (~/.config/rice) and notes stay."
    say "  Remove the checkout too:  git -C $REPO worktree remove $STABLE"
    say "  The login screen / alarms: sudo greeter/install --undo · sudo system/install --undo"
}

doctor() {
    step "Checks"
    local rc=0
    if [ -x "$STABLE/bin/kuwai" ] || [ -x "$REPO/bin/kuwai" ]; then
        KUWAI_ROOT=$STABLE "${STABLE}/bin/kuwai" doctor 2>/dev/null || KUWAI_ROOT=$REPO "$REPO/bin/kuwai" doctor || rc=1
    fi
    if [ -x "$REPO/bin/rice-doctor" ]; then
        KUWAI_ROOT=$REPO "$REPO/bin/rice-doctor" --quiet || rc=1
        [ $rc -eq 0 ] || "$REPO/bin/rice-doctor" || true
    elif pgrep -f '^qs -p .*/shell -d$' >/dev/null; then
        "$REPO/bin/rice-check" || rc=1
    else
        warn "the shell isn't running (it starts with Hyprland); rice-check skipped"
    fi
    return $rc
}

case $MODE in
    install) install_all ;;
    uninstall) uninstall_all ;;
    doctor) check_deps; doctor ;;
esac
