# Desktop helpers and island reliability audit

Date: 2026-11-18. Initial candidate base: `5cc9bc0`, including the owner's
existing uncommitted theme/screensaver work. The checkout advanced during
the audit; the candidate was merged onto `7e55306`, then updated through
`5cf1741`, preserving its
accessibility, translation, data-path and screensaver changes. Running
stable was initially `6887a91` and independently advanced during the audit.
Source changes, isolated qualification, and live qualification are separate.

## Scope and preservation

Inventoried 71 files under bin/lib/greeter/system (38 shell and 22 Python
shebangs, plus other helper/support files). Ran the existing Python, Bun,
Lua and token checks, and shell static analysis. Deep review concentrated
on backup/restore, recording, screenshot publication, wallpaper encoding,
Lua argument boundaries, terminal launch, and the complete split-capsule
layout/action/proximity flow. This is a bounded audit, not proof that every
script and every possible desktop state is bug-free.

Work was developed in `.worktrees/reliability-20261118`, then requalified in
`.worktrees/reliability-20261118-current` after concurrent updates. The initial dirty
patch and a file-hash manifest were saved in the session scratch directory.
Only owned files are transferred, with concurrent-edit checks. Existing
theme, screensaver, migration and wallpaper-map edits are not part of this
audit's patch. No commit, stable promotion or input/focus manipulation is
implicit in a passing source test.

## Reproduced findings and fixes

Severity describes the impact before these fixes. Each row identifies the
trigger, impact, root cause, fix and an attempted disproof/regression case.
Paths refer to the resulting source; tests preserve the reproductions.

| Severity / location | Trigger and impact | Cause and resulting behavior | Regression evidence |
|---|---|---|---|
| High — `bin/kuwai-backup`, `validate_archive` | A restore archive contains links, traversal or an unrelated home file such as `.ssh/authorized_keys`; extraction can cross the advertised backup boundary | Validate regular files/directories, configured roots, excluded searxng data and destination boundaries before extraction or pre-backup | Malformed tar archives are rejected before changing settings or taking/pruning a backup; valid restore still succeeds |
| High — `bin/kuwai-backup`, `snap` / `restore` | Two snapshots within a second, or restore with retention=1, can lose the selected version | Serialize operations, use unique names and private archive publication; copy the selected archive before retention runs | Same-second snapshots preserve distinct contents; retention=1 restores the selected old contents |
| Medium — `bin/kuwai-backup`, `paths` / `newest` | First automatic snapshot or missing optional final path fails | Empty history and absent optional paths now return normally; fingerprints exclude ignored backup/container files; listing is NUL-delimited | First auto backup, missing optional files, unchanged files, spaces, bad retention and unsupported external roots |
| High — `bin/kuwai-rec`, `running` / `stop` | A stale PID points to an unrelated live process; stopping could signal it | Check PID and Linux process birth time, reject zombies, serialize commands and retain a recorder that is still stopping | Unrelated live process survives; simultaneous starts create one child; a crashed recorder clears without a saved-success claim |
| Medium — `bin/kuwai-rec` and `shell/services/Clipboard.qml` | Paths contain spaces, metadata is malformed, thumbnail generation stalls, or state publication fails | Tab-separated records with legacy-reader fallback, bounded thumbnail work, validated display times, active-only liveness checks; failed publication stops the newly launched child | Full recording path round-trips, invalid/future/expired timestamps stay out of UI, publication failure terminates the fixture recorder |
| Medium — `bin/kuwai-shot`, output allocation | Concurrent captures in the same second overwrite one another | Reserve a unique private filename, remove cancelled empty outputs and clean up an owned freezer on interruption | Concurrent captures preserve both payloads; cancellation leaves no empty PNG |
| Medium — `bin/kuwai-wall`, `add` / `next_number` | A zero-padded sequence hits shell octal parsing, encoder fails after advertising NVENC, or a failed encode leaves a library entry | Decimal sequence parsing, import lock, private MP4 encode, software fallback and atomic publication | Padded names, empty/non-ASCII slug, encoder failure/fallback and parallel import cases |
| High — `lib/dispatch.sh`, `_dsp_lua_string` | A dynamic workspace, command, monitor or key contains Lua delimiters | Escape values as Lua strings and validate numeric coordinates before dispatch | Actual Lua evaluates round-trips for quotes, slashes, multiline text, Unicode and injection-shaped input; classic argument behavior retained |
| Medium — `bin/kuwai-term` | Kitty/Ghostty are installed but prime-run is absent | GPU wrapper is optional; launch the chosen terminal directly when unavailable | Kitty, Ghostty and Foot fake-executable launch cases |
| Medium — `shell/modules/island/IslandSplit.qml`, Pill `shown` / `spaceFor` | A live warning remains invisible; simultaneous pills exceed a narrow host | Visibility previously depended on hidden descendant geometry; use activity demand independently, budget each side, show a compact identity when detail will not fit, clamp spring allocation | Real Qt fixtures previously showed wants=true/shown=false; now four concurrent activities stay within 320/480/1120 logical-pixel hosts |
| Medium — `IslandSplit.qml`, Pill handlers / `AgentStack.qml` | Padding does nothing; nested primary actions can toggle the panel closed; tiny targets are hard to acquire | Full-body primary action, idempotent opens, tested vertical slop, named keyboard/accessibility actions, disabled hidden handlers; nested Usage action preserved | Qt clicks on body padding, vertical slop and nested limit badge; Return activation; folded/returned state checks |
| Medium — `shell/components/RestMark.qml` | At 2x text size a count overlaps its ring and adjacent T3 text | Size the ring using measured text, repaint arcs on size changes and respect reduced motion; capsule height uses font metrics | Native assertion fails on the old ring dimensions and passes at text scales 1/1.2/2 |
| Medium — `IslandBar.qml`, proximity and mask | Auto mode expands, stops tracking and misses an exit; hidden/fullscreen/locked surfaces retain work or input geometry | Keep tracking while near, gate availability, balance subscriptions idempotently, cancel obsolete dwell/intent work and gate mask regions on visibility/enabled state | Production-expression/function tests cover hidden/fullscreen states, exit tracking and repeated subscription transitions; Wayland mask behavior remains a live qualification gate |
| Medium — `shell/services/Pointer.qml` | Rotated monitor width is wrong, coordinates are malformed, or sample time repeats/moves backward | Use rotated logical width, accept only finite numeric coordinates, reset velocity across invalid time intervals and publish the complete sample before notifying consumers | Rotated-monitor, nonfinite-coordinate, duplicate-time and clock-rollback cases |
| Verification — `bin/kuwai-ui-test` | Offscreen cannot compile PanelWindow adapters and software rendering omits shader content | Add a private Xvfb/Mesa backend, isolated HOME/runtime/DBus/network, actual component compilation and explicit qualification scope; retain the offscreen fixture with its documented adapters | Namespace isolation probe, 142 actual component compilations, native settings checks and X11 capsule rendering/input |

The dispatcher's `action='on'` was investigated and is supported; it was not
changed. A blank music cover in the offscreen software capture was checked
against private X11/Mesa: the production fallback renders there. That image
was not treated as evidence of a production album-art bug.

## Design decision

Keep the top-center island and its existing panels. Assign stable sides,
budget the available width on each side and retain a recognizable activity
identity when detailed content does not fit. Primary clicks open the same
panel from a detailed or compact capsule. Secondary badge actions keep
their existing meaning. Do not shrink text to hide overflow.

| Layout option | Assessment |
|---|---|
| Unbounded natural widths | Rejected: detailed content can leave the host and move targets unpredictably |
| Side budgets with compact identities | Selected: preserves simultaneous status, stable placement and existing actions |
| `+N` for activities without a full target | Selected for dense layouts. It uses the island’s panel and Back navigation. |

Five 40px targets, a 112px notch and their gaps exceed a 320px host. The
layout reserves a slot for `+N` and gives direct slots to system warnings,
agent errors and agents or threads waiting for input first. When there is
no side slot, the `+N` control sits below the notch. The panel keeps the
selected activity list as the notch expands, and its rows use the existing
panel and window restore actions. A departing pill yields its slot when a
new activity needs the room. The 40px target applies when the host can
accommodate it.

Tooltips wrap and elide after six lines. They release their popup when their
text clears and avoid movement under reduced motion. Full labels stay on
the associated controls. A capsule interrupted during a drag springs home
without opening a panel.

## References and comparative ratings

These are subjective fit ratings for this owner's Hyprland + T3 + kittymux
workflow, not measured speed, security or overall quality scores for other
projects. No competing desktop was installed or benchmarked.

| Option | Workflow fit / 10 | What to learn / adoption cost |
|---|---:|---|
| Owned kuwai island with bounded capsules | 9.0 | Best fit for the existing agent workflows; the owner also carries the verification/maintenance cost |
| [Waybar](https://github.com/alexays/waybar) | 8.0 | Useful conventional bar/custom-module reference and fallback; an island/panel experience needs additional components |
| [Caelestia](https://github.com/caelestia-dots/shell) | 8.0 | Coherent morphing Quickshell reference; replacing the whole shell requires porting this setup's integrations |
| [Dux Shell](https://github.com/duxlabs-dev/dux-shell) | 8.0 | Complete Quickshell/Go desktop reference with broad compositor integrations; a complete-stack migration is larger than fixing the owned flow |
| [Original Tide Island](https://github.com/enhaoswen/Tide-island) | 6.0 | Relevant island interaction reference; its README says the old version is no longer actively maintained and the successor is unfinished |

Current primary project pages were checked on the audit date. The old
DankMaterialShell repository currently redirects to Dux Shell; do not treat
the old name or a local clone directory as current product metadata.
[Qt's HoverHandler documentation](https://doc.qt.io/qt-6/qml-qtquick-hoverhandler.html)
also explains why disabling only a visual parent is insufficient for hover:
the handler's own enabled state must be considered.

## Quality status and remaining live checks

The initial audit rated the revised source at 7.5/10. The density, tooltip
and drag work raises the provisional assessment to about **8/10**. Real
Wayland input, assistive technology and hardware performance remain open
parts of the 9.5/10 target.

| Area | Evidence and remaining work |
|---|---|
| Correctness and recovery | Helper regressions cover real failure paths with isolated state and processes. Disk-full recovery and real recorder/encoder operation still need hardware checks. |
| Pointer, keyboard and focus | Native Qt checks cover wide and compact pills, button padding, drag release and cancellation, keyboard activation and Back. Physical approach, pass-through, rapid re-entry and focus restoration need tests on both monitors. |
| Layout and readability | Five activities fit through direct access or overflow at 200/320/480/1120 logical pixels. Long tooltips wrap at up to 2× text. Mixed-scale and rotated outputs still need live captures. |
| Performance and lifecycle | Measure actual idle CPU below 5%, wallpaper playback, frame pacing and resource recovery after suspend and display changes. |
| Semantics and accessibility | Native named actions and focus checks pass. Screen-reader use and Wayland keyboard reachability still need checking. |

### Wallpaper measurements

An earlier live sample recorded 909 MiB anonymous PSS. The source history
reports 910–935 MiB with two Qt players and a 1440p 4:2:0 loop. A later
stable health check recorded 123 MiB with the screensaver mapped. Those
observations represent different desktop states.

The follow-up played a synthetic 1440p H.264 4:2:0 loop in two 640×720
views in a private X11 session with Mesa software rendering. The figures
are medians of three one-second samples. CPU uses 100% for one logical core.

| State | Anonymous PSS | CPU |
|---|---:|---:|
| Qt before loading the loop | 116 MiB | 0% |
| Qt playing two views | 614 MiB | 119% |
| Qt paused | 597 MiB | 0% |
| Qt after unloading the loop | 394 MiB | 0% |
| Two standalone mpv processes playing | 718 MiB | 1199% |

Pausing stopped decoder work but released little memory in this fixture.
The standalone mpv software run dropped frames, and mpvpaper was absent
from the host. A useful backend decision needs an A/B run with hardware
decode on the same outputs, counting both shell and player memory. The
follow-up kept the existing live wallpaper backend.

## Verification and reproducibility

Run from the candidate worktree or the integrated source checkout:

```sh
python -m pytest -q -p no:cacheprovider tests
bun test
for t in tests/hypr/test_*.lua; do lua "$t"; done
shellcheck bin/kuwai-backup bin/kuwai-rec bin/kuwai-wall bin/kuwai-shot bin/kuwai-term lib/dispatch.sh
bin/kuwai-tokens --check
bin/kuwai-ui-test --backend x11 --self-test-isolation --output /tmp/kuwai-isolation
bin/kuwai-ui-test --backend x11 --compile-components --output /tmp/kuwai-components
bin/kuwai-ui-test --case settings-store --backend x11 --output /tmp/kuwai-settings
bin/kuwai-ui-test --case island --backend x11 --motion full --text-scale 2 --output /tmp/kuwai-island
```

The capsule fixture checks 200/320/480/1120 logical-pixel widths, text scales
1/1.2/2, body and nested clicks, Return, overflow navigation, drag release
and cancellation, long tooltips and fold/recovery. It exercises both full
and reduced motion. Offscreen mode uses explicit
compositor-only Caffeine/WallFx adapters; X11 mode uses the real services.
Actual network/audio/Hyprland/UPower services are unavailable in the private
namespace, by design. Their absence is logged and is not live integration
qualification. The real settings writer writes only private HOME state.

Use `/usr/lib/qt6/bin/qmllint`, not the older `qmllint` on PATH. Qt6 lint
reported no fatal syntax/alias classes in the changed QML; unresolved
project-import/type warnings prevent treating that as a clean full lint.
The native 142-component compile provides the stronger source-load check.
`kuwai-loadtest HEAD` archives committed files and cannot prove an
uncommitted candidate. `kuwai-check` observes the running revision and must
be reported with that revision, not credited to these source changes.

Recorded checks on the integrated candidate: the Bun suite passed 304 tests
(2,773 assertions), the Lua fixtures and token ratchet passed, and ShellCheck
passed for all changed shell helpers and the dispatcher library. Private X11
compiled 142 actual components and passed the full-motion 2x-text capsule
case after the merge. The initial candidate additionally passed the six
width/text/motion combinations and 404 Python tests; the merged candidate's
full Python suite passed 429 tests plus five subtests.
The subsequent wallpaper delta touched no owned audit path; its four new
regressions also passed, and the 142-component native compile passed again.
The current-source X11 capsule matrix passed all six text-scale/motion
combinations, each checking all three host widths.

Compatibility limits: backup roots outside HOME and link members are
rejected explicitly; they are not silently flattened/restored. Recording
metadata accepts old space records for display, but process signaling
requires a verified birth-time sidecar. Finish any legacy active recording
before activating the new recorder. Tabs/newlines in recording-directory
names are rejected because the state format cannot represent them safely.

The follow-up candidate combined 125 agent tests and 308 other Python tests
with five subtests, 304 Bun tests, the Lua fixtures, ShellCheck, and a
143-component native compile. The capsule runs checked both motion modes
and text scales 1, 1.2 and 2.
