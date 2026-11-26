#!/usr/bin/env bash
# what: Clipboard history and GitHub/Gmail feeds become your choice (kuwai collect); what already ran at login stays on
# touches: $XDG_CONFIG_HOME/kuwai/collect.conf

f="$XDG_CONFIG_HOME/kuwai/collect.conf"
[ -e "$f" ] && exit 0
on() { compgen -G "$XDG_CONFIG_HOME/systemd/user/*.wants/$1" >/dev/null; }
lines=""
on kuwai-clipboard.service && lines+="clipboard=on"$'\n'
if on kuwai-feeds.service && { [ -e "$XDG_CONFIG_HOME/kuwai/feeds.json" ] || [ -e "$XDG_CONFIG_HOME/gh/hosts.yml" ]; }; then
    lines+="feeds=on"$'\n'
fi
[ -n "$lines" ] || { echo "collect.conf: nothing ran at login; the installer asks"; exit 0; }
mkdir -p "$(dirname "$f")"
printf '%s' "$lines" >"$f.new"
mv -- "$f.new" "$f"
echo "collect.conf: kept on what ran at login: $(printf '%s' "$lines" | tr '\n' ' ')(kuwai collect changes them)"
