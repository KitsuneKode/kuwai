# Island

## Bar modes

- **Waybar** vs **Island**: Settings → Bar & Island, or `rice bar island|waybar`.
- **Rest**: workspaces, clock, status, activity dots (agents, alerts).

## Usage limits in the notch

`bin/rice-usage --watch` runs from startup (T3 Code pushes changes; nothing polls). If it dies, the last reading stays and it comes back on its own (2 s, doubling to 5 min).

- **Approaching** (a window ≥ **80 %**, Settings → Bar & Island → *Alert at*): one Moment, e.g. "Claude weekly · 82% · resets Tue". Once per window per reset period, remembered in `~/.local/state/rice/limits-told.json` across restarts. No mark stays.
- **Used up** (100 %): a Moment "Claude weekly · used up · resets in 3d 15h", then a mark on the notch: the gauge and the soonest reset ("3d") in a solid orange ring. It stays while a live activity has the stage, like a warning.
- **Reset** (`resetsAt` passes, or `used` drops): the mark goes, with a quiet "Claude weekly · reset".
- Moments wait their turn in the queue, and none are shown under Focus or while sharing the screen (the mark still is).
- **Usage panel**: rest on the mark, click it, or `rice usage`. **All** lists every window, used-up first, then by how much is used; one tab per provider after it. **Tab** / **Shift+Tab** change tabs, **Esc** closes. If rice-usage isn't running it says so, with **Retry**.
- Off: Settings → Bar & Island → *Limit alerts in the notch* (`rice set limitAlerts false`).

## Hover

Clock, media, workspaces, tray, **bell with badge** (click → center, **hold** → quick list), Focus/DND.

## Media (rest row, hover, Now Playing)

When a player has a track loaded (`Media.active`), the rest row can show album art plus bars (Settings → rest media). **Playing**: full activity chip + live peaks. **Paused**: clock and status stay; art and a still bar silhouette sit beside them (music does not take over the notch like dictation). Hover card and Now Playing unchanged.

**Try it:** play, then pause — clock and status stay; art and calm bars remain (no “Paused” label).

**Approach:** Settings → **Reveal on approach** (default on). In **auto** rest, a compact activity chip (e.g. paused music) also reveals the full row when you near the top edge.

## Settings

Super+, launcher “Settings”, or `rice settings`.

## Now Playing: the player's own action

One extra button beside the waveform, by player (`bin/rice-player`):

- **Cider**: ♥ Love (Apple Music rating) through Cider's local API (127.0.0.1:10767). If Cider asks for a token: Cider → Settings → Connectivity → Manage External Application Access, then `rice-player cider-token` (kept in the keyring).
- **A browser that reports the page** (Brave, Chrome): copy the link; on YouTube, at the current second. Firefox/Zen don't report the page, so no button; click the art to jump to the tab.
- **L** does the same from the keyboard. The answer shows in the subtitle line ("Loved", "Link copied at 1:35", or what went wrong).
- YouTube captions can't be toggled from outside the browser without faking a keypress into it, so kuwai doesn't.

## Warnings at rest

A warning (CPU temperature, memory, disk) never takes over the notch: it shows as its mark and value (🌡 96°) beside the time or the music, in its colour. Click it for System.
