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
| `Tide-island` | Quickshell + C++ Dynamic Island for Hyprland/niri (GPL-3: ideas only, never code) | island morph, swipe between capsules, exact-shape blur, lean-memory habits |
| `noctalia-dev_noctalia-shell` | now a native C++ shell, no longer Quickshell | design and UX ideas only, plus its ARCHITECTURE.md on frame phases |
| `vercel_ai-elements` | shadcn AI Elements (`packages/elements/src/`) | tool / confirmation / reasoning / model-selector / prompt-input / context states and anatomy |
| `ibelick_prompt-kit` | shadcn chat blocks (`components/prompt-kit/`) | stick-to-bottom chat container, scroll button, thinking bar, steps |
| `assistant-ui_assistant-ui` | React chat runtime | message action semantics (copy, edit, regenerate, feedback) |
| `pingdotgg_t3code` | T3 Code, multi-provider agent GUI (MIT) | the runtime event vocabulary, how Antigravity/Codex/Claude tool calls and child work are normalised, timeline rows, model picker |
| `openai_codex` | Codex CLI, sparse: `codex-rs/tui`, `codex-rs/protocol` | how a running command and its approval read; compaction |

## Pointers by topic

**The island (Tide-island)**
- `qml/common/InsetBlurRegion.qml` + `DynamicIslandWindow.qml` (`BackgroundEffect.blurRegion`):
  real compositor blur through `ext-background-effect-v1`, which Hyprland 0.56 has. The region is inset
  one pixel inside the antialiased outline and its corners are cut row by row (Qt's ellipse region is
  lopsided), re-measured after each animation frame (`Window.afterAnimating`). Better than our
  `ignore_alpha` layer rule, which also blurs under soft shadows. Adopt for the island and the center.
- `IslandRootGestureArea.qml`: horizontal wheel/touchpad swipe on the island flips between capsules
  (time → now playing → custom), with progress following the fingers and a settle after 150 ms idle.
- `DynamicIslandWindow.qml`: one layer per screen holding every layer of the island; the input mask is
  a union of the visible parts; the exclusive zone animates (fast in, slow out) for auto-hide.
- `qml/island/OsdLayer.qml`: volume/brightness as an island state, not a separate HUD.
- `docs/PROJECT_REVIEW.zh-CN.md` (their own audit): set `sourceSize` on every preview (30 MiB saved per
  4K image), never call D-Bus synchronously on the UI thread, sample system stats once and share them
  across screens, build long lists with `ListView` not `Repeater`, stop child processes asynchronously,
  unload panels that are closed. All of these are rules here too.

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

**Chat / agent UI** (the assistant, `docs/superpowers/plans/2026-11-03-assistant-agent-parity.md`)
- AI Elements `packages/elements/src/`: `tool.tsx` (input-streaming → input-available → output),
  `confirmation.tsx` (approval card), `reasoning.tsx`, `chain-of-thought.tsx`, `model-selector.tsx`,
  `prompt-input.tsx`, `context.tsx` (token meter), `queue.tsx`, `task.tsx`, `message.tsx`, `shimmer.tsx`.
- prompt-kit `components/prompt-kit/`: `chat-container.tsx` (stick to bottom), `scroll-button.tsx`,
  `thinking-bar.tsx`, `steps.tsx`, `feedback-bar.tsx`, `tool.tsx`.
- assistant-ui `packages/core/src/react/primitive-hooks/useActionBar{Copy,Edit,Feedback}.ts`.
- T3 Code: `packages/contracts/src/providerRuntime.ts` (event and tool-item names we use),
  `apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.ts`, `apps/server/src/provider/acp/AntigravityChildWork.ts`,
  `apps/web/src/components/chat/` (`TimelineAssistantRows`, `TimelinePendingApprovalRow`, `TimelineToolActivityIcon`,
  `ModelPickerContent`, `ModelListRow`, `ComposerCommandMenu`).
- Codex `codex-rs/tui/src/`: `exec_cell/`, `bottom_pane/approval_overlay.rs`.
- Web only (no clone): kobra.systems, skiper-ui.com, animate-ui.com, shadcn/ui; findings in
  `docs/research/2026-11-03-ui-libraries.md`.

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
- Inline components (`component X: …`) inside files under `components/ai/` fail to load ("X is not a type",
  the whole config fails); they work under `modules/`. Put small shared pieces in their own file.
- Qt 6.12's ES module loader (`import "x.mjs" as X`) rejects object spread `{...a}`; array spread, `?.`, `??`
  are fine. Use `Object.assign`.
- From an agent/tool shell, `bin/rice start` must reach Hyprland's exec (HYPRLAND_INSTANCE_SIGNATURE set),
  or the shell lives in that shell's process group and dies with it.
- With `~/.config/quickshell/shell.qml` present, `qs -c <name>` finds nothing:
  run by path.
