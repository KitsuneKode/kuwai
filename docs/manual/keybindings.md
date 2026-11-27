# Keybindings

Press **`Super+/`** (or hold **`Super`** for ~0.9 s) to view every live binding in the Shortcuts panel, or run `kuwai binds [word]`.

## Customising shortcuts

- Open **`Settings → Shortcuts`** (`Super+Ctrl+I`) and click any row to record a new chord. Conflicts are flagged before replacing; overrides are stored in `~/.config/kuwai/keys.tsv` and applied live (`kuwai keys`).
- **Function keys:** `F7`, `F8`, and `F10` control brightness and mute by default. Switch **`Settings → Keyboard → Function keys`** to **Plain** (`kuwai set fKeys plain`) to leave `F7`/`F8`/`F10` to applications.
- For custom app bindings, edit `~/.config/kuwai/hypr/user.lua`.

## Shell and island (`hypr/kuwai/binds.lua`)

| Keys | Action |
| --- | --- |
| `Super+A` | Launcher (apps, windows, files, `=` calc, `!` processes/ports, `+` packages) |
| `Super+N` | Notifications center |
| `Super+Ctrl+Space` | Controls (Wi-Fi, Bluetooth, Sound, DND, Display) |
| `Super+Ctrl+Alt+W` | Wi-Fi networks |
| `Super+Alt+B` | Bluetooth |
| `Super+Alt+N` | Toggle Do Not Disturb |
| `Super+Shift+Alt+N` | Open the newest notification |
| `Super+Ctrl+Enter` | Answer active island card (peek, alarm, reminder, timer) |
| `Super+Shift+N` | Agents panel (every kitty pane, T3 thread, and hooked agent) |
| `Super+Ctrl+A` | Jump to the agent waiting on you |
| `Super+V` | Clipboard island |
| `Super+Shift+V` / `Super+Alt+V` | Clipboard pins |
| `Super+Ctrl+J` | Quick note (`~/Notes/inbox.md`) |
| `Super+Ctrl+Shift+J` | Remind me |
| `Super+Alt+C` | Calendar |
| `Super+Ctrl+I` | Settings |
| `Super+Shift+T` | Themes |
| `Super+Shift+W` | Wallpapers |
| `Super+Ctrl+Shift+U` | Software Update |
| `Super+Ctrl+Shift+A` | Local AI Assistant (opt-in) |
| `Super+L` | Lock screen |
| `Super+Backspace` | Power menu (hold to confirm) |
| `Super+/` | Keyboard shortcuts sheet |
| `Super+Shift+/` | Desktop mode picker (focus, default, glass, gaming, battery) |
| `Super+Alt+G` | Toggle Gaming mode |
| `Super+Shift+C` | Toggle Caffeine (keep awake) |
| `Super+Ctrl+G` | Focus session (25 min DND; press again to stop) |
| `Super+,` / `Super+.` | Emoji (`:`) / Nerd Font glyphs (`;`) |
| `Super+Alt+I` | Peek island details (in minimal mode) |
| `Ctrl+Alt+W` | Tuck/untuck the island (or toggle Waybar when using Waybar) |
| `Ctrl+Alt+Shift+W` | Toggle island rest style (minimal / everything) |

## Wallpapers and screensavers

| Keys | Action |
| --- | --- |
| `Super+Alt+]` / `Super+Alt+[` | Next / previous still wallpaper |
| `Super+Ctrl+]` / `Super+Ctrl+[` | Next / previous live wallpaper |
| `Super+Ctrl+Alt+]` / `Super+Ctrl+Alt+[` | Next / previous screensaver |
| `Super+Alt+Shift+S` | Start screensaver now |

## Windows, workspaces, and columns

| Keys | Action |
| --- | --- |
| `Super+Q` / `Alt+F4` | Close window |
| `Super+W` | Float / tile window |
| `Super+F` / `Super+F11` | Fullscreen |
| `Super+Shift+F` | Maximize (bar and gaps stay) |
| `Super+Ctrl+F` | Pin window on every workspace |
| `Super+G` | Toggle window group (tabs) |
| `Super+[` / `Super+]` | Previous / next tab, column, or window |
| `Super+J` | Rearrange layout |
| `Super+Esc` | Jump to urgent window or previous window |
| `Super+Tab` / `Super+Ctrl+Up` | Mission Control (workspace overview) |
| `Super+Shift+Tab` | Previous workspace on this screen |
| `Alt+Tab` / `Alt+Shift+Tab` | Window switcher (hold `Alt`) |
| `Alt+\`` | Switch windows of the current app |
| `Super+Alt+Tab` | Switch windows on this workspace |
| `Super+Arrows` | Focus left / right / up / down |
| `Super+Shift+Arrows` | Move window |
| `Super+Alt+Arrows` | Resize window |
| `Super+Ctrl+S` | Resize mode (`h/j/k/l` or arrows, `Shift` faster, `=`/`-` column width, `Enter`/`Esc` exit) |
| `Super+Left Click` / `Super+Z` | Drag to move window |
| `Super+Right Click` / `Super+X` | Drag to resize window |
| `Super+1`…`0` | Switch workspace 1–10 on this screen (`Shift` moves window, `Alt` sends without following) |
| `Super+Ctrl+Left` / `Right` | Previous / next workspace (`Shift` carries window) |
| `Super+Ctrl+Down` | First empty workspace on this screen |
| `Super+Alt+Shift+H` / `L` | Previous / next busy workspace (also `Super+Scroll`) |
| `Super+Alt+L` | Cycle workspace layout (scrolling, dwindle, monocle, floating) |
| `Super+S` / `Super+Shift+S` / `Super+Alt+S` | Toggle scratchpad / move window / send window (stay) |
| `Super+\`` / `Super+Shift+\`` | Drop-down console / move window to console |
| `Super+O` / `Super+Shift+O` | Minimize window / restore last minimized |
| `Super+Alt+W` / `Super+Alt+Shift+W` | Picture-in-picture: next corner / other screen |
| `Super+Ctrl+K` | Click a window to kill it |
| `Super+Delete` | Quit Hyprland |

### Scrolling columns and multi-monitor

| Keys | Action |
| --- | --- |
| `Ctrl+Alt+Arrows` | Focus column left/right or window up/down (`Ctrl+Alt+Scroll` scrolls tape) |
| `Ctrl+Alt+=` / `-` | Wider / narrower column |
| `Ctrl+Alt+C` / `X` | Next / previous preset column width |
| `Ctrl+Alt+P` | Promote window to its own column |
| `Ctrl+Alt+A` / `S` | Swap column left / right |
| `Ctrl+Alt+F` / `E` | Fit active column / fit all visible |
| `Ctrl+Alt+Shift+F` / `E` | Scroll column into view / grow into free space |
| `Ctrl+Alt+G` | Inhibit scrolling on this workspace |
| `Ctrl+Alt+Enter` | Centre active column |
| `Super+Alt+F` / `Super+Alt+Shift+F` | Tile two windows side by side (right / left) |
| `Ctrl+Alt+Tab` / `Shift+Tab` | Next / previous monitor |
| `Super+Ctrl+Alt+Left` / `Right` | Move window to monitor (`Shift` moves workspace's windows) |

## Launching apps

| Keys | Action |
| --- | --- |
| `Super+T` / `Super+Enter` | Terminal |
| `Super+Shift+Enter` | Terminal in the focused terminal's folder (`kuwai-term`) |
| `Super+Ctrl+T` / `Super+Alt+T` | Drop-down terminal / floating terminal |
| `Super+Alt+Enter` / `Super+Alt+Shift+Enter` | Claude Code / Codex in the focused folder (`kuwai-agent`) |
| `Super+E` | File manager |
| `Super+C` | Editor |
| `Super+Shift+B` | Browser |
| `Super+Shift+Esc` | System monitor |

## Capture, hardware, and zoom

| Keys | Action |
| --- | --- |
| `Super+P` | Screenshot region and annotate |
| `Super+Alt+P` | Screenshot region (no editor) |
| `Super+Ctrl+P` | Freeze screen, then screenshot region |
| `Super+Ctrl+Alt+P` | Screenshot active window |
| `Super+Shift+Alt+P` | OCR region to clipboard |
| `Super+Ctrl+Shift+P` | Screenshot current monitor |
| `Print` / `Shift+Print` | Screenshot all monitors / current monitor in 3 s |
| `Super+Shift+P` | Colour picker (`hyprpicker -an`) |
| `Super+Shift+Alt+R` | Screen recording setup or stop |
| `Super+Ctrl+Alt+R` | Record region (press again to stop) |
| `XF86AudioRaiseVolume` / `LowerVolume` / `Mute` (`F10`) | Output volume and mute |
| `XF86AudioMicMute` / `Ctrl+Alt+M` | Toggle microphone mute |
| `XF86AudioPlay` / `Prev` / `Next` (`Super+F7` / `F6` / `F8`) | Media play/pause, previous, next |
| `XF86MonBrightnessUp` / `Down` (`F8` / `F7`) | Brightness (`Super+Alt+F7` toggles focused screen vs all screens) |
| `Super+K` | Next keyboard layout (bound only when multiple layouts are configured) |
| `Super+Alt+=` / `-` (`Alt+Shift+Scroll`) | Zoom in / out at cursor (`Alt+Shift+Middle Click` resets) |

## Dictation (only when `voxtype` is installed, `hypr/kuwai/voxtype.lua`)

| Keys | Action |
| --- | --- |
| `F9` (hold) | Push-to-talk dictation (tap for hands-free) |
| `Super+Ctrl+D` / `Super+Shift+F23` | Start / stop dictation |
| `Super+Shift+D` / `Esc` | Cancel active dictation |
| `Super+Ctrl+Alt+D` | Recover the last cancelled dictation (kept 10 min in RAM) |
| `Super+Ctrl+E` | Edit the current selection by voice |
| `Super+Ctrl+Shift+D` | Teach a dictation correction |
| `Super+Alt+D` | Open Voxtype Studio (if installed) |

## Inside panels

- **Island section strip:** `Alt+1` Agents · `Alt+2` Usage · `Alt+3` System · `Alt+4` Cleanup.
- **Notification Center:** type to search · `↑`/`↓` select · `Enter` open · `Delete` dismiss · `←`/`→` fold/expand group · `Tab` filter · `Ctrl+Tab` switch tab · `Ctrl+D` DND · `Ctrl+Z` undo clear · `Esc` clear search then close.
- **Clipboard (`Super+V`):** `↑`/`↓`/`←`/`→` move · `Enter` paste into previous window · `Shift+Enter` copy · `Space` Quick Look · `Ctrl+E` edit · `Ctrl+P` pin · `Ctrl+O` OCR · `Ctrl+K` actions · `Ctrl+X` / `Shift+Delete` delete (`Ctrl+Z` undo) · `Ctrl+H` reveal masked secret · `Alt+1`–`9` paste nth item.
- **Settings (`Super+Ctrl+I`):** `↑`/`↓` switch section · type (or `/` / `Ctrl+F`) to search every setting · `Tab` / `Shift+Tab` walk controls · `Esc` clear search then close.
