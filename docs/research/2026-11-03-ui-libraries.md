# UI Component & Motion Library Research for Quickshell AI Assistant

Research survey evaluating web component libraries (`animate-ui`, `kobra.systems`, `shadcn/ui` 2025–2026, `vercel/ai-elements`, `assistant-ui`, `pingdotgg_t3code`, `motion-primitives`, `ibelick/prompt-kit`) for porting into native Qt 6 QML (Hyprland desktop overlay). Design tokens and foundations reference `/home/kitsunekode/Projects/rice/docs/DESIGN.md` and `shell/config/Theme.qml`.

---

## 1. Model / Option Picker (Combobox, Select, Command Menu)

### Ranked Takeaways
1. **Kobra Command Menu** (`https://kobra.systems/r/command-menu.json`):
   - **Dialog entrance:** `250ms cubic-bezier(0.16, 1, 0.3, 1)` (*from source*), transform: `scale(0.96) translateY(-4px) -> scale(1) translateY(0)` (*from source*).
   - **Dialog exit:** `180ms cubic-bezier(0.4, 0, 1, 1)` (*from source*), transform: `scale(1) -> scale(0.97)` (*from source*).
   - **Level shift (drilling into model settings):** `240ms cubic-bezier(0.23, 1, 0.32, 1)` (*from source*), scale dips to `0.99` at 40% before springing back to `1.0`.
   - **Hover/selection indicator:** Single absolute layer transitioning with `transform 150ms cubic-bezier(0.16, 1, 0.3, 1), width 150ms, height 150ms` (*from source*).
   - **Filter algorithm:** Subsequence matching `subsequence(text, query)` + tiered ranking: exact match `0`, prefix match `1`, substring match `2`, subsequence `3` (*from source*).
   - **Capability badge typography:** padding `2px 6.4px` (`0.125rem 0.4rem`), radius `6px` (`0.375rem`), font-size `11px` (`0.6875rem`), weight 500 (*from source*).
2. **Animate UI Combobox & Select** (`animate-ui/packages/react/src/primitives/base-ui/combobox`, `select/motion.tsx`):
   - **Menu entrance:** `MENU_TRANSITION = { duration: 0.22, ease: [0.215, 0.61, 0.355, 1] }` (ease.soft) (*from source*).
   - **Scale & origin:** Initial scale `0.9 -> 1.0` (*from source*), transforms anchored to trigger edge (`transformOrigin: 'var(--transform-origin)'`).
   - **Stagger:** Cascading option reveal with `stagger.stack = 30ms` (`0.03s`) (*from source*).
   - **Item highlight glide:** `HIGHLIGHT_TRANSITION = { type: 'spring', stiffness: 500, damping: 40 }` (*from source*). Transfers position, dimensions, and exit velocity between sibling rows.
   - **Selection hold:** Delay popup unmount by `200ms` (`usePickHold`) so checkmark animation resolves before menu teardown (*from source*).
3. **T3 Code Model Picker** (`pingdotgg_t3code/apps/web/src/components/chat/ModelListRow.tsx`, `ModelPickerContent.tsx`):
   - **Row layout:** 32px height row (*observed/estimated*), provider glyph + model name + parameter/version tag + capability badge + numeric jump key (`Kbd` ⌘1–⌘9) + favorite star on hover (*from source*).
   - **Background lock:** Sets `overscrollBehavior = 'contain'` on root and suppresses wheel events outside picker (*from source*).
4. **Vercel AI Elements Model Selector** (`vercel_ai-elements/packages/elements/src/model-selector.tsx`):
   - **Logo clustering:** Provider icons loaded from `models.dev/logos/${provider}.svg`, `size: 12px` (`size-3`), overlapping `-space-x-1` with 1px border ring (*from source*).

### Recommendation for our QML Version
- Wrap `ModelPickerMenu.qml` in an anchored card using `Theme.springModerate` (stiffness 3329, damping 115) with scale `0.96 -> 1.0` and 6px downward drop.
- Route row hover/focus through a single `FluidHighlight.qml` cursor powered by `Theme.springFast` (stiffness 13300, damping 231) for zero-latency 150ms glides.
- Format capability tags with Apple 11px SF Pro Text (`Theme.tracking(11)`), 6px radius, and semantic colors (`Theme.blue` Reasoning, `Theme.green` Vision, `Theme.orange` General).

---

## 2. Prompt Input / Composer

### Ranked Takeaways
1. **Vercel AI Elements PromptInput & Shadcn InputGroup** (`vercel_ai-elements/packages/elements/src/prompt-input.tsx`, `shadcn/ui/input-group.tsx`):
   - **Container architecture:** Composable `InputGroup` shell with `InputGroupTextarea`, `InputGroupAddon`, and footer action bar (*from source*).
   - **Flush button alignment:** Addons use negative margins (`-0.45rem` left, `-0.4rem` right) to keep icons flush with outer container padding (*from source*).
   - **Send/Stop morph state:** Submits with `CornerDownLeftIcon` (16px), swaps to `Spinner` (16px animate-spin) on submit, `SquareIcon` (16px filled) during streaming, and `XIcon` on error (*from source*).
   - **State-aware click handler:** Single button calls `onStop()` when `status === 'streaming'` and submits when idle (*from source*).
2. **Ibelick Prompt-Kit PromptInput** (`ibelick_prompt-kit/components/prompt-kit/prompt-input.tsx`):
   - **Auto-grow geometry:** Base minimum height `44px` (`min-h-[44px]`), maximum height ceiling `240px` (`maxHeight: 240`), recalculating via `Math.min(el.scrollHeight, maxHeight)` (*from source*).
   - **Container shape:** Corner radius `24px` (`rounded-3xl`), outer padding `8px` (`p-2`), 1px neutral border (*from source*).
   - **Keyboard handling:** Plain `Enter` submits; `Shift + Enter` allows newline without sending (*from source*).
3. **Animate UI Reflow & Chips** (`animate-ui/packages/react/src/internal/reflow.ts`, `combobox.tsx`):
   - **Attachment chip entrance:** `opacity: [0, 1]`, `scale: [0.85, 1]`, with spring `CHIP_TRANSITION` (*from source*).
   - **Sibling reflow glide:** Siblings slide into new slots using `REFLOW_TRANSITION` (`spring.reflow`: stiffness 500, damping 40) rather than abruptly snapping (*from source*).
4. **T3 Code Composer Command Menu** (`pingdotgg_t3code/apps/web/src/components/chat/ComposerCommandMenu.tsx`):
   - **Slash command trigger:** `/` at character index 0 opens floating command palette; `@` opens file/symbol search (*from source*).
   - **Row presentation:** Icon (16px) + command name + muted description + shortcut badge (*from source*).

### Recommendation for our QML Version
- Structure `PromptInput.qml` with `radius: 18`, dark liquid glass tint (`Theme.glassTint`), and auto-grow height capped at 160px (5 lines) before enabling internal scrolling.
- Animate height expansion using `Theme.reflowMs` (200ms) with `Theme.easeOut` curve `[0.23, 1, 0.32, 1]`.
- Implement send/stop action as an icon crossfade with a `0.92 -> 1.0` scale pulse on `Theme.springFast`, triggering stop on active stream and submit on idle.

---

## 3. Tool Call Row / Approval Card / Command Output Block

### Ranked Takeaways
1. **Vercel AI Elements Tool & Confirmation** (`vercel_ai-elements/packages/elements/src/tool.tsx`, `confirmation.tsx`):
   - **Tool call header:** 36px height, `p-3`, 14px font-medium title, 16px wrench icon, status badge rounded-full `text-xs` (*from source*).
   - **Lifecycle status states:**
     - `input-streaming`: CircleIcon (16px) + "Pending" (*from source*).
     - `input-available`: ClockIcon (16px animate-pulse) + "Running" (*from source*).
     - `output-available`: CheckCircleIcon (16px, green-600) + "Completed" (*from source*).
     - `output-denied`: XCircleIcon (16px, orange-600) + "Denied" (*from source*).
     - `output-error`: XCircleIcon (16px, red-600) + "Error" (*from source*).
   - **Disclosure animation:** Content enters with `data-[state=open]:slide-in-from-top-2` (8px translateY) and fade-in (*from source*).
   - **Confirmation approval card:** Inline `Alert` card, action buttons `h-8 px-3 text-sm` (32px height), right-aligned with 8px gap (`gap-2`) (*from source*).
   - **Approval transition:** When user accepts/rejects, confirmation buttons morph immediately into an inline badge receipt without shifting layout height (*from source*).
2. **Vercel AI Elements Terminal** (`vercel_ai-elements/packages/elements/src/terminal.tsx`):
   - **Window frame:** `bg-zinc-950 text-zinc-100 rounded-lg border`, header `36px` (`px-4 py-2`), border bottom `border-zinc-800` (*from source*).
   - **Terminal typography:** `font-mono text-sm leading-relaxed`, max height `384px` (`max-h-96`) with scroll pinning to `scrollHeight` (*from source*).
   - **Streaming cursor:** `inline-block h-4 w-2 animate-pulse bg-zinc-100 ml-0.5` (*from source*).
   - **Action buttons:** 28px ghost buttons (`size-7`), icon 14px, copy success feedback timeout `2000ms` (*from source*).
3. **T3 Code Shell Command Block** (`pingdotgg_t3code/apps/web/src/components/chat/ShellCommandBlock.tsx`, `CommandOutputPanel.tsx`):
   - **Lexer stability:** Pre-splits raw command into whitespace/word spans before grammar highlights load to guarantee zero layout reflow (*from source*).

### Recommendation for our QML Version
- Build `Tool.qml` on `Theme.glassTintElevated` with 10px radius, 1px specular rim, and 36px header disclosure toggled via `Theme.springModerate`.
- Render Confirmation approvals with a 1px `Theme.orange` tint border, auto-focusing "Approve" (bound to `Return`), and Deny on `Escape`.
- Format terminal blocks with SF Mono 12px, tabular figures, 240px max-height scroll viewport, and a 800ms sine pulsing cursor block.

---

## 4. Reasoning / Thinking Indicator

### Ranked Takeaways
1. **Vercel AI Elements Reasoning** (`vercel_ai-elements/packages/elements/src/reasoning.tsx`, `shimmer.tsx`):
   - **Auto-expand on start:** Automatically expands disclosure container when `isStreaming` becomes true (*from source*).
   - **Auto-close delay:** Automatically collapses 1000ms (`AUTO_CLOSE_DELAY = 1000`) after streaming concludes, leaving a compact summary chip (*from source*).
   - **Duration counter:** Computes elapsed time in whole seconds: `Math.ceil((Date.now() - startTime) / 1000)` (*from source*).
   - **Active vs resting copy:** "Thinking..." with animated shimmer while active; "Thought for 6 seconds" when resolved (*from source*).
   - **Shimmer sweep mathematics:** Background size `250% 100%`, animated from `backgroundPosition: 100% center -> 0% center`, duration `1.0s` or `2.0s` linear infinite, gradient mask: `linear-gradient(90deg, #0000 calc(50% - spread), var(--color-background), #0000 calc(50% + spread))` (*from source*).
2. **Ibelick Prompt-Kit Text Shimmer** (`ibelick_prompt-kit/components/prompt-kit/text-shimmer.tsx`):
   - **Pure CSS linear gradient:** `linear-gradient(to right, var(--muted-foreground) 30%, var(--foreground) 50%, var(--muted-foreground) 70%)` with background size `200% auto`, duration `4s` linear infinite (*from source*).
3. **Animate UI Shimmering Text** (`animate-ui/packages/react/src/primitives/texts/shimmering`):
   - **Beam profile:** 40px gradient band, 2.5s duration, supports easeInOut sweep across typography without clipping descenders (*from source*).

### Recommendation for our QML Version
- Implement `ReasoningBlock.qml` with automatic expansion on stream start and a 1000ms collapse timer upon completion.
- Render the shimmer in QML via a custom fragment shader or horizontal linear gradient animation sweeping `0.50 -> 0.96` alpha in 1.4s linear cycles.
- Collapse into a 28px pill displaying "Thought for Xs" with chevron rotated to 0°, expanding on click with `Theme.springModerate`.

---

## 5. Message List & Streaming Reveal

### Ranked Takeaways
1. **Ibelick Prompt-Kit Response Stream** (`ibelick_prompt-kit/components/prompt-kit/response-stream.tsx`):
   - **Word-by-word streaming reveal:** Uses `Intl.Segmenter` (granularity `"word"`) to partition incoming text stream into lexical tokens (*from source*).
   - **Staggered word fade:** CSS keyframe `@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }` with duration `1000 / sqrt(speed)` ms (~223ms at default speed 20) and segment delay `100 / sqrt(speed)` ms (~22ms) (*from source*).
2. **Ibelick Prompt-Kit Scroll Button** (`ibelick_prompt-kit/components/prompt-kit/scroll-button.tsx`):
   - **Geometry & motion:** `40px` circular pill (`h-10 w-10 rounded-full`), 20px chevron (`h-5 w-5`), transitions with `duration-150 ease-out` (*from source*).
   - **Enter / exit transform:** Visible at `translate-y-0 scale-100 opacity-100`; hidden at `translate-y-4 scale-95 opacity-0` (4px drop, 95% scale, 0 opacity) (*from source*).
3. **Assistant-UI Action Bar** (`assistant-ui_assistant-ui/packages/react/src/primitives/actionBar/ActionBarRoot.tsx`):
   - **Visibility gating:** `autohide: "not-last" | "always" | "never"` (*from source*).
   - **Stream suppression (`hideWhenRunning`):** Action bar automatically stays hidden while assistant is actively generating (*from source*).
   - **Interaction lock:** `acquireInteractionLock` keeps the bar locked visible if an action menu, tooltip, or dropdown is open (*from source*).
4. **Animate UI Message Reveal** (`animate-ui/packages/react/src/utils/motion/index.tsx`):
   - **Card entrance:** `reveal: { duration: 0.3, ease: [0.23, 1, 0.32, 1] }` (*from source*), starting from `y: 8px, opacity: 0`.

### Recommendation for our QML Version
- Animate message arrivals with `Theme.enterMs` (200ms) easeOut, 6px translateY drop, and opacity fade.
- In QML, bypass per-word DOM animations (which thrash FreeType glyph caches) in favor of chunked stream updates paired with a 14px blinking accent cursor.
- Float the action bar at bottom-right of assistant turns on hover (28px height, 1px rim, 140ms easeOut fade), suppressing it during `isStreaming`.

---

## 6. Toggles, Segmented Controls, Tabs

### Ranked Takeaways
1. **Animate UI Physical Switch Thumb** (`animate-ui/packages/react/src/internal/controls/thumb.ts`, `switch/switch.tsx`):
   - **Apple physical stretch ratio:** `PRESSED_STRETCH = 19 / 16` (= 1.1875, or 18.75% horizontal expansion while pressed!) (*from source*).
   - **Spring parameters:** `THUMB_TRANSITION = { type: 'spring', stiffness: 300, damping: 25, restDelta: 0.005, restSpeed: 0.01 }` (*from source*).
   - **Lean / anchor dynamics:** While held down, thumb stretches toward the destination side while anchored at its trailing edge (`m.lean = atEnd ? rest.anchor - 1 : rest.anchor`) (*from source*).
   - **Release snap:** On pointer release, width snaps back from `natural * 1.1875` to `natural` as the position springs across the track (*from source*).
2. **Animate UI Sliding Indicator** (`animate-ui/packages/react/src/internal/sliding-indicator.tsx`):
   - **Pill spring:** `INDICATOR_TRANSITION = { type: 'spring', stiffness: 300, damping: 35, restDelta: 0.01 }` (*from source*).
   - **Reduced motion fallback:** When reduced motion is active, sliding transforms are replaced by a 200ms opacity crossfade between cloned span layers (*from source*).
3. **Animate UI Tabs & Panel Transitions** (`animate-ui/packages/react/src/internal/tabs.tsx`):
   - **Panel in curve:** `panelIn = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] }` (*from source*).
   - **Panel out curve:** `panelOut = { duration: 0.15, ease: [0, 0, 0.58, 1] }` (*from source*).
   - **Panel height morph:** `panelHeight = { duration: 0.45, ease: [0.4, 0, 0.1, 1] }` (*from source*), following active panel size with `spring.morph` (stiffness 660, damping 52).
   - **Directional slide:** Sliding left or right determines enter/exit horizontal translation (`shift.tabs = 12px`) (*from source*).

### Recommendation for our QML Version
- Fix the existing switch: set track to 38x22px, thumb to 18px circle. On `pressed`, stretch thumb width to 21.4px (`19/16` stretch) oriented toward target toggle state.
- On release, execute `Theme.springModerate` (stiffness 3329, damping 115) to translate x position and return width to 18px.
- Segmented tabs: drive active pill selection through a shared background rectangle with `Behavior on x` and `Behavior on width` set to `SpringAnimation { spring: 300; damping: 35 }`.

---

## 7. Popover / Dialog / Sheet Open-Close & Magnetic Effects

### Ranked Takeaways
1. **Animate UI Modal & Sheet Motion** (`animate-ui/packages/react/src/internal/modal-motion.ts`, `anchored.tsx`):
   - **Popover spring:** `POPOVER_TRANSITION = { type: 'spring', stiffness: 400, damping: 29 }` (*from source*), scale `0.8 -> 1.0`.
   - **Dialog spring:** `DIALOG_TRANSITION = { type: 'spring', stiffness: 150, damping: 25 }` (*from source*), scale `0.8 -> 1.0`, blur `4px -> 0px`.
   - **Dismiss curve (asymmetric exit):** `DISMISS_TRANSITION = { duration: 0.2, ease: [0.33, 0.17, 0.67, 0.5] }` (ease.away) (*from source*). Exits never use entering springs.
   - **Sheet / Drawer curve:** `SHEET_TRANSITION = { duration: 0.4, ease: [0.215, 0.61, 0.355, 1] }` (ease.soft) (*from source*); exit `160ms cubic-bezier(0.4, 0, 1, 1)` (ease.in).
   - **Warm Tooltip Window:** `WARM_WINDOW = 300ms` (*from source*). If a tooltip opens within 300ms of another closing, all enter animations are skipped (`appearAtOnce`).
2. **Animate UI Magnetic Effect** (`animate-ui/packages/react/src/primitives/effects/magnetic/index.tsx`):
   - **Spring options:** `DEFAULT_SPRING_OPTIONS = { stiffness: 100, damping: 10, mass: 0.5 }` (*from source*).
   - **Attraction radius & strength:** `range = 120px`, `strength = 0.5` (*from source*).
   - **Formula:** `dist = Math.hypot(dx, dy); factor = (1 - dist / range) * strength; targetX = dx * factor; targetY = dy * factor` (*from source*). Resets to 0 when `dist > range` or cursor leaves.
3. **Motion Primitives Morphing Popover** (`refs/motion-primitives/morphing-popover.tsx`):
   - **Shared Layout Morph:** `TRANSITION = { type: 'spring', bounce: 0.1, duration: 0.4 }` (*from source*). Trigger pill boundaries expand directly into popover card.

### Recommendation for our QML Version
- Open popovers with `Theme.springModerate` (stiffness 3329, damping 115) from `0.95` scale and 6px Y offset; dismiss with 120ms easeOut tween.
- Sheets / sidebars: 240ms iOS sheet curve `Theme.easeDrawer` (`[0.32, 0.72, 0, 1]`), exiting with 160ms easeOut.
- Apply magnetic attraction strictly to small icon buttons (close, copy, mic) capped at ±3px travel with `Theme.springFast`.

---

## 8. Icon Animations (Animate UI & Kobra)

### Ranked Takeaways
1. **Animate UI Icon Swap & Copy/Check** (`animate-ui/packages/react/src/primitives/buttons/_icon-swap.tsx`, `copy/index.tsx`, `check/index.tsx`):
   - **Icon swap transition:** `SWAP_TRANSITION = { duration: 0.15, ease: [0.23, 1, 0.32, 1] }` (ease.out) (*from source*).
   - **Icon morph geometry:** Outgoing icon exits to `scale: 0.5, blur(2px), opacity: 0`; incoming enters from `scale: 0.5, blur(2px), opacity: 0` to `scale: 1.0, blur(0px), opacity: 1` (*from source*).
   - **Check stroke draw:** `pathLength: [0, 1]`, `scale: [1, 1.1, 1]`, duration `0.6s`, `ease: 'easeInOut'` (*from source*).
2. **Kobra CopyCheck Glyph** (`https://kobra.systems/r/copy-check.json`):
   - **Receipt hold:** `COPIED_HOLD = 1500ms` (1.5 seconds) (*from source*).
   - **Spring morph:** `{ type: 'spring', duration: 0.34, bounce: 0, delay: copied ? 0 : 0.07 }` (*from source*).
   - **Path draw:** `duration: 0.22s, delay: 0.13s, ease: [0.22, 1, 0.36, 1]` (*from source*).
3. **Animate UI Chevron Down** (`animate-ui/apps/v2/registry/icons/chevron-down/index.tsx`):
   - **Nudge:** `y: [0, 4, 0]`, duration `0.3s`, `ease: 'easeInOut'` (*from source*).
   - **Accordion flip:** Rotation `0 -> 180deg` with `duration: 0.2s, ease: [0.23, 1, 0.32, 1]` (*from source*).
4. **Animate UI Send & Send-Horizontal** (`animate-ui/apps/v2/registry/icons/send/index.tsx`, `send-horizontal/index.tsx`):
   - **Launch flight path:** Scale `[1, 0.8, 1, 1, 1]`, X translation `[0, '-10%', '100%', '-125%', 0]`, Y translation `[0, '10%', '-100%', '125%', 0]`, duration `1.2s`, keyframe times `[0, 0.25, 0.5, 0.5, 1]` (*from source*).

### Recommendation for our QML Version
- Copy/Check button: On copy, swap glyph via 150ms scale-down (0.6) + fade, hold checkmark for 1500ms (`COPIED_HOLD`), then reverse.
- Chevrons: Rotate 180° using `NumberAnimation { duration: 180; easing: Theme.easeOut }` without vertical wobble.
- Send button: Reject the 1.2s paperplane loop. Use a crisp 140ms forward nudge (`x: +2px`, scale `0.97`) on press, cleanly morphing to a filled stop square during generation.

---

## 9. Do Not Copy (Gimmicks and AI Slop)

1. **Rainbow Gradient Border Glows & Conic Rotations** (Aceternity / Magic UI style):
   - *Why:* Degrades native dark liquid glass by overwhelming the delicate 1px specular rim and 46% tint transparency. Reads immediately as a synthetic AI template.
2. **Heavy Multi-Pass Gaussian Blurs (>30px)**:
   - *Why:* Wayland compositor (Hyprland `blur` layer) pays heavy GPU fragment shader costs for wide radii. Stacking multiple blurred cards drops frames and muddies SF Pro typography.
3. **Bouncy / Oscillating Exits**:
   - *Why:* Reversing entrance springs on close causes dialogs and menus to wobble as they vanish. Exits must ALWAYS be rapid, critically-damped tweens under 160ms (`Theme.exitMs: 150`).
4. **Continuous Idle Loops & Pulsing Buttons**:
   - *Why:* Infinite pulsing or breathing on idle buttons drains battery and creates visual noise. As codified in `DESIGN.md`: "Arrivals that matter get one cue, never a loop."
5. **1.2-Second Paperplane Icon Stunts**:
   - *Why:* Icon animations that fly off screen and loop back over 1.2s delay feedback. Desktop utility actions require instantaneous confirmation under 150ms.
6. **Per-Word DOM Layout Reflow During Streaming**:
   - *Why:* Word-by-word opacity transitions re-trigger layout geometry and font rasterization dozens of times a second. Text streaming in desktop overlays must append stably with a blinking cursor.
