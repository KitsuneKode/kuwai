# Rex, one week in — what it shows, and what we adopt

Source: *Rex Already Got Better* (Sam Natale, 2026-11-04, 9:19).
Transcript: `transcript.md` (local Parakeet; YouTube subtitles were
rate-limited). Frames: `NN_hhmmss.jpg`, all nine in `contact-sheet.jpg`.

## What the video shows

| Time | Feature | What it is / how it looks |
|---|---|---|
| 00:12 | Changelog splash | "Rex · week 1" with `rex --whats-new` listing cursor trails and floating panes (01) |
| 00:20–00:55 | **Cursor trails** | GPU cursor shaders (comet, sweep, warp, rainbow) under Developer options → bleeding edge |
| 00:55–01:45 | **Floating panes, minimizable** | Toggle a pane floating; minimize it to a **chip at the bottom right**: app icon + label ("Claude Code", "pnpm ~/Projects/…"), click restores (01, 02). Several at once, with a count; minimize or restore all |
| 02:30–03:00 | **Activity mode: group by priority** | A filter menu (04): *All hosts / This Mac / Mac Mini*, *Show idle processes*, *Show each process in tabs*, *Group by session* or *Group by priority*. By priority, every agent across sessions and hosts sorts into **working, done, awaiting input** |
| 03:00 | **Mute an agent** | Right-click → mute: it keeps running and tracked, but sends no "come check me" notification when it finishes |
| 03:20 | **Close confirmation for a busy agent** | Closing a pane whose agent is mid-response asks "are you sure?" (07: a small inline prompt in the sidebar). New this week |
| 03:35–04:05 | **Remote hosts** | Sidebar grouped by host ("This Mac", "Mac Mini"), then project path, then sessions with app icons (06). Over Tailscale; "native performance" (nvim on the remote feels local). Multi-host is planned |
| 04:05 | **Auto-update** | "Update installed automatically"; relaunch restores every session exactly |
| 04:30–06:30 | **Agent-native via Rex skills** | With the agent integration and Rex skills, Claude runs `rex ls --json` and `rex new … -c …` (09) to make a worktree, a session, and **visible tabs for each dev server** (API, web, admin), instead of hidden background processes. Close the agent and everything keeps running |
| 05:00–07:20 | **Worktree workflow** (his scripts, bound to Rex actions) | Ctrl+B: a branch worktree with the ignored files (env) copied, dropped straight into its session. Cmd+O: open a project (an fzf picker). Ctrl+Shift+O: open a worktree. Cmd+Shift+B: delete a worktree, which **also closes its session** |
| 07:20–08:00 | **Fork the agent session** | Cmd+Shift+F opens a forked Claude beside the current one, so you can try plan B without touching A; close the pane and revert if B loses |
| 08:00–09:00 | Gaps he names | Pickers are user scripts (fzf), not native; he wants them in a **command palette**. Free for personal use |

Known from launch (not new): pill tabs with app icons, a two-line header,
per-pane title bars with split/zoom/close, tab hover thumbnails, an "Exited"
pill, theme migration. New this week: cursor trails, floating/minimized
panes, priority grouping, mute, close confirmation, auto-update, skills.

## What we adopt (ranked: value for an agent-first multiplexer ÷ cost)

1. **Group by priority**, beside Machine → Space. One key (`g`) toggles the
   kittymux panel between *by space* and *by state* (Needs you → Working →
   Finished → Idle), across every session. kuwai's Agents tab adopts the same
   order across sources (kittymux + T3 Code), so it's one list by state.
   *Cost: small; the state contract already has it.*
2. **Mute an agent.** A `muted` flag in the status contract
   (`kittymux mute <tab>`, right-click in the panel, `m` on a row). Muted:
   no toast, no notch moment, no "needs you" chip, still in the lists with a
   quiet bell-slash. kuwai's Notifs honours it.
   *Cost: small; the biggest everyday win against agent noise.*
3. **Confirm closing a busy agent.** Closing a pane or tab whose agent is
   Working or Needs you asks first (kitty's close is wrapped by a kittymux
   action that checks the state; a one-line inline prompt, not a dialog).
   *Cost: small; prevents lost runs.*
4. **Agent-facing CLI + skill**, the strongest idea in the video. Document
   and harden `kittymux ls --json`, `kittymux new-tab --cwd D -- cmd` and
   `kittymux run --title T -- cmd`, and ship a Claude/Codex skill: "run dev
   servers and long jobs in visible kittymux tabs, never as background
   processes". kuwai's Agents tab and notch then see those tabs as the
   agent's own. *Cost: medium (verbs exist in part; skill + docs).*
5. **Minimized panes as chips.** kitty can't hide a window inside a tab, so a
   minimized pane moves to a hidden "stash" tab; the panel's footer (and
   kuwai's notch, as a mark with a count) shows a chip per stashed pane:
   icon + label, click restores it to where it was.
   *Cost: medium.*
6. **Worktree verbs.** `kittymux worktree new <branch>` (copies the
   gitignored env files, opens a session there), `open`, and `rm`, which also
   closes its tabs. As native panel actions with a picker, so no fzf
   scripts. *Cost: medium.*
7. **Fork an agent** (Claude Code's `--resume <id> --fork-session`): an
   action that opens the fork in a split beside the original.
   *Cost: medium; Claude-first, others when their CLIs allow.*
8. **A command palette** (the thing Rex users still lack): every action and
   picker in one fuzzy list in the panel. *Cost: medium; it's where 5–7 live.*
9. **Cursor trail:** kitty has one natively (`cursor_trail 1`,
   `cursor_trail_decay`). Suggest a subtle preset in the docs; no shader work.
   *Cost: nothing.*
10. **Remote hosts:** later. kitty's ssh kitten plus kittymux on the remote,
    grouped by host in the panel. *Cost: large.*

**Don't adopt:** rainbow or comet trails (motion at rest, against calm);
fzf pickers in a terminal popup (the palette does it natively); auto-update
of kittymux itself (the user's update flow handles packages).

## Fixes for PR #13 first (wave 3.1, before the features above)

1. The pixel panel and the cell bar both list the same tabs: hide the bar
   while the panel shows.
2. Child pane rows say the repo ("website") twice: show what runs in the
   pane (agent or command).
3. The key-hint boxes and the prompt preview under the pixel panel: render
   the hints in the panel's own style, and drop the preview (the pane
   already shows it).
4. The cell bar's grey and gold progress block reads as a glitch: a thin
   ring or a percentage instead.
5. Pink accent + orange + gold on one row: dim the accent hairline to about
   45% so state colours lead.

## Order

Wave 3.1 (the five fixes) → 1, 2, 3 (one small PR: priority, mute, confirm)
→ 4 (CLI + skill) → 8 with 5–7 → 9 (docs) → 10.
