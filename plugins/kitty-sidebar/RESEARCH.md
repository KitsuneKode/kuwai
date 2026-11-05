# Kitty sidebar as a Hyprland window decoration

Research date: 2026-11-05. Status: **feasible API; compiled prototype; no runtime
plugin qualification**. All new work is inside `plugins/kitty-sidebar/`. The shared
rice branch and other sessions' changes were left in place. No push, live plugin
load, enable, reload, Hyprland configuration change, shell restart, or kitty action
was performed.

## Verdict

Hyprland 0.57.1 can attach a real left decoration to kitty, reserve client space,
receive pointer input, draw translucent rounded blurred material, render Pango/Cairo
text textures, and animate in its own scene. This is the more direct architecture
for a sidebar that must remain attached throughout compositor window animations.
It removes an external geometry/event/commit round trip; **zero visual lag has not
been measured or demonstrated here**. Bad geometry, stale textures, damage bugs,
or slow plugin work can still cause visible defects.

The installed package and pkg-config both report **0.57.1**, not exactly 0.57.0.
Headers and binary are commit `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9`.
The binary's `.comment` and the spike compiler both identify GCC 16.2.1.
The official hyprbars snapshot used for comparison is its v0.57.0 tag; the spike
itself was compiled directly against the installed **0.57.1** headers.

## Primary-source evidence

The local paths below are relative to this directory unless absolute. Each upstream
link is pinned, so source line references survive updates.

| Question | Evidence and implication |
|---|---|
| Is the API present? | Installed `/usr/include/hyprland/src/render/decorations/IHyprWindowDecoration.hpp:41-69`: positioning, `draw(ctx, monitor, alpha, presentation)`, input, animation and lifecycle methods. [Pinned header](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/decorations/IHyprWindowDecoration.hpp#L41-L69). |
| Left attachment and reservation? | Installed `DecorationPositioner.hpp:11-40`: sticky policy, LEFT edge, desired extents, `reserved`. `vendor/Hyprland/src/render/decorations/DecorationPositioner.cpp:151-174` accumulates reservation; `:229-237` assigns the left strip. [Positioner](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/decorations/DecorationPositioner.cpp#L151-L237). |
| Does the client actually shrink? | `vendor/Hyprland/src/layout/target/WindowTarget.cpp:231-233` offsets client position by reserved top-left and subtracts both reserved sides from client size. This proves the layout reservation path, rather than drawing over terminal cells. Floating resizing, minimum-size clamping and fullscreen need runtime checks. [Window target](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/layout/target/WindowTarget.cpp#L231-L246). |
| Pointer input? | Installed `IHyprWindowDecoration.hpp:29-32,58` defines input and main-window flags. `vendor/Hyprland/src/desktop/view/window/WindowPresentation.cpp:161-177` hit-tests eligible decorations and calls `onInputOnDeco`. `src/managers/input/InputManager.cpp:863` routes mouse-button events there. This avoids a second layer-shell input surface. [Dispatch](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/desktop/view/window/WindowPresentation.cpp#L161-L177). |
| Blur and rounding? | Installed `/usr/include/hyprland/src/render/pass/RectPassElement.hpp:9-19` exposes colour/alpha, round, blur, blur owner and presentation. `vendor/hyprland-plugins/hyprbars/barDeco.cpp:562-568` renders rounded rectangles with blur. Blur still depends on compositor settings and backend support. [Hyprbars drawing](https://github.com/hyprwm/hyprland-plugins/blob/d2427d4d15b36df40468f5a58bbd67cdba19835d/hyprbars/barDeco.cpp#L562-L568). |
| Text? | Hyprbars `barDeco.cpp:312-343` uses `g_pHyprRenderer->renderText`. On 0.57.1 `vendor/Hyprland/src/render/Renderer.cpp:1696-1742` uses Pango layout, Cairo ARGB32 and `createTexture`; `:1745` also offers an async text-resource overload. No need for the spike to manage raw GL uploads. [Text renderer](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/Renderer.cpp#L1696-L1754). |
| Animation and attachment? | Hyprbars `barDeco.cpp:54-56` creates an animated colour and damages on updates. Core `CHyprGroupBarDecoration.cpp:549-555` combines the assigned box with animated window-edge geometry and render presentation. Installed `render/WindowRenderPresentation.hpp:10-24` carries workspace/floating offsets and alpha. The spike follows that presentation in the same draw traversal. [Core decoration positioning](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/decorations/CHyprGroupBarDecoration.cpp#L545-L555), [hyprbars animation](https://github.com/hyprwm/hyprland-plugins/blob/d2427d4d15b36df40468f5a58bbd67cdba19835d/hyprbars/barDeco.cpp#L54-L56). |
| ABI? | Installed `/usr/include/hyprland/src/plugins/PluginAPI.hpp:8-12` explicitly disclaims C++ ABI compatibility and recommends the same compiler/machine. `:21` is API version 0.2; matching this string alone is insufficient. Hyprbars `main.cpp:158-166` compares host and compiled header hashes. [API warning](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/plugins/PluginAPI.hpp#L8-L21). |

## Feed and action contract

Current authority is `~/Projects/kittymux/docs/inbox.md:55-94`: version 1,
atomically replaced `agents.json`, `kitty_pid`, pane `window_id`, state/title/brand
and an action object. `bin/kittymux:2507-2540` validates `act` arguments again and
handles `jump` using its supplied PID and pane. No invocation was made.

The spike reads only an explicitly provided `KITTYMUX_STATE/agents.json`. A future
production consumer could use the documented default state directory. It polls at
500 ms through a compositor event-loop timer, so idle windows can update; animation
ticks alone stop when idle (`AnimationManager.cpp:345-360`). Reads are bounded at
1 MiB, rows at 128, rendered rows at 12, labels at 256 UTF-8 bytes. Missing,
malformed or incompatible feeds clear the rows. It rejects symlinks and nonregular
files; it ignores unknown fields. The layout receives plain text, not markup.

Rows are matched to `window->backend().pid()`. **This is process-level filtering,
not sufficient top-level-window identity.** One kitty process can own multiple OS
windows. This schema has no OS-window identifier, so such windows would duplicate
rows. Future `tabs.json` needs a stable mapping from kitty PID + OS window + tab +
pane to the compositor's top-level window, plus focus/select actions. No `tabs.json`
schema was found in the referenced inbox document; none is invented here.

For real clicks, hand a validated `action.dump()` to an asynchronous external
helper as one argument: executable `kittymux`, arguments `act`, JSON. Use
`posix_spawnp` or equivalent argv passing, never a shell string. Reap children,
bound work, check stale targets, and preserve explicit PID routing. The prototype
only changes its footer to `Action staged: jump (no execution)`; it runs no command
and changes no focus. Before real action support, test against a fake executable
and a private kitty/socket namespace, including the target-disappeared race.

For production, prefer directory inotify (atomic rename replaces the watched inode)
and a bounded worker/helper delivering immutable snapshots to the compositor loop.
A regular-file read with O_NONBLOCK can still block on storage; Pango shaping and
texture creation also currently happen on the compositor thread.

## Prototype and verification

- `sidebar.cpp`: class `kitty` only; 260 logical-pixel left strip; reserved geometry;
  main-window/input flags; 18 px rounded translucent background with blur requested;
  title, cached Pango/Cairo text textures and agent/state rows; height-limited rows;
  native window/workspace presentation and fade alpha; no-exec click stub.
- It follows inherited compositor motion; it does **not** implement independent
  row transitions, collapse animations, scrolling, tab groups or icon assets.
- Initialization requires `KITTY_SIDEBAR_SPIKE=isolated`, a private-runtime marker,
  explicit KITTYMUX_STATE and matching compositor/header hash. These are accidental
  activation guards, not a security boundary against a hostile loader.
- CMake configures with pkg-config Hyprland 0.57.1; `cmake --build build -j2`
  produces `build/libkitty-sidebar.so` successfully. Plugin entry points are
  exported (`pluginAPIVersion`, `pluginInit`, `pluginExit`).
- CTest: **1/1 passed**. The standalone feed-contract executable checks schema,
  empty snapshots, malformed input, size bounds, PID/action consistency, command
  text rejection in pane IDs, UTF-8 truncation and single-line label sanitization.
  This is data validation, not a decoration/input/render test.
- `isolated-probe.py` starts a new baseline Hyprland inside bubblewrap with private
  HOME/config/state/runtime and no parent display. Host devices, TTYs, session
  buses and runtime sockets are hidden. It never loads a plugin. It exits **134**:
  libseat unavailable, nested Wayland unavailable, then **Cannot open backend:
  no allocator available**. This is a baseline compositor failure, not a plugin
  crash. A first private-environment attempt also failed before loading and exposed
  an overlong Unix-socket path; the namespace probe fixes that using `/mnt/runtime`.
- The reason is visible in pinned source: Hyprland `Compositor.cpp:315-338` adds
  headless, DRM and Wayland backends and notes headless-only work remains;
  Aquamarine `Headless.cpp:133-139` returns -1 for DRM fds; `Backend.cpp:162-180`
  requires a GBM allocator sourced from another backend. Software-Mesa flags alone
  do not provide it. [Hyprland backend setup](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/Compositor.cpp#L315-L345),
  [headless fds](https://github.com/hyprwm/aquamarine/blob/b77d67648336223a6c8fb88844ae316e7b72b574/src/backend/Headless.cpp#L125-L139),
  [allocator requirement](https://github.com/hyprwm/aquamarine/blob/b77d67648336223a6c8fb88844ae316e7b72b574/src/backend/Backend.cpp#L162-L180).
- No standalone nested parent compositor (`weston`, `cage`, `sway`, `labwc`,
  `kwin_wayland`) was found on PATH. No connection to the live Wayland compositor
  was attempted. This establishes that the safe setup available here did not
  render; it does not prove no possible nested setup could ever run on the machine.
- **No plugin load, no grim capture, no PNG, no visual inspection was possible.**
  No running kitty was contacted or started. Blur, corners at the client join,
  pointer hit testing, moving/resizing, scaling, fullscreen, groups, snapshots and
  unload behavior remain unverified. A source/build result must not be called a
  working visual prototype.

See `evidence/build-output.txt`, `evidence/verification.txt` and
`evidence/headless-result.json`. Raw logs and run roots are ignored to avoid
committing machine/session details.

## Upgrade and failure story

The `hyprpm` binary is not installed on this PATH; its matching official source was
inspected. `hyprpm/src/core/PluginManager.cpp:416-487` checks header hash and ABI,
`:561-563` checks out the matching Hyprland revision for headers, and `:1049-1065`
refuses load on a running-version ABI mismatch. `hyprpm/src/main.cpp:140-161`
updates headers/rebuilds plugins and then may ensure load state. Therefore **even
`hyprpm update` is not assumed build-only or safe to run here**; none was run.
[Matching-version checks](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/hyprpm/src/core/PluginManager.cpp#L416-L487),
[update behavior](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/hyprpm/src/main.cpp#L140-L161).

A released plugin needs a hyprpm manifest with build/output metadata and commit pins
for supported Hyprland commits. Treat each compositor/ABI upgrade, including patch
releases and ABI-changing dependency upgrades, as requiring compatible headers,
rebuild and isolated qualification. An on-disk upgrade does not change the already
running compositor: do not load the newly rebuilt object into the older process.
Any future activation/restart requires a separate authorized workflow; none is part
of this spike. Pinned build instructions and hash guards reduce mismatch risk but
cannot catch a renderer bug, use-after-free or blocking call.

The [official plugin wiki](https://wiki.hypr.land/hyprland-plugins/using-plugins/)
explains that plugins execute inside Hyprland. Its
[development guide](https://wiki.hypr.land/hyprland-plugins/development/getting-started/)
describes their access to internal process state. A plugin fault can bring down the
compositor and the entire session; there is no process isolation for the sidebar.

## Comparison and recommendation

| Property | Compositor decoration | Quickshell layer-shell overlay |
|---|---|---|
| Appearance | Real reserved strip; participates in the window scene/shadow. Exact seam, blur and corner behavior still need GPU screenshots. | Rich QML material, text, controls and transitions are easier. A separate surface needs deliberate clipping and stacking. |
| Motion | Uses the compositor's current window/presentation geometry in the same render traversal. No geometry-following IPC path. This is architectural evidence, not a latency measurement. | Geometry delivery, UI evaluation and Wayland buffer commits occur separately. Lag during compositor animation is possible; the other agent's measurement should decide its practical severity. |
| Space | Native reserved decoration shrinks layout client content. | A layer-shell exclusive zone reserves monitor edges, not an individual window side. An external panel needs kitty-owned space or another layout integration to avoid overlap. |
| Robustness | Must handle mapping, grouping, fullscreen, popups, snapshots, input, close/unload and damage correctly inside the compositor. | Failure is usually confined to the UI process; startup/recovery can be handled without crashing Hyprland. |
| Maintenance | Private C++ API/ABI, exact rebuilds, compositor/dependency upgrade tests, C++ lifetime and renderer ownership. | QML/Qt/Quickshell and IPC changes still need maintenance, with a smaller compositor-crash exposure. |
| Accessibility | Textures and hit boxes need separate keyboard and accessibility design. | QML provides controls/focus/accessibility infrastructure, which still needs to be configured and tested. |

Primary sources for the overlay boundary: [Quickshell WlrLayershell](https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/WlrLayershell/)
describes a screen-edge surface. Hyprland `Renderer.cpp:2953-2973` applies its
exclusive area to the monitor's reserved work area, not one client:
[monitor reservation](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/Renderer.cpp#L2953-L2973).
The motion comparison is an architectural inference; this spike does not provide
Quickshell performance measurements.

**Recommend both as a staged strategy:** Quickshell remains the practical shell
implementation and fallback; retain this plugin as isolated R&D for attachment
quality. If measured overlay lag is acceptable, choose Quickshell for daily use.
If exact attachment through all compositor animations is a hard requirement,
prefer the decoration architecture, contingent on an isolated rendered prototype
and accepting its maintenance/crash cost. Do not enable this spike in the live
session on build evidence alone.

Next qualification needs a separate nested parent with render-node-only GPU access
and no physical display/KMS ownership, or a disposable VM/seat. Then capture and
read grim screenshots in dark/light/narrow/scaled states, test actual click/release,
resize/workspace/fullscreen/close/unload, and measure frame alignment. Keep all test
clients, sockets and feeds private and all click executables stubbed until target
routing is proven.
