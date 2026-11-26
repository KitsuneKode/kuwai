# Agents, T3 and Usage: what holds them back, and the plan (2026-11-21)

Written after comparing the island's T3 capsule and the Usage panel with
[eliophan/t3code-bar](https://github.com/eliophan/t3code-bar) (MIT; ideas only,
no code of it is used: `refs/t3code-bar`). Each item says where its data comes
from today, so none of it is a guess about what exists.

## What t3code-bar does that we didn't

| | t3code-bar | kuwai before 2026-11-21 |
|---|---|---|
| The glanceable bit | One word for the most urgent state ("Approval", "Input", "Limited", "Failed"), a count only past one; settled = nothing | `T3 ① ✓ 13`: the working count, and finished threads not opened in T3 as permanent news |
| Spend | Cost / Tokens / Limits; 24h · 7d · 30d · 90d; a daily chart; per provider: cost, share, tokens, sessions | Limits only |
| Where spend comes from | T3 Code's own `server.getUsageSummary` (per provider and model, day or hour buckets, its own price list, sessions) | nothing |
| Rows | State word at the right, hover for the last reply, right-click to open or copy a link | the same since fc6b06c |

## Done (2026-11-21)

- **The capsule says what's wanted** (9695549): "Approval", "Question 2",
  "Limit reached", "Failed"; the turning ring only for plain work; the ✓ only
  when nothing is asking (`t3.mjs headline()`, tests/ui/pill.qml).
- **Spend from this machine's logs** (639ed5b): Claude Code, Codex and opencode
  logs, read incrementally, priced from `lib/spend-prices.json`; a line per
  provider card in Usage. Runs only while Usage is open.
- **The screens stay on while agents work** (62d3520): turning them off
  disconnected the external monitor and moved its workspaces.

## Done (2026-11-26)

1. **Providers service** (52ff6d6): `bin/kuwai-providers` + `services/Providers.qml`,
   T3's provider caches read field by field (the email in `auth` never reaches a
   dict); names, marks and models for T3 rows.
2. **Spend and tokens from T3's turns** (84173ff): `lib/t3usage.mjs`, read from
   `statev2.sqlite` without a token; partial and unrecorded turns said, never 0;
   OpenAI, Google and xAI prices with their source; T3's own sessions left out of
   the local logs.
3. **Marks everywhere** (84173ff): `island/AgentMark.qml` (tile, mark, two
   letters, the model's vendor badge, the T3 badge); Kiro's mark from T3 Code.
   Pi, Muse and fx have no mark in T3 Code's source yet: two letters.
4. **Usage** (84173ff, on 59a40c6): every provider T3 runs, its instances, "no
   price" rows, cache hit rate, coverage.
5. **Provider health** (52ff6d6): Usage's card, the Agents footer line. A tap
   opens Usage or T3 Code; T3's settings page has no known link to open it at.
6. **Rows say more** (63dd44f): context fill, "Cache warm 3 min", a limited T3
   thread's time back.
7. **One capsule** (63dd44f): it was one already; the ✓ now counts only what
   finished since you last opened the Agents panel.
8. **The rest**: Super+Ctrl+A already went to what needs you; the away recap
   says what failed or hit a limit; a daily budget (Settings → Bar) with cost on
   T3 rows and a footer line; a limited thread names an instance with room.

## What T3 Code already gives us (found 2026-11-21, no new token needed)

- **Every provider's state**: `~/.t3/caches/<instance>.json`, one per provider
  instance (23 here): `displayName`, `driver`, the owner's `accentColor`,
  `status` ready · warning · disabled with a `message` in words ("Sign in with
  ChatGPT to use Codex."), `auth.label` (the plan: "Claude Pro Subscription"),
  `models[]` with real names ("Claude Opus 5.5"). `auth` also holds email and
  workspace ids: never read past `label` and `status`.
- **Every turn's tokens**: `statev2.sqlite`,
  `orchestration_v2_projection_provider_turns.payload_json`:
  `turnTokenUsage` (input, output, cached, cache-creation, reasoning, models,
  `usageStatus` complete · partial · unavailable), `tokenUsage.usedTokens /
  maxTokens` (how full the context is), `tokenUsage.promptCacheExpiresAt`.
  kuwai-t3 already reads this database. So spend per provider, model and day
  comes from T3 itself, and item 1 of the old list (a `diagnostics:read`
  token) is no longer needed.
- **Model names**: `userdata/model-manifest.json` (slug → name per provider).
- **Provider marks**: T3 Code's own `apps/web/src/components/Icons.tsx` (MIT,
  `refs/pingdotgg_t3code`): Cursor, Kiro, Antigravity, ACP Registry, … — the
  ones `shell/assets/brands/` lacks (kiro, fx, pi, muse).

Measured this week: 650 turns; ~45 % ran on Antigravity, Codex, Devin, Grok
and Cursor, which Usage doesn't show, and `lib/spend-prices.json` prices only
Anthropic's models. 96 turns say `unavailable` and 94 `partial`.

## Next, in order

1. **Providers service** (`services/Providers.qml` + a reader): the caches
   above, watched (no poll), one entry per instance: name, driver, colour,
   status + message, plan label, models. The one place that turns a driver or
   model slug into a mark and a name (Limits, Kittymux, T3, Spend use it).
2. **Spend and tokens from T3's turns** (`bin/kuwai-spend` asks T3 first):
   per instance, model and day; `partial`/`unavailable` turns counted and
   said, never priced as 0. Prices for OpenAI, Google and xAI next to
   Anthropic's (source and date per row); a model without a price shows its
   tokens and "no price", like t3code-bar's muted rows. Don't count a session
   twice: T3 runs the Claude and Codex CLIs, which also write the local logs
   kuwai-spend reads today; T3's turns win for its sessions, local logs only
   for agents run outside T3 (kittymux panes).
3. **Marks everywhere**: T3 panel rows get the provider mark (today "Claude ·
   rice" in text) and the model's name with effort ("Opus 5.5 · high"); a
   harness that runs other vendors' models (OpenCode, Cursor, Devin,
   Antigravity) shows its mark with a small badge for the model's vendor
   (claude-* Anthropic, gpt-* OpenAI, gemini-* Google, grok-* xAI). The four
   missing marks from T3 Code's Icons.tsx (+ NOTICE row); no mark: two letters
   on the instance's colour.
4. **Usage: Limits · Spend · Tokens**, 24h / 7d / 30d / 90d: the total, a row
   per provider (mark, sessions, share, tokens, cost), a daily stacked chart
   (one Canvas, redrawn on new data only), the top 5 models, totals (processed,
   cached input = cache hit rate). Every enabled instance, Claude and Claude-2
   grouped under their account; not just the two cards of today.
5. **Provider health**: instances in `warning` named where you'd look (Usage's
   header, the Agents footer): "Codex-2: sign in with ChatGPT", click → T3's
   settings. Disabled ones stay out.
6. **Rows say more, quietly**: a working thread's context fill when > 70 %
   ("context 84 %": it will compact soon); an idle thread whose prompt cache is
   still warm ("cache warm 3 min": answering now is cheaper); a limited one
   says when it's back ("back 13:40") from Limits' reset time.
7. **One agents capsule** (T3 + kittymux, `headline()` over both), and the
   "✓ 17" goes: finished threads count until you've looked (opened the T3
   panel or T3), not forever. Settled = nothing, as t3code-bar does.
8. Then the earlier ideas, unchanged: "go to what needs me" key, away summary,
   cost on rows with a daily budget, limited → offer an instance that's ready
   and has room (status + Limits already say which).

Each step: a scene per new state in `tests/ui/scenes.json` (unpriced, partial,
warning provider, 90d with gaps, 20 instances), fixtures built from synthetic
JSON in T3's shapes, never this machine's database.

## Rules for all of it

- t3code-bar's boundary, adopted: read what T3 Code ships, never write it;
  name the T3 version a field was seen in; missing or changed data shows an
  explicit "unavailable", never an empty or wrong number.

- Nothing leaves the machine; T3 Code and kittymux are read, never written,
  except answering a prompt the way the Agents panel already does.
- Zero work while nothing shows it (a helper runs only while its panel is open,
  or streams pushes; never a poll that rereads everything).
- Every new state gets a scene; the rehearsal gate stays green and its known
  list stays empty.
