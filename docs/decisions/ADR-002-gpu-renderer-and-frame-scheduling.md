# ADR-002: Hybrid GPU Renderer Selection, Explicit Sync, and Frame Scheduling on Hyprland 0.57

## Status
Accepted

## Date
2026-11-21

## Context
kuwai targets hybrid Intel/NVIDIA laptops driving dual high-refresh displays
(e.g. built-in panel + external 1440p monitor) under Hyprland 0.57 and
Quickshell/Qt6. Several default compositor, driver, and Qt settings caused
measurable frame drops, GPU wake stalls, and memory leaks:

- Invoking `lspci` or `nvidia-smi` during Hyprland config load woke a
  runtime-suspended dGPU, exceeding Hyprland's ~1.5 s startup/reload event-loop
  budget.
- Setting `LIBVA_DRIVER_NAME=nvidia` on an iGPU-composited session broke
  Chromium/Electron hardware video decode (black video).
- NVIDIA's pre-explicit-sync anti-flicker workaround dropped commits arriving
  during an in-flight page flip on 555+ drivers, leaving typed text invisible
  in Electron apps until an unrelated redraw.
- Hyprland's triple buffering (`render.new_render_scheduling = true`) logged
  2,246 `"Cannot commit when a page-flip is awaiting"` drops in 49 hours
  (~46/h), causing Electron/GPU apps to appear frozen until pointer movement.
- Qt's threaded scene-graph render loop (`QSG_RENDER_LOOP=threaded`) leaked
  ~750 B/frame on NVIDIA GL (~2.7 MB/min continuous animation; 70–180 MB/h in
  normal desktop use).
- On Hyprland 0.57, any fullscreen window enabled VRR regardless of the monitor
  setting, causing brightness pulsing/flicker on LCDs under uneven terminal or
  browser frame pacing.

## Decision

1. **Sysfs-only hybrid GPU selection (`hypr/kuwai/gpu.lua`)**:
   - Probe DRM connectors exclusively via cached sysfs — never fork `lspci` or
     `nvidia-smi`.
   - In `auto` mode, pick NVIDIA as primary when a connected screen hangs off
     it (or on AC in the first 120 s after boot, while a docked screen may not
     have answered yet), listing all display-driving
     cards with primary first; otherwise render on the iGPU so NVIDIA sleeps
     until `prime-run`.
   - Set `NVD_BACKEND=direct` (required on 525+ `nvidia-vaapi-driver`), and
     export `LIBVA_DRIVER_NAME=nvidia` only when NVIDIA is the primary
     compositor GPU.
   - Use `cursor.no_hardware_cursors = 2` (auto) and keep pre-explicit-sync
     anti-flicker disabled on 555+ drivers.

2. **Conservative frame scheduling and blur budget (`hypr/kuwai/look.lua`, `hypr/kuwai/system.lua`, `hypr/kuwai/rules.lua`)**:
   - Disable `render.new_render_scheduling` (trade minor late-frame smoothness
     on cross-GPU panel copy for zero dropped/frozen frames).
   - Cap blur at `passes = 3` (with `size = 6`) regardless of theme settings: a
     4th pass on dual 1440p costs ~25% more GPU blur work for negligible visual
     gain. Keep `motion_blur` disabled during window drags.
   - Force `screencopy_force_8b = true` so screenshots, recordings, and screen
     shares remain compatible on 10-bit outputs.
   - Default `no_vrr = true` globally via window rule and re-enable VRR only for
     games and media players; enable `immediate` (tearing) only for games.
   - Set `allow_session_lock_restore = true` and `session_lock_xray = false` so
     a restarted shell can reclaim the lock while unlocked monitors never leak
     session frames.
   - Enforce Hyprland permissions only when the allow-list was loaded at initial
     launch (`#(hl.get_monitors() or {}) == 0`), carrying an env marker across
     reloads so a mid-session config switch never enforces an empty allow-list.

3. **Shell render loop, allocator, and crash-relaunch env (`bin/kuwai-shell`)**:
   - Launch Quickshell with `QSG_RENDER_LOOP=basic` (flat memory vs NVIDIA GL
     threaded leak; ~10 MB smaller baseline than threaded and ~40 MB smaller
     than Vulkan).
   - Set `GLIBC_TUNABLES=glibc.malloc.arena_max=2:glibc.malloc.trim_threshold=8388608`
     so thread arenas release freed panel memory promptly. Pass each assignment
     as a separate argv element (not one space-delimited string, which broke
     `env` parsing and dropped `QSG_RENDER_LOOP`).
   - Export `QS_CONFIG_PATH=$SHELL_DIR` so Quickshell's crash relauncher loads
     kuwai instead of falling back to `~/.config/quickshell`.
   - Start Quickshell via Hyprland (`hl.exec_cmd`), not directly inside a
     terminal's cgroup/process group.

## Alternatives Considered

- **Vulkan backend (`QSG_RHI_BACKEND=vulkan`) for Quickshell**:
  Flat memory on NVIDIA, but added ~40 MB baseline anonymous RSS compared to
  `QSG_RENDER_LOOP=basic` on GL.
- **Keeping `new_render_scheduling = true`**:
  Rejected due to reproducible frozen-frame regressions (~46 page-flip drops
  per hour) on Electron and GPU-accelerated apps.

## Consequences
- Hyprland config reloads stay well inside the 1.5 s budget without waking a
  sleeping dGPU.
- Shell idle RSS stays flat over multi-day uptime instead of drifting 70–180
  MB/h.
- Switching primary GPU (`kuwai gpu`) requires a new login because Hyprland
  picks its renderer once at startup.
