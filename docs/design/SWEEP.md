# Idle projects (sweep in the island)

Old projects that hold disk space, as the `sweep` tool counts them
(<https://github.com/KitsuneKode/sweep>). Ported from the `feat/sweep-capsule`
branch (2026-11-17) onto the kuwai shell on 2026-11-22. Its notes moved here
from the code (ADR-010).

## Pieces

| Piece | Job |
|---|---|
| `bin/kuwai-sweep` | prints the last answer at once; when it is older than 6 h (30 min when the panel opens) it refreshes in the background at idle CPU and I/O priority, under a lock, written atomically to the cache. `--open [DIR]` opens sweep's own review in your terminal. |
| `shell/services/Sweep.qml` | reads only the cache (a few ms), never waits on a scan, and notices a finished refresh by watching the cache. Without sweep installed, `alive` is false and nothing shows. |
| `shell/services/sweepModel.js` | the pure part, tested in `tests/shell/sweep-model.test.mjs`: sizes ("16G"), the bar's parts (kinds under 4 % fold into "other"), a worktree's repo name, the headline, the panel's words for each state. |
| `shell/modules/island/SweepPanel.qml` | the panel: one bar of what the idle projects hold, by kind (node_modules, target, .next…), then the old projects holding the most. |
| `SysMarks` | the broom mark in the system capsule, with the size. |

## Decisions

- **Nothing is deleted from the island.** Removal stays behind sweep's own
  review and confirm; the island only looks and opens that review.
- **The mark steps back once you've looked.** Looking stores the size you saw;
  the mark returns only when the number grows 5 GB past it, not at every step.
- **Worth a mark:** at least `Settings.sweepMinGB` (10 GB by default).
- **Reclaimable counts only safe and caution items.** Dangerous and blocked
  ones show as "protected", never as space you can have.
- **Unknown is not idle.** A project whose last activity sweep could not read
  is not called idle.
- **A failed refresh keeps the last good answer** and notes `error` and
  `failedAt` beside it; the next try waits 30 min. The panel says why a count
  failed instead of "Counting…" forever.
- **The cache holds project names and paths** (0600, on this machine only).

## Keys (the panel)

↑ ↓ a project · ← → a part of the bar · Enter sweep's review of the chosen
project, or of the folder · Esc closes. Keys move at once, with no glide: they
repeat too often to animate.
