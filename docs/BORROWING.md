# Borrowing

Shallow clones live in `refs/` (gitignored). Refresh with
`git -C refs/<name> pull --depth 1`. Read them for ideas and patterns, then
rewrite in our own style and tokens. Don't copy whole files in.

| Ref | What it is | Worth taking |
|---|---|---|
| `caelestia-dots_shell` | Quickshell, Material-ish, very polished motion | structure, notifications, drawers |
| `end-4_dots-hyprland` | Quickshell "illogical-impulse" (`dots/.config/quickshell/ii`) | feature breadth: overview, sidebars, OSK, region selector |
| `AvengeMedia_DankMaterialShell` | Quickshell (`quickshell/`), very complete | notification rules/policy, control center, settings UI |
| `emilkowalski_sonner` | the React toast library, the reference for our toast stack | exact constants and transitions (`src/index.tsx`, `src/styles.css`) |
| `noctalia-dev_noctalia-shell` | now a native C++ shell, no longer Quickshell | design and UX ideas only, plus its ARCHITECTURE.md on frame phases |

## Pointers by topic

**Notifications**
- caelestia `services/Notifs.qml` + `NotifData.qml`: wrapper objects over
  `Notification`, JSON-persisted history, DND, fullscreen suppression, and
  "locks" so an expanded card isn't removed under the pointer. We adopted the
  wrapper and persistence ideas.
- caelestia `modules/sidebar/Notif*.qml`: grouped notification center. This is the
  model for our next piece.
- DMS `quickshell/Services/NotificationService.qml`: dedup keys, per-app rules
  (match by desktopEntry/appName → urgency/DND bypass/no-history), and a popup
  queue that merges by group. Our `NotifAdapters` is a lighter version.
- end-4 `ii/services/Notifications.qml` and `ii/modules/ii/notificationPopup/`.

**Shell structure**
- caelestia `modules/drawers/`: one fullscreen layer per screen with
  `Regions`/`Exclusions` for input masks, which lets panels animate across
  the whole screen. Consider it once there are several panels.
- caelestia `components/` (`Anim.qml`, `CAnim.qml`, `StyledText.qml`,
  `StateLayer.qml`): token-bound wrappers for animations and text. Worth doing
  for us too once there are more modules (`Anim` defaults to `Theme.enterMs` …).

**OSD / bar / control center**
- DMS `Modules/OSD`, `Modules/ControlCenter`, `Modules/DankBar`.
- end-4 `ii/modules/ii/onScreenDisplay`, `ii/modules/ii/bar`, `sidebarRight` (quick toggles).

**Quickshell gotchas found so far**
- `DesktopEntries` scans lazily: touch `DesktopEntries.applications` at startup
  or the first `byId()` returns null.
- `ScriptModel.values` wants a JS array. A `list<QtObject>` property won't assign,
  so keep model sources as `var`.
- `keepOnReload` notifications come back through `onNotification` on every hot
  reload with `lastGeneration` set; reattach them, don't add them again.
- Notification images can be in-memory handles (`image://qsimage/…`) or temp
  files: never persist them, keep the app icon instead.
- New files in a module dir aren't picked up by hot reload: restart.
- `font.pixelSize` is an int; fractional values fail to load the whole file.
- With `~/.config/quickshell/shell.qml` present, `qs -c <name>` finds nothing:
  run by path.
