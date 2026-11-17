---
name: verify-kuwai
description: Drive and prove the kuwai shell (the island/notch, its panels, capsules, the launcher, wallpaper changes, agents) on the live Hyprland session without touching the user's pointer, keyboard, focus or media. Use after changing anything under shell/, bin/rice-*, greeter/ or hypr/kuwai, before promote, and whenever a claim "it works" needs evidence (screenshots, 60 fps frames, logs, state dumps).
---

# Verify kuwai (live session, the user is at the machine)

The user works in the same session while you test. Rules that came from real incidents: never move the
pointer (follow_mouse moves focus), never type text (ydotool/wtype), never open a keyboard-grabbing panel
for a screenshot, never pause/play their media. Everything below is read-only or uses the shell's own
test hooks. `q` below is `qs ipc -p ~/Projects/rice/shell call` (zsh: write a function,
`q() { qs ipc -p $HOME/Projects/rice/shell call "$@"; }`; a `$Q` string variable does not split).

## Launch
The live shell runs from the dev checkout (`~/Projects/rice/shell`, file watching on): saving a file
reloads it. Stable (`~/.local/share/kuwai`) moves only with `bin/rice promote` (runs `rice-check`).
Ready = the log's last reload line is `Configuration Loaded`:
`qs log -p ~/Projects/rice/shell | grep -nE "Reloading|Failed to load|caused by|Configuration Loaded" | tail -3`
A failed reload keeps the previous shell running: the log is the only sign. Touch the file to retry.

## Doctor (before driving, and after anything surprising)
- `bin/rice check` — load, orphans, idle owner, memory budget, CPU at rest (median of 5 s, want < 5 %),
  compile of every module and component, token ratchet.
- `q island state` (which panel is open where), `q islandbar-<SCREEN> dump` (why an island is in a state).
- `q lock state` must be `unlocked` before promote.

## Drive (test hooks; no keyboard focus is taken)
| Want | Call |
|---|---|
| Hover glance / full view on a screen | `q islandbar-DP-3 hover glance\|full\|off` |
| A panel shown without keyboard focus | `q test preview <panel> DP-3` … then `q island close` |
| Fake agent states (pinned against kittymux's heartbeats) | `q test agentStates "working,waiting"` … `q test clear` |
| Allow/Deny for a pane as the Agents panel does | `q test answerKey <paneKey> allow\|deny` |
| A live activity in the notch | `q timer start 2m "test x"` (cleared by `q test clear`) |
| A wallpaper change | `q wallfx play <path>` / `q wallfx stats` |
| Compile one file in the live engine | `q test compile <path relative to shell/>` |
| Peeks, moments, cards, settings pages | `q test peek DP-3 short`, `q test moment`, `q test card alarm x`, `q test settings N` |

## Evidence
- Stills: `grim -o DP-3 file.png` (eDP-1 screencopy can return the previous frame on this hybrid GPU;
  prefer DP-3). Crop with `magick … -crop WxH+X+Y`.
- Motion: start the recorder **before** changing state (starting a capture folds an open island):
  `(gpu-screen-recorder -w DP-3 -f 60 -o rec.mp4 &)`, drive, `pkill -INT -x gpu-screen-reco`. Then
  `ffmpeg -ss … -t … -i rec.mp4 -vf "crop=W:H:X:Y,fps=40" f/%02d.png` and find the change by sampling a
  region's mean (`magick f.png -crop … -colorspace gray -format '%[fx:mean]' info:`); read the frames.
- Logs: the `qs log` lines after the last `Configuration Loaded` (TypeError/ReferenceError are real).
- Keep evidence in the session scratchpad; say what you could not see (anything needing a real pointer:
  drag, swipe, hover timing; the login screen; real agent prompts).

## Cleanup
`q test clear` (fake agents, test timers, peeks), `q island close`, `q islandbar-DP-3 hover off`; stop any
recorder you started (`pkill -INT -x gpu-screen-reco`, never by a broader pattern). Restore anything you
changed for the test (a wallpaper: play the original back).

## Feature map (what to prove per surface)
- **Island rest/glance/full:** centre click opens full; capsules bud from the edge, icon arrives after;
  state change swaps content without a blank frame or a full-strength first frame.
- **Sections:** Agents/Usage/System/Cleanup strip lit on the current one; ⌥1–4 switch in place.
- **Cleanup:** big number = report's unusedTokens; nothing clipped at the island's ceiling.
- **System:** LinkedBar parts sum ≤ used memory; legend and dots light together.
- **Media:** titles cleaned (`bun test tests/shell/media-text.test.mjs`); a film's frame only for the
  window whose title is the track.
- **WallFx:** `wallfx stats` lastRun "revealed N s"; `awww query` shows the new picture on every screen.
- **Agents hook path:** a real `kittymux/bin/mux-ask` request appears (`~/.local/state/kittymux/asks`),
  `test answerKey` returns "answered through the hook", the hook prints the decision.
- **Bar:** after any theme or colour-mode switch, `pgrep -x waybar` is empty 12 s later.
