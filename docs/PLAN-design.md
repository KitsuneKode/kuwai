# Design and HyDE: what's next (2026-11-21)

From the owner's screenshots of 2026-11-21 (the centre at 09:32 and 09:33, the
island after the 09:36 crash) and a peek at the live centre afterwards.

## Done today

- **A click opens a notification**, and it leaves the list (handled), as on
  macOS; a folded stack unfolds first. A right-click opens the row's menu:
  Open, Read in the island, Reply, the app's own actions, Snooze, Copy link,
  Dismiss, Dismiss all from the app. Before, a click only selected the row,
  so everything you had "clicked" stayed.
- **What is no longer news leaves on its own** (`shell/services/notifTidy.mjs`):
  the same message again replaces the row before it (four identical "NVIDIA
  driver updated" rows were one message); a sudo prompt goes after ten
  minutes; low-urgency ones an hour after you've seen them (the dictation
  checks); a T3 thread's notification once you've opened that thread in T3;
  a transient notification (kuwai's own smoke test) is never kept.
- **Tooltips sit below what you hover** unless there is no room, on the same
  raised surface as the menus: "Show networks" was painted over the
  Controls search field.
- **The empty list after "Cleared 3"**: not reproduced; it was the build that
  crashed minutes later (the ScrollFade layer fault, fixed in b7f56bc). The
  `center-clear` fixture now pictures every clear, undo and arrival, and the
  rehearsal gate runs it.

## Design, next (in order)

1. **Controls: the Wi-Fi list where you asked for it.** The chevron on the
   Wi-Fi tile should open the networks in place of the tiles (the tile grows
   into the list, Back returns), not add a "Networks" section further down.
   The same for Bluetooth and the sound outputs. One pattern: a tile with a
   chevron expands into its list.
2. **One popover.** Menus, tooltips and the reply field are three surfaces
   today. One raised surface (Theme.menuSurface, menuEdge, Elevation) for all
   of them, anchored to what opened it, never over an input.
3. **Notification rows say less.** Group headers already name the app; the row
   repeats it in the title for some senders (voxtype: "voxtype" /
   "voxtype: …"). The adapters should drop a title equal to the app and a
   body prefix equal to the app.
4. **Counts that agree.** The tab badge counts everything kept; the list can
   be filtered. When a filter hides rows, the badge should say what is shown
   out of what is kept ("3 of 13").
5. **Brightness rows.** Monitor model names ("XV272U X1") mean little; name
   them by place (External, Built-in) with the model as a subtitle.
6. **Every panel, the same three checks** before it ships: its rehearsal scene
   at 1×, 1.2× and 2× text; keyboard and pointer reach the same things; a
   hover never hides something you are reading or typing into.

## How to work so the result is the best it can be

- A screenshot of something wrong becomes a scene (`tests/ui/scenes.json`) or
  a fixture first, so the fix is seen failing and then passing, and stays
  checked (`bin/kuwai-rehearse --gate`).
- Look at the sheet the gate writes, not only its verdict: the gate judges
  contrast, cut rows and sizes; taste is still a person's.
- Change the shared piece (Tips, ContextMenu, ListRow, Button) rather than one
  panel, so every panel gets it.

## HyDE: what's left to own

HyDE is already optional (docs/design/WITHOUT-HYDE.md has the table): without
it nothing breaks, but these come only from HyDE today. In order:

1. **Wallpaper.** Set it with `awww` directly and keep the current one in
   kuwai's state (`~/.local/state/kuwai/wallpaper`) instead of HyDE's
   `wall.set`; `bin/kuwai-wall` and the Theme panel pick from a folder of the
   owner's choosing. Lock, saver and login read kuwai's file.
2. **Colours from the wallpaper.** kuwai's own palette file, made from the
   wallpaper when it changes (a small extractor in `lib/`), read by
   `Theme.qml`, Hyprland's `theme.lua`, kitty and GTK; HyDE's wallbash becomes
   one possible source instead of the only one.
3. **Themes.** A kuwai theme is a folder: wallpapers, a palette, GTK, icon and
   cursor theme names. `bin/kuwai-themes` applies one with `gsettings`, Qt's
   and kitty's configs; HyDE's themes import into that shape once.
4. **Emoji and glyph lists.** Ship them in the repo (Unicode's emoji data and
   the Nerd Font names), so `:` and `;` in the launcher work everywhere.
5. **Pickers.** Super+Shift+E/A/R/U and the game launcher are HyDE's rofi
   scripts; the launcher already finds files, so the rest either move into it
   or go.
6. **Waybar.** The island replaces it; `kuwai-hyde-waybar` and `waybar_start`
   go when nothing asks for a bar.

`bin/kuwai-nohyde --strict` proves each step: the shell in a home without HyDE,
nothing warns, nothing is missing.
