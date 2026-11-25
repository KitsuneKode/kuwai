#!/usr/bin/env bash
# what: the launcher's use counts for the old "Vitals" action go to "System"
# touches: $XDG_STATE_HOME/kuwai/launcher.json

f="$XDG_STATE_HOME/kuwai/launcher.json"
[ -f "$f" ] || exit 0
jq -e '(if has("counts") then .counts else . end) | type == "object" and has("action:Vitals")' "$f" >/dev/null 2>&1 || exit 0
jq '
  def merge(c):
    (c["action:Vitals"]) as $v | (c["action:System"] // { n: 0, t: 0 }) as $s
    | c + { "action:System": { n: (($s.n // 0) + ($v.n // 0)), t: ([($s.t // 0), ($v.t // 0)] | max) } }
    | del(.["action:Vitals"]);
  if has("counts") then .counts |= merge(.) else merge(.) end
' "$f" >"$f.new"
mv -- "$f.new" "$f"
echo "launcher.json: Vitals' use counts now count for System"
