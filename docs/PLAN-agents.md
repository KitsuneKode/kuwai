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

## Next, in order

1. **Spend from T3 Code itself** (the biggest gap left). `server.getUsageSummary`
   is in the installed T3 Code (nightly) and covers every provider T3 runs,
   with T3's up-to-date prices and session counts. It needs a token with
   `diagnostics:read`; kuwai's token has `orchestration:read` only, and minting
   one is the owner's call:
   `t3 auth session issue --scope diagnostics:read --label kuwai-spend --ttl 365d --token-only > ~/.local/state/kuwai/t3-usage-token && chmod 600 ~/.local/state/kuwai/t3-usage-token`
   Then: `bin/kuwai-spend` asks it first (day buckets for 90 days, hour buckets
   for 24h), the local logs stay the fallback while T3 Code is closed.
2. **A Spend view in Usage**: Limits · Spend tabs; 24h / 7d / 30d / 90d; the
   total, a daily bar chart (one Canvas, drawn once per change), per provider:
   cost, share of the total, tokens, sessions. A scene per period.
3. **Limits with their history**: kittymux's `agent-usage-trends.json` samples
   each limit over time; draw the last day as a line under each bar and forecast
   "runs out at" from the real slope (Usage now forecasts from the window's
   average pace).
4. **One agents capsule**: T3 threads and kittymux panes are one list in the
   Agents panel already; the island still has two capsules counting separately.
   One capsule with the headline across both (`headline()` over T3 threads and
   kittymux states), the brands as small marks.
5. **"Go to what needs me"**: one key (beside Super+Shift+N) that opens the most
   urgent thing directly: the kitty pane asking, or the T3 thread at its
   approval. Super+Ctrl+↵ already answers the island's card.
6. **Away summary**: back at the desk after the lock, one card: "3 finished, 1
   needs approval, ~$4.20" instead of a stack of toasts; built from the inbox
   and T3's items.
7. **Cost on the rows**: T3's summary carries a session's source; show a
   thread's cost on its row (quiet, right-aligned under the state) and a daily
   budget (Settings) that notifies once when today's estimate passes it.
8. **Limited → elsewhere**: when a provider is out, its rows say when it's back
   and offer "continue in Codex/Claude" where the pane's agent can switch.

## Rules for all of it

- Nothing leaves the machine; T3 Code and kittymux are read, never written,
  except answering a prompt the way the Agents panel already does.
- Zero work while nothing shows it (a helper runs only while its panel is open,
  or streams pushes; never a poll that rereads everything).
- Every new state gets a scene; the rehearsal gate stays green and its known
  list stays empty.
