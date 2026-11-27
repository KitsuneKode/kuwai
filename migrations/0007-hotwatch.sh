#!/usr/bin/env bash
# what: kuwai notices when its shell stays busy and saves what it was doing (kuwai-hotwatch.timer, once a minute)
# touches: $XDG_CONFIG_HOME/systemd/user/kuwai-hotwatch.service
# touches: $XDG_CONFIG_HOME/systemd/user/kuwai-hotwatch.timer
# touches: $XDG_CONFIG_HOME/systemd/user/timers.target.wants/kuwai-hotwatch.timer

d="$XDG_CONFIG_HOME/systemd/user"
[ -e "$d/kuwai-auth.service" ] || [ -e "$d/kuwai-shell.service" ] || exit 0
n=0
for u in kuwai-hotwatch.service kuwai-hotwatch.timer; do
    src="$KUWAI_ROOT/systemd/$u"
    [ -f "$src" ] || exit 0
    [ "$(readlink -f "$d/$u" 2>/dev/null)" = "$(readlink -f "$src")" ] && continue
    [ -e "$d/$u" ] && [ ! -L "$d/$u" ] && continue
    ln -sfn -- "$src" "$d/$u"
    n=$((n + 1))
done
w="$d/timers.target.wants"
if [ ! -e "$w/kuwai-hotwatch.timer" ]; then
    mkdir -p "$w"
    ln -sfn -- "$d/kuwai-hotwatch.timer" "$w/kuwai-hotwatch.timer"
    n=$((n + 1))
fi
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user start kuwai-hotwatch.timer 2>/dev/null || true
[ "$n" = 0 ] || echo "kuwai-hotwatch.timer on: a busy shell is noticed and what it was doing is kept"
