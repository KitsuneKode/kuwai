#!/usr/bin/env bash
# what: "Hide sensitive message text" becomes Message privacy (chat messages hidden on the lock screen, shown on the desktop)

f="$XDG_CONFIG_HOME/kuwai/settings.json"
[ -f "$f" ] || exit 0
jq -e 'has("notifRedactSensitive")' "$f" >/dev/null 2>&1 || exit 0
jq 'if .notifRedactSensitive == false and (has("notifPrivacy") | not) then .notifPrivacy = "never" else . end | del(.notifRedactSensitive)' "$f" >"$f.new"
mv -- "$f.new" "$f"
echo "settings.json: Message privacy replaces Hide sensitive message text"
