#!/usr/bin/env bash
# what: kuwai's shell runs as kuwai-shell.service, which systemd restarts

d="$XDG_CONFIG_HOME/systemd/user"
[ -e "$d/kuwai-auth.service" ] || exit 0
n=0
for u in kuwai-shell.service kuwai-shell-broken.service; do
    src="$KUWAI_ROOT/systemd/$u"
    [ -f "$src" ] || exit 0
    [ "$(readlink -f "$d/$u" 2>/dev/null)" = "$(readlink -f "$src")" ] && continue
    [ -e "$d/$u" ] && [ ! -L "$d/$u" ] && continue
    ln -sfn -- "$src" "$d/$u"
    n=$((n + 1))
done
systemctl --user daemon-reload 2>/dev/null || true
[ "$n" = 0 ] || echo "kuwai-shell.service linked; the shell is kept running by systemd from the next restart"
