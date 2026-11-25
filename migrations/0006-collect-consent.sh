#!/usr/bin/env bash
# what: Clipboard history and GitHub/Gmail feeds become your choice (kuwai collect); what already ran at login stays on
# touches: $XDG_CONFIG_HOME/kuwai/collect.conf

f="$XDG_CONFIG_HOME/kuwai/collect.conf"
[ -e "$f" ] && exit 0
units="$XDG_CONFIG_HOME/systemd/user"
clip=off; feeds=off
[ -e "$units/kuwai-clipboard.service" ] && clip=on
if [ -e "$units/kuwai-feeds.service" ] && { [ -e "$XDG_CONFIG_HOME/kuwai/feeds.json" ] || [ -e "$XDG_CONFIG_HOME/gh/hosts.yml" ]; }; then
    feeds=on
fi
mkdir -p "$(dirname "$f")"
printf 'clipboard=%s\nfeeds=%s\n' "$clip" "$feeds" >"$f.new"
mv -- "$f.new" "$f"
echo "collect.conf: clipboard history $clip, feeds $feeds (kuwai collect changes them)"
