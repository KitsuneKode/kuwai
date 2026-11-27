#!/usr/bin/env bash
set -euo pipefail

usage() {
cat <<'KUWAI_USAGE'
kuwai: install, check, or remove, without touching anything it can't put back.
kuwai setup runs this from a signed release it has checked; run from a clone it
installs that clone for you, and leaves everything that needs root to root's
checked copy of a release.

  ./install.sh               install (or update the install) for this user
  ./install.sh --dry-run     say what it would do; change nothing
  ./install.sh --deps        also install missing packages (sudo pacman; all in the official repos)
  ./install.sh --yes         pass --noconfirm when installing packages with --deps
  ./install.sh --print-missing  print missing required packages/fonts one per line and exit
  ./install.sh --no-services skip linking and enabling systemd user units
  ./install.sh --clipboard / --no-clipboard   keep clipboard history, or not (asked otherwise)
  ./install.sh --feeds / --no-feeds           GitHub/Gmail notifications, or not (asked otherwise)
  ./install.sh --uninstall   put back what was there before the first install
  ./install.sh --separate-session  an older install that used ~/.config/hypr:
                             move Kuwai to ~/.config/kuwai/hypr and give ~/.config/hypr back
  ./install.sh --doctor      only check (kuwai doctor + kuwai-check)

What it does:
  1. checks the packages the desktop needs (and the optional ones)
  2. remembers, the first time only, how each path it replaces was (absent, a
     file, or a link) and whether each service was enabled: ~/.local/state/kuwai/original/
  3. ~/.config/kuwai/hypr/hyprland.lua ← hypr/templates/hyprland.lua (your
     monitors.lua and user.lua beside it are created empty if missing, never
     overwritten); ~/.config/hypr and the plain Hyprland session are not touched
  4. the stable channel: a checkout of the `stable` branch in ~/.local/share/kuwai
     (your session runs from it; `kuwai promote` moves it forward)
  5. user services (password prompt, a daily snapshot of your own files: kuwai
     backup), linked from the stable checkout and enabled; clipboard history and
     GitHub/Gmail feeds only if you say yes (asked once, kept in
     ~/.config/kuwai/collect.conf; kuwai collect changes it)
  6. a "Kuwai" entry on the login screen, beside your other sessions, and a
     root-owned copy of the password prompt, both from root's checked copy of
     a signed release in /usr/local/lib/kuwai (sudo, once; without a terminal,
     or without that copy, it says the commands instead)
  7. the checks
Never: autologin, or your settings. The login screen and alarms that wake the
laptop are separate, with sudo, from root's copy too:
/usr/local/lib/kuwai/current/greeter/install, …/system/install.
KUWAI_USAGE
}

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CFG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/kuwai
STABLE=$DATA/kuwai
LIB=${KUWAI_SYSROOT:-}/usr/local/lib/kuwai
UNITS=(kuwai-auth.service kuwai-shell.service kuwai-shell-broken.service kuwai-wallpaper.service kuwai-clipboard.service kuwai-feeds.service kuwai-backup.service kuwai-backup.timer kuwai-hotwatch.service kuwai-hotwatch.timer)

FROM_RELEASE=0; DRY=0; DEPS=0; YES=0; PRINT_MISSING=0; NO_SERVICES=0; MODE=install; SEPARATE=0; WANT_CLIP=""; WANT_FEEDS=""
for a in "$@"; do
    case $a in
        --dry-run) DRY=1 ;;
        --deps) DEPS=1 ;;
        --yes|-y) YES=1 ;;
        --print-missing) PRINT_MISSING=1 ;;
        --no-services) NO_SERVICES=1 ;;
        --clipboard) WANT_CLIP=on ;;
        --no-clipboard) WANT_CLIP=off ;;
        --feeds) WANT_FEEDS=on ;;
        --no-feeds) WANT_FEEDS=off ;;
        --uninstall) MODE=uninstall ;;
        --separate-session) SEPARATE=1 ;;
        --doctor) MODE=doctor ;;
        --from-release) FROM_RELEASE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }

COLLECT=$CFG/kuwai/collect.conf
collect_state() { [ -f "$COLLECT" ] || return 0; sed -n "s/^$1=//p" "$COLLECT" | tail -1; }
consent() {
    local name=$1 flag=$2 question=$3 answer
    answer=${flag:-$(collect_state "$name")}
    if [ -z "$answer" ]; then
        answer=off
        if [ $DRY = 0 ] && [ -t 0 ]; then
            printf '  %s [y/N] ' "$question"
            read -r reply || reply=""
            case $reply in [yY]*) answer=on ;; esac
        else
            warn "$name: off (asked only on a terminal; --$name turns it on, or later: kuwai collect $name on)"
        fi
    fi
    [ $DRY = 1 ] && { say "  would: $name=$answer in $COLLECT"; return 0; }
    mkdir -p "$(dirname "$COLLECT")"
    { grep -v "^$name=" "$COLLECT" 2>/dev/null || true; echo "$name=$answer"; } >"$COLLECT.new" && mv -- "$COLLECT.new" "$COLLECT"
}
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  • %s\n' "$*"; }
do_()  { if [ $DRY = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }
userbus() { systemctl --user show-environment >/dev/null 2>&1; }

read_pkg_file() {
    [ -f "$1" ] || return 1
    awk 'NF && $1 !~ /^#/' "$1"
}

NEED_LIST=$(read_pkg_file "$REPO/packages/core.txt" || printf '%s\n' \
    Hyprland:hyprland qs:quickshell cliphist:cliphist wl-copy:wl-clipboard jq:jq grim:grim slurp:slurp \
    brightnessctl:brightnessctl pw-play:pipewire-audio wpctl:wireplumber notify-send:libnotify curl:curl \
    setpriv:util-linux gdbus:glib2 python3:python luac:lua playerctl:playerctl git:git file:file node:nodejs :qt6-multimedia)
OPTIONAL_LIST=$(read_pkg_file "$REPO/packages/optional.txt" || printf '%s\n' \
    'satty:satty(screenshot-editing)' 'tesseract:tesseract(copy-text-from-images)' 'mpv:mpv(live-wallpapers)' \
    'mpvpaper:mpvpaper(live-wallpapers-outside-the-shell)' 'socat:socat(live-wallpapers-outside-the-shell)' \
    'magick:imagemagick(thumbnails)' 'pdftoppm:poppler(PDF-previews)' 'kitty:kitty(terminal)' \
    'secret-tool:libsecret(Gmail-password-in-keyring)' 'gh:github-cli(GitHub-notifications)' \
    'wtype:wtype(typing-emoji-into-windows)' 'ydotool:ydotool(tests)' 'ddcutil:ddcutil(external-monitor-brightness)')
FONTS_LIST=$(read_pkg_file "$REPO/packages/fonts.txt" || printf '%s\n' \
    'Inter:inter-font' 'Symbols Nerd Font:ttf-nerd-fonts-symbols')

has_pkg() {
    local b=$1 p=$2
    if [ -n "$b" ]; then
        command -v "$b" >/dev/null
    elif command -v pacman >/dev/null; then
        pacman -Q "$p" >/dev/null 2>&1
    else
        return 0
    fi
}

check_deps() {
    [ $PRINT_MISSING = 1 ] || step "Packages"
    local missing=() fonts=()
    while IFS= read -r pair; do
        [ -n "$pair" ] || continue
        b=${pair%%:*}; p=${pair#*:}
        if has_pkg "$b" "$p"; then [ $PRINT_MISSING = 1 ] || ok "${b:-$p}"; else [ $PRINT_MISSING = 1 ] || warn "missing: ${b:-$p} (package $p)"; missing+=("$p"); fi
    done <<<"$NEED_LIST"
    if [ $PRINT_MISSING = 0 ]; then
        while IFS= read -r pair; do
            [ -n "$pair" ] || continue
            b=${pair%%:*}; rest=${pair#*:}; p=${rest%%(*}; why=${rest#*(}; why=${why%)}
            has_pkg "$b" "$p" || warn "optional, not installed: $p — for ${why//-/ }"
        done <<<"$OPTIONAL_LIST"
    fi
    local have; have=$(fc-list : family 2>/dev/null | tr ',' '\n' || true)
    local sf=0; grep -qx -- "SF Pro Text" <<<"$have" && grep -qx -- "SF Pro Display" <<<"$have" && sf=1
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        name=${f%%:*}; p=${f#*:}
        if grep -qx -- "$name\( Variable\)\?" <<<"$have"; then [ $PRINT_MISSING = 1 ] || ok "font: $name"
        elif [ "$name" = Inter ] && [ $sf = 1 ]; then :
        else [ $PRINT_MISSING = 1 ] || warn "missing font: $name (package $p; the shell falls back to sans-serif)"; fonts+=("$p"); fi
    done <<<"$FONTS_LIST"
    if [ $PRINT_MISSING = 1 ]; then
        for p in "${missing[@]}" "${fonts[@]}"; do printf '%s\n' "$p"; done
        return 0
    fi
    [ $sf = 1 ] && ok "font: SF Pro (found: the shell uses it instead of Inter)" \
        || say "  (SF Pro is used instead of Inter if you install it yourself; Apple's licence limits it to Apple platforms)"
    if [ ${#missing[@]} -gt 0 ] || [ ${#fonts[@]} -gt 0 ]; then
        if [ $DEPS = 1 ] && [ $DRY = 0 ]; then
            local pflags=(--needed)
            [ $YES = 1 ] && pflags+=(--noconfirm)
            sudo pacman -S "${pflags[@]}" "${missing[@]}" "${fonts[@]}"
        else
            say "  install: sudo pacman -S --needed ${missing[*]} ${fonts[*]}"
            say "  (or rerun with --deps)"
            [ ${#missing[@]} -gt 0 ] && [ $DRY = 0 ] && { say "  (the needed ones first; stopping here)"; exit 1; }
        fi
    fi
    hypr_version || exit 1
    hyde_report
    return 0
}

hypr_version() {
    command -v Hyprland >/dev/null || return 0
    local v; v=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    [ -n "$v" ] || { warn "couldn't read Hyprland's version; Kuwai needs 0.57 or later (Lua config)"; return 0; }
    if [ "$(printf '%s\n0.57\n' "$v" | sort -V | head -1)" != 0.57 ]; then
        warn "Hyprland $v is too old: Kuwai's config is Lua, which needs Hyprland 0.57 or later (sudo pacman -Syu)"
        [ $DRY = 1 ] && return 0
        return 1
    fi
    [ $PRINT_MISSING = 1 ] || ok "Hyprland $v (0.57 or later)"
}

# shellcheck source=lib/hyde.sh
. "$REPO/lib/hyde.sh" 2>/dev/null || hyde_here() { return 1; }
hyde_report() {
    step "HyDE (optional)"
    if hyde_here; then
        ok "HyDE is installed: kuwai uses its wallpaper, themes and theme colours, Waybar and a few pickers"
        return 0
    fi
    say "  HyDE isn't installed. kuwai works without it; these features need it, and without it:"
    say "    • the desktop wallpaper: set one with kuwai-wall set IMAGE (kept for the next login)"
    say "    • the Themes panel's themes, wallpapers and Colours: it says HyDE isn't there"
    say "    • the island's theme colour: kuwai's own blue"
    say "    • Waybar: plain waybar if it's installed, else the island is the bar"
    say "    • Game mode: kuwai's gaming mode (Super+Alt+G) instead of HyDE's"
    say "    • HyDE's pickers (Super+Shift+E, A, R, U, G) and 'update in a terminal': not bound / says so"
    say "  Live wallpapers, screensavers, the island, notifications, the lock and login screens don't need it."
}

ORIG() { python3 "$REPO/bin/kuwai_install.py" --state "$STATE" "$@"; }
remember()  { [ $DRY = 1 ] || ORIG remember "$1"; }
installed() { [ $DRY = 1 ] || ORIG installed "$1"; }

stage() {
    local link=$1 src=$2 dst=$3 tmp
    mkdir -p "$(dirname "$dst")" || return 1
    if [ "$link" = 1 ]; then
        tmp=$(mktemp -u "$(dirname "$dst")/.$(basename "$dst").XXXXXX") || return 1
        ln -s "$src" "$tmp" || return 1
    else
        tmp=$(mktemp "$(dirname "$dst")/.$(basename "$dst").XXXXXX") || return 1
        cp -- "$src" "$tmp" && chmod --reference="$src" "$tmp" || { rm -f -- "$tmp"; return 1; }
    fi
    if [ "${4:-}" = new ]; then mv -nT -- "$tmp" "$dst"; rm -f -- "$tmp"
    else mv -fT -- "$tmp" "$dst" || { rm -f -- "$tmp"; return 1; }; fi
}

stop_install() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

create() {
    local dst=$1 tmp
    tmp=$(mktemp "$(dirname "$dst")/.$(basename "$dst").XXXXXX")
    printf '%s\n' "$2" >"$tmp"
    chmod 0644 "$tmp"
    mv -nT -- "$tmp" "$dst"
    rm -f -- "$tmp"
}

place() {
    local link=0; [ "$1" = -s ] && { link=1; shift; }
    local src=$1 dst=$2
    if [ $DRY = 1 ]; then printf '  would: %s %s → %s\n' "$([ $link = 1 ] && echo link || echo copy)" "$src" "$dst"; return; fi
    remember "$dst" || stop_install "couldn't back up $dst first, so it wasn't replaced; nothing after it was installed"
    if ORIG edited "$dst"; then
        stage "$link" "$src" "$dst.kuwai-new" || stop_install "couldn't write $dst.kuwai-new"
        warn "you changed $dst since kuwai installed it: kept yours; the new one is $dst.kuwai-new"
        return 1
    fi
    stage "$link" "$src" "$dst" || stop_install "couldn't write $dst (your original is backed up)"
    installed "$dst" || stop_install "couldn't record $dst as kuwai's (your original is backed up)"
}

KDIR=$CFG/kuwai/hypr

kuwai_dir() {
    local old=$CFG/hypr/hyprland.lua
    if [ ! -f "$KDIR/hyprland.lua" ] && { ORIG manages "$old" 2>/dev/null || grep -qs KUWAI_ROOT "$old"; }; then
        printf '%s\n' "$CFG/hypr"
    else
        printf '%s\n' "$KDIR"
    fi
}

separate_session() {
    if [ $DRY = 1 ]; then say "  would: copy monitors.lua, user.lua, features.lua to $KDIR and put back $CFG/hypr/hyprland.lua"; return; fi
    mkdir -p "$KDIR"
    for f in monitors.lua user.lua features.lua; do
        [ -f "$CFG/hypr/$f" ] && [ ! -e "$KDIR/$f" ] || continue
        remember "$KDIR/$f"; stage 0 "$CFG/hypr/$f" "$KDIR/$f" new; installed "$KDIR/$f"
        ok "$f copied to $KDIR (the one in $CFG/hypr stays)"
    done
    place "$REPO/hypr/templates/hyprland.lua" "$KDIR/hyprland.lua" && ok "$KDIR/hyprland.lua ← hypr/templates/hyprland.lua"
    if ORIG manages "$CFG/hypr/hyprland.lua"; then ORIG restore-one "$CFG/hypr/hyprland.lua" || true
    else warn "$CFG/hypr/hyprland.lua was Kuwai's before kuwai kept records; it's left as it is (replace it with your own to make the plain Hyprland session yours again)"; fi
}

login_session() {
    step "Login session"
    local s=$REPO/system/session r=$LIB/current/system/session
    if [ ! -x "$s" ]; then ok "nothing to add in this copy"
    elif "$s" --check >/dev/null 2>&1; then ok "\"Kuwai\" is on the login screen"
    elif [ ! -x "$r" ]; then
        warn "the login entry comes from root's checked copy of a signed release, which isn't installed: kuwai setup puts it in place"
        say "    (developing kuwai, trusting this clone as it is: sudo $s --trust-clone)"
    elif [ $DRY = 1 ]; then say "  would: sudo $r (adds \"Kuwai\" to the login screen)"
    elif [ -t 0 ] && [ -t 1 ] && command -v sudo >/dev/null; then
        say "  adding \"Kuwai\" to the login screen from root's checked copy (sudo, once; nothing else of the system changes)"
        sudo "$r" | sed 's/^/  /' || warn "not added; run: sudo $r"
    else
        warn "add \"Kuwai\" to the login screen with: sudo $r"
    fi
}

pin_prompt() {
    step "Password prompt"
    if [ -f /usr/local/share/kuwai/shell-auth/shell.qml ]; then ok "runs from root's copy (/usr/local/share/kuwai/shell-auth)"
    elif [ ! -d "$LIB/current/shell-auth" ]; then warn "the password prompt is pinned from root's checked copy of a signed release, which isn't installed: kuwai setup puts it in place"
    elif [ $DRY = 1 ]; then say "  would: kuwai auth pin (a root-owned copy of the password prompt; sudo, once)"
    elif [ -t 0 ] && [ -t 1 ] && command -v sudo >/dev/null; then
        say "  pinning the password prompt: a root-owned copy, so the code that reads your password isn't code your account can change"
        "$STABLE/bin/kuwai" auth pin | sed 's/^/  /' || warn "not pinned; run: kuwai auth pin"
    else
        warn "pin the password prompt with: kuwai auth pin (until then it runs from your own copy of kuwai)"
    fi
}

default_wallpaper() {
    local name="" url="" sum="" sumtool dest tmp list=$REPO/themes/kuwai-night/wallpapers.tsv
    [ -f "$list" ] && { IFS=$'\t' read -r name url sum _ < <(grep -v '^#' "$list" | head -1) || true; }
    case $name in ''|*[!A-Za-z0-9._-]*) warn "no default wallpaper listed"; return 0 ;; esac
    case ${sum:-} in
        sha1:*) sumtool=sha1sum; sum=${sum#sha1:}; printf '%s' "$sum" | grep -Eq '^[0-9a-f]{40}$' || { warn "the default wallpaper checksum is malformed; not used"; return 0; } ;;
        sha256:*) sumtool=sha256sum; sum=${sum#sha256:}; printf '%s' "$sum" | grep -Eq '^[0-9a-f]{64}$' || { warn "the default wallpaper checksum is malformed; not used"; return 0; } ;;
        *) warn "the default wallpaper has no checksum pin; not used"; return 0 ;;
    esac
    dest=$STATE/wallpapers/$name.jpg
    mkdir -p "$STATE/wallpapers"
    tmp=$(mktemp)
    if ! curl -fsSL --proto =https --proto-redir =https --max-time 120 --max-filesize 40M -A "kuwai-install/1 (+https://github.com/KitsuneKode/kuwai)" -o "$tmp" "$url"; then
        rm -f "$tmp"; warn "couldn't download a wallpaper (offline?): set one later with kuwai-wall set IMAGE"; return 0
    fi
    if ! printf '%s  %s\n' "$sum" "$tmp" | "$sumtool" -c --status; then
        rm -f "$tmp"; warn "the wallpaper isn't the file Kuwai Night lists; not used"; return 0
    fi
    if ! file -b --mime-type "$tmp" | grep -Eq '^image/(jpeg|png|webp)$'; then
        rm -f "$tmp"; warn "the wallpaper download isn't an image; not used"; return 0
    fi
    mv "$tmp" "$dest"
    cp "$REPO/themes/kuwai-night/CREDITS.txt" "$STATE/wallpapers/CREDITS.txt"
    ln -sfn "$dest" "$STATE/wallpaper"
    "$STABLE/bin/kuwai-look" theme kuwai-night --no-apply >/dev/null 2>&1 || "$STABLE/bin/kuwai-look" set-wallpaper --no-apply "$dest" >/dev/null 2>&1 || true
    ok "Kuwai Night's wallpaper ($name), set at your first login; credits beside it"
}

install_all() {
    check_deps

    step "Stable channel ($STABLE)"
    if git -C "$REPO" show-ref --verify --quiet refs/heads/stable; then ok "branch stable exists"
    else do_ git -C "$REPO" branch stable HEAD; ok "branch stable made at $(git -C "$REPO" rev-parse --short HEAD)"; fi
    if [ -e "$STABLE/hypr/init.lua" ]; then ok "checkout exists ($(git -C "$STABLE" rev-parse --short HEAD 2>/dev/null))"
    else
        do_ git clone -q --branch stable "$REPO" "$STABLE"
        if [ $DRY = 0 ]; then
            up=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
            if [ -n "$up" ]; then git -C "$STABLE" remote set-url origin "$up"; fi
            ok "checkout cloned (its own copy: moving or deleting $REPO doesn't break it)"
        fi
    fi
    do_ mkdir -p "$STATE"
    [ $DRY = 1 ] || [ $FROM_RELEASE = 1 ] || printf '%s\n' "$REPO" >"$STATE/dev-root"
    [ -f "$STATE/channel" ] || { [ $DRY = 1 ] && say "  would: write stable to $STATE/channel" || echo stable >"$STATE/channel"; }
    ok "channel: $(cat "$STATE/channel" 2>/dev/null || echo stable)"

    step "Migrations"
    local mig=$STABLE/bin/kuwai-migrations
    [ -x "$mig" ] || mig=$REPO/bin/kuwai-migrations
    if [ ! -x "$mig" ]; then warn "no migrations runner in this copy; nothing to migrate"
    elif [ $DRY = 1 ]; then "$mig" --dry-run | sed 's/^/  /' || warn "the migrations can't run here (above)"
    elif out=$("$mig" 2>&1); then printf '%s\n' "$out" | sed 's/^/  /'; ok "settings and state are current"
    else
        printf '%s\n' "$out" | sed 's/^/  /'
        say "  Stopped here: the services below would start code your state isn't ready for."
        say "  Fix what it says, then run ./install.sh again (what ran is kept; it continues from there)."
        exit 1
    fi

    step "Configs kuwai owns (home/)"
    if [ ! -x "$REPO/bin/kuwai-home" ]; then ok "nothing to link in this copy"
    elif [ $DRY = 1 ]; then "$REPO/bin/kuwai-home" --dry-run | sed 's/^/  /'
    else KUWAI_HOME_SRC="$STABLE/home" "$REPO/bin/kuwai-home" | sed 's/^/  /'; fi

    step "Kuwai's Hyprland config"
    local dir; dir=$(kuwai_dir)
    if [ $SEPARATE = 1 ] && [ "$dir" = "$CFG/hypr" ]; then separate_session; dir=$KDIR; fi
    [ "$dir" = "$KDIR" ] || warn "an older install: Kuwai reads $dir, so the plain Hyprland session starts Kuwai too (./install.sh --separate-session moves it to $KDIR)"
    local entry=$dir/hyprland.lua
    if [ -f "$entry" ] && cmp -s "$entry" "$REPO/hypr/templates/hyprland.lua"; then ok "$entry is current"
    else
        if place "$REPO/hypr/templates/hyprland.lua" "$entry"; then ok "$entry ← hypr/templates/hyprland.lua"; fi
    fi
    for f in monitors.lua user.lua; do
        if [ -e "$dir/$f" ]; then ok "$f: yours, kept"
        elif [ $DRY = 1 ]; then say "  would: create an empty $dir/$f"
        else
            remember "$dir/$f"; mkdir -p "$dir"
            create "$dir/$f" "-- $f: yours (kuwai never overwrites it)"
            installed "$dir/$f"
        fi
    done
    [ "$dir" = "$CFG/hypr" ] || [ ! -f "$CFG/hypr/hyprland.lua" ] || ok "$CFG/hypr/hyprland.lua: not Kuwai's, left as it is"

    step "The kuwai command"
    local kbin=$HOME/.local/bin/kuwai
    if [ "$(readlink -f "$kbin" 2>/dev/null)" = "$(readlink -f "$STABLE/bin/kuwai")" ]; then ok "kuwai on your PATH"
    elif [ -e "$kbin" ] && ! { [ -L "$kbin" ] && [ -f "$(dirname "$(readlink -f "$kbin")")/kuwai-ctl" ]; }; then ok "$kbin is your own: left as it is"
    elif place -s "$STABLE/bin/kuwai" "$kbin"; then ok "kuwai → $STABLE/bin/kuwai"; fi
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin isn't on your PATH: add it to run kuwai by name" ;; esac

    step "Wallpaper"
    if hyde_here; then ok "HyDE's (its themes and wallpapers)"
    elif [ -e "$STATE/wallpaper" ]; then ok "yours, kept"
    elif [ $DRY = 1 ]; then say "  would: download Kuwai Night's first wallpaper into $STATE/wallpapers and use it"
    else default_wallpaper; fi

    step "User services"
    if [ $NO_SERVICES = 1 ]; then
        ok "skipped (--no-services)"
    else
        do_ mkdir -p "$CFG/systemd/user"
        [ $DRY = 1 ] || for u in "${UNITS[@]}"; do ORIG unit "$u"; done
        for u in "${UNITS[@]}"; do
            local dst=$CFG/systemd/user/$u src=$STABLE/systemd/$u
            [ -f "$src" ] || src=$REPO/systemd/$u
            if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then ok "$u linked"
            elif place -s "$src" "$dst"; then ok "$u → $src"; fi
        done
        consent clipboard "$WANT_CLIP" "Keep clipboard history? Text and images you copy are kept by cliphist in your home folder until you clear them."
        consent feeds "$WANT_FEEDS" "Show GitHub and Gmail notifications? Uses your gh login to read your GitHub notifications (private repositories too); Gmail only after kuwai feeds gmail-setup."
        local enable=() off=()
        for u in "${UNITS[@]}"; do
            local src=$STABLE/systemd/$u; [ -f "$src" ] || src=$REPO/systemd/$u
            case $u in
                kuwai-clipboard.service) [ "$(collect_state clipboard)" = on ] || { off+=("$u"); continue; } ;;
                kuwai-feeds.service) [ "$(collect_state feeds)" = on ] || { off+=("$u"); continue; } ;;
            esac
            grep -qs '^\[Install\]' "$src" && enable+=("$u")
        done
        if [ $DRY = 0 ] && ! userbus; then
            warn "no user session to enable them in (a text console or SSH); once you're logged in run:"
            say "    systemctl --user daemon-reload && systemctl --user enable ${enable[*]}"
        else
            do_ systemctl --user daemon-reload
            for u in "${enable[@]}"; do
                do_ systemctl --user enable "$u" >/dev/null 2>&1 || warn "couldn't enable $u"
            done
            for u in "${off[@]}"; do
                systemctl --user -q is-enabled "$u" 2>/dev/null && { do_ systemctl --user disable --now "$u" >/dev/null 2>&1 || true; }
                ok "$u left off (your choice: kuwai collect)"
            done
        fi
    fi

    login_session
    pin_prompt

    [ $DRY = 1 ] || { step "Original state"; ok "kept in $STATE/original (./install.sh --uninstall puts it back)"; }

    step "Optional, with sudo"
    say "  sudo $LIB/current/greeter/install    the login screen (greetd; --undo puts the old login back)"
    say "  sudo $LIB/current/system/install     alarms that wake the laptop from sleep"
    say "  kuwai feeds gmail-setup        Gmail notifications (the app password goes to your keyring)"

    [ $DRY = 1 ] || doctor
    say ""
    say "Done. Log out and pick Kuwai on the login screen (from a console: kuwai-session)."
}

uninstall_all() {
    step "Uninstall"
    if ! command -v python3 >/dev/null; then
        if [ -d "$STATE/original" ]; then
            say "  Uninstall reads what to put back with python3 (package python), which isn't installed; install it, then run this again."
            exit 1
        fi
        say "  Nothing to put back: kuwai was never installed for this user (nothing is kept in $STATE/original)."
        return 0
    fi
    local rc=0
    if [ $DRY = 1 ]; then ORIG restore --dry-run; else ORIG restore || rc=$?; fi
    say "  The stable checkout ($STABLE), your settings (~/.config/kuwai) and notes stay."
    if [ -f "$STABLE/.git" ]; then say "  Remove the checkout too:  git -C $REPO worktree remove $STABLE"
    else say "  Remove the checkout too:  rm -rf $STABLE"; fi
    say "  The Kuwai login entry: sudo $LIB/current/system/session --undo"
    say "  The pinned password prompt: kuwai auth unpin"
    say "  The login screen / alarms: sudo $LIB/current/greeter/install --undo · sudo $LIB/current/system/install --undo"
    say "  Root's copy of kuwai, after those: sudo rm -rf $LIB"
    return $rc
}

doctor() {
    step "Checks"
    local rc=0
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        ok "installed; no graphical session here, so the session checks wait for your first login: kuwai doctor"
        return 0
    fi
    if [ -x "$STABLE/bin/kuwai" ] || [ -x "$REPO/bin/kuwai" ]; then
        KUWAI_ROOT=$STABLE "${STABLE}/bin/kuwai" doctor 2>/dev/null || KUWAI_ROOT=$REPO "$REPO/bin/kuwai" doctor || rc=1
    fi
    if [ -x "$REPO/bin/kuwai-doctor" ]; then
        KUWAI_ROOT=$REPO "$REPO/bin/kuwai-doctor" --quiet || rc=1
        [ $rc -eq 0 ] || "$REPO/bin/kuwai-doctor" || true
    elif pgrep -f '^qs -p .*/shell -d$' >/dev/null; then
        "$REPO/bin/kuwai-check" || rc=1
    else
        warn "the shell isn't running (it starts with Hyprland); kuwai-check skipped"
    fi
    return $rc
}

if [ $PRINT_MISSING = 1 ]; then
    check_deps
    exit 0
fi

case $MODE in
    install) install_all ;;
    uninstall) uninstall_all ;;
    doctor) check_deps; doctor ;;
esac
