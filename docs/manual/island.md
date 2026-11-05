# Island

## Bar modes

- **Waybar** vs **Island**: Settings → Bar & Island, or `rice bar island|waybar`.
- **Rest**: workspaces, clock, status, activity dots (agents, alerts).

## Agent limit alerts

When **Agent limit alerts** is on, the shell runs `bin/rice-usage --watch`. Crossing **90%** on a session/week window (or hitting the cap) triggers **one island peek** — app name (Claude, Codex, …), window label, account, and how much is left. **Open usage** → notification center **Agents** tab. Nothing sits beside the clock.

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
