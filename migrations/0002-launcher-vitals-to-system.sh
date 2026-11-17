#!/usr/bin/env bash
# what: the launcher's use counts for the old "Vitals" action go to "System"
#
# f7fd72b (2026-11-17) made the island's two System views one: the launcher's
# "Vitals" action is gone and "System" answers to "vitals". The launcher ranks
# actions by how often and how lately you used them (Island.uses, kept in
# launcher.json as "action:<name>": { n, t }); what "Vitals" had earned was
# left under a name nothing shows. It's added to "System" (counts summed, the
# later time kept) and the old key goes, which also makes a second run a no-op.
# (Not additive: rolled back, the old release's Vitals would start from zero.
# It's a ranking, so that's acceptable; nothing else read the old key.)
#
# Checked 2026-11-18 for anything else stored under the old id: the panel id is
# never persisted (Island.open is in memory, the alias covers binds and
# scripts), settings.json has no panel ids, and the island's shape and
# clipboard state don't name panels.

f="$XDG_STATE_HOME/kuwai/launcher.json"
[ -f "$f" ] || exit 0
# Older files are the counts themselves; newer ones wrap them in { counts }.
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
