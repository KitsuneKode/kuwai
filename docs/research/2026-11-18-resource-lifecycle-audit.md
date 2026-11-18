# Desktop memory and rendering lifecycle audit

The live and source baseline was `2c82a55`. The fixes below were qualified in a private worktree. The active desktop was observed and was used for a read-only health check.

## What the memory evidence shows

On a prior stable run (`5cf1741`), the same process had 48 samples over about 469 minutes. Anonymous proportional set size (PSS) fell from 936 to 129 MiB and ranged from 104 to 936 MiB. The previous measurement with two wallpaper layers visible on `2c82a55` had a 611 MiB memory median and a 19.3% CPU median over 10 seconds. The audit's read-only health check on `2c82a55` measured 423 MiB with both saver and wallpaper layers mapped. Its CPU median was 32% in the film/saver category. It passed the configured gates, and that category uses a different threshold from idle.

The current logger used cumulative counts for saver starts and panels opened. Earlier counts cannot reconstruct exactly when a surface was visible. New samples add saver visibility, displays-off state and whether the selected wallpaper is hidden, off or eligible. Eligibility can include a per-output pause because a window covers that output.

The isolated one-output comparison used the same synthetic 1440p 4:2:0 clip and Qt/Xvfb/Mesa. It omitted the Wayland layer attachment and kept the real wallpaper QML, player, and loader. Hooks logged player activation and destruction. Each memory reading followed 1.7 seconds at that state.

| State | Baseline anonymous PSS | Candidate anonymous PSS |
|---|---:|---:|
| Playing initially | 429.4 MiB | 423.9 MiB |
| Screensaver covering wallpaper | 429.4 MiB | 334.5 MiB |
| Displays off | 428.9 MiB | 333.7 MiB |
| Locked | 439.1 MiB | 343.3 MiB |

The candidate created and released exactly seven players during an additional seven-cycle run, with a filename that contained both `#` and `?`. Hidden samples started at 356.4 MiB, reached 370.9 MiB, and ended at 366.1 MiB. Those short samples show resource release and some allocator warm-up. Long-running growth and device-side graphics memory require a longer test on the actual compositor.

## Confirmed defects

| Severity and owner | Trigger and user impact | Fix and disproof attempt |
|---|---|---|
| High, `shell/modules/wallpaper/LiveWallpaper.qml` | Lock, DPMS or saver leaves the decoder and its window alive. DPMS and the shared lock state could also miss the pause condition. | Release the loader under those states. Keep the last-frame pause for covered windows and battery policy. Verify the same clip in both versions and confirm each decoder restarts on uncover. The static wallpaper can be visible briefly while the first video frame returns. |
| Medium, `shell/services/Clipboard.qml` | History eviction leaves thumbnail, render, file metadata and request entries reachable. Deleting an entry could briefly show its card again. An old async reply could restore stale metadata after deletion or ID reuse. | Prune caches against active history and pins, check request ownership, immediately remove committed deletes, and release failed requests with retry backoff. Exercise 500 replacements in logic tests and 100 replacements plus asynchronous success and obsolete responses in native Qt. |
| Medium, `shell/modules/clipboard/ClipCard.qml` | A recycled card can show a previous entry's code after a delayed render reply. | Reset the rendered text on key change and reject replies for a previous key. Existing island rendering and accessibility tests still pass. |
| Medium, `shell/modules/screensaver/Screensaver.qml` | Changing the film while the saver is up leaves the original process running. A failed Live film could leave an empty film surface. Lock and displays-off left drawn scene work active. | Reconcile a single film process against the current request after exit. Fall back to Dusk after an unexpected exit. Drop the saver scene while locked or off. Test rapid A→B→C, failure, dismissal, lock and DPMS. |
| Medium, `shell/services/Notifs.qml` | Quickshell replayed a tracked notification after reload without a matching active or snoozed history row. It could remain tracked with no owner. | Release unmatched and duplicate objects and keep the original action-bearing notification for a match. Test all three cases. |
| Medium, `shell/services/WallFx.qml` | Picking a second wallpaper mid-transition leaves the first reveal, timers, and watchdog active. Its fallback can set the older image again. | Cancel the first transition and its timers before applying the new choice. While old queries drain, apply the new choice immediately. Test that the old hand-off never runs. |

## Remaining cases, in priority order

1. Run a longer Wayland soak with the same output geometry, refresh rates and playback state at the start and end of each sample. Track anonymous PSS, GPU memory, frame times and helper counts. Exercise repeated panel opens, lock, DPMS, suspend and monitor removal. The current evidence has no matched hardware stress replay.
2. Profile the drawn screensaver on both high-refresh monitors. The 32% reading is enough to prioritize a trace. Separate animation updates, texture snapshots and Wayland buffer submission. Compare the static scene and capped animation after warm-up.
3. Verify wallpaper hand-off during output removal, scale changes and compositor restart. The audit fixes obsolete timers; equal basenames from different directories and an external wallpaper command already dispatched by the compositor still warrant a native replay.
4. Exercise click-through, focus restoration, rapid pointer reversal, popup anchoring at fractional scale and press cancellation on actual Wayland outputs. The X11 fixture verifies the corresponding Qt actions and geometry.
5. Review disk cache retention separately. The observed thumbnail directory held 127 files and used about 74 MiB. The RAM fix prunes references. Automatic clipboard-history eviction and disk thumbnail garbage collection need their own test and retention policy.
6. Profile album-art cache and screen-copy buffer ownership when track metadata changes quickly or the artist window closes. Ownership inspection identified these as candidates; this audit did not show reproducible growth there.

## Verification

The Python suite passed in two shards (308 tests and five subtests, then 125 agent tests). Focused checks also validated the final memory-log fields. Bun passed 316 tests, including 12 lifecycle cases. Shell tokens and the Lua fixtures passed. The private X11 renderer compiled 143 components and verified the island at 2× text in full and reduced motion. Native probes exercised wallpaper loading and clipboard process completion. The live health check refers to `2c82a55`.

The native probe logs and per-stage samples were saved in `rice-leaks/evidence` in the session scratch directory. Hardware decode, physical Wayland input, mount/unplug cycles and an overnight soak remain outside those fixtures.
