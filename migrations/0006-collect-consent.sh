#!/usr/bin/env bash
# what: Clipboard history and GitHub/Gmail feeds become your choice (kuwai collect); what already runs stays on
# touches: $XDG_CONFIG_HOME/kuwai/collect.conf

f="$XDG_CONFIG_HOME/kuwai/collect.conf"
[ -e "$f" ] && exit 0
on() { systemctl --user -q is-enabled "$1" 2>/dev/null || systemctl --user -q is-active "$1" 2>/dev/null; }
clip=off; feeds=off
on kuwai-clipboard.service && clip=on
on kuwai-feeds.service && feeds=on
mkdir -p "$(dirname "$f")"
printf 'clipboard=%s\nfeeds=%s\n' "$clip" "$feeds" >"$f.new"
mv -- "$f.new" "$f"
echo "collect.conf: clipboard history $clip, feeds $feeds (kuwai collect changes them)"
