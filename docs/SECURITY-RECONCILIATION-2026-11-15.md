# Security and recovery reconciliation — November 15, 2026

This maps the eighteen November10 audit IDs to the current isolated candidate,
based on committed baseline `56902918832548f490803911a0689e4c85a8aa62` plus the
uncommitted quality/lifecycle fixes. These are not eighteen newly discovered or
still-open vulnerabilities. Earlier fixes belong to the baseline; the present
batch must not take credit for implementing them.

“Fixture” means production logic exercised with synthetic files, commands or
providers. “Source only” means the mitigation exists but the adversarial or native
acceptance test is missing. No row establishes actual portal/PAM/compositor or
hardware qualification. No real credentials, user chats, lock, suspend, package
installation or stable promotion were used.

| ID | Current source and attempted disproof | Current evidence / remaining gate |
|---|---|---|
|01 Sandbox approval/use race | `bin/kuwai_sandbox.py` descriptor traversal and `kuwai_agent.py` sandbox operations; substitute a symlink after target selection | Baseline mitigation. `tests/agent/test_jail.py` swaps links and refuses host writes/reads; `test_sandbox_boundary.py` also checks links, hardlinks and FIFOs. Host approval revalidation beyond these fixtures remains review scope. |
|02 Secret-named ancestors | `bin/kuwai_files.py` checks all ancestors and resolved targets | Baseline mitigation. `test_file_policy.py` direct/recursive/glob/link fixtures pass; no credential inspection. |
|03 DNS/HTTP separation | `kuwai_agent.py` `_PinnedHTTP`, `_PinnedHTTPS`, `_pinned_socket`, `_SafeRedirect` | Baseline pinned connector. New `test_pinned_transport.py` verifies rebound-to-local refusal before socket creation, numeric-address connection, connected-peer recheck and close for IPv4/IPv6 private peers. Redirect and TLS behavior still need broader transport fixtures; no internet calls made. |
|04 Critical notification share redaction | `Notifs.qml bodyRedacted/bodyHidden` prioritize sharing over severity | Baseline mitigation. `privacy.test.mjs` critical/warning/private-chat cases pass. Actual capture and all visual surfaces remain native qualification. |
|05 Restart during active share | `Notifs.qml` requests `kuwai.privacy_resync()`; `automation.lua` replies mute-on when engaged | **Startup gap repaired in this batch:** `shareKnown=false` holds/redacts previews until the compositor acknowledges; resync now explicitly reports sharing/not-sharing, including feature-off, with five bounded startup attempts. Bun truth-table and actual Lua automation fixtures pass. Ordering under overlapping IPC/capture events and capture enumeration after compositor restart remain release gates requiring isolated portal/capture fixtures. No live restart/share was attempted. |
|06 Lock verification codes | `LockNotifs.qml isCode/heading/preview` uses `Notifs.otpOf` plus code word/shape checks | Baseline mitigation. `privacy.test.mjs` grouped digits, PIN, title codes and ordinary messages pass. Unicode-code and native lock/group exposure matrix remains unqualified. |
|07 Fallback lock readiness | `bin/kuwai lock --wait` formerly inferred readiness from a persistent hyprlock PID | **Fixed conservatively in this batch:** fallback request is still made, but `--wait` returns failure without trusted readiness acknowledgement. `tests/recovery/test_lock_boundary.py` reproduces the false success with inert persistent-PID stubs, then passes after repair; shell acknowledgement path remains accepted. Real fallback readiness integration and disposable lock/suspend acceptance remain pending. |
|08 Dirty stable rollback | `bin/kuwai` refuses promotion when stable `git status --porcelain` is nonempty | Baseline source mitigation. Installer lifecycle tests preserve user edits, but are not a promotion/rollback adversarial fixture. Actual promotion remains unrun and unauthorized. |
|09 Load-test false success | `bin/kuwai-loadtest` checks archive/entry and requires an expected offscreen stop | Baseline source mitigation. Not run here because HOME-only isolation cannot qualify all host boundaries. New `kuwai-ui-test` enforces namespace isolation, rejects runtime/binding errors and labels missing backend UNQUALIFIED; it does not certify the old command's full failure matrix. |
|10 Chat capability dispatch | `kuwai_agent.py` rejects changing tools at dispatch in Chat mode | Baseline mitigation. `test_tools.py` tests a prohibited named tool; `test_router.py` covers offered capabilities. Provider fixtures are synthetic. |
|11 Clipboard OTP restart expiry | `Clipboard.qml` persists secret IDs and derives expiry from stored copy times | Baseline source mitigation. Original expiry/classification paths inspected. Full restart/copy/expiry integration and pinned-entry policy remain unqualified; no clipboard accessed. |
|12 Clipboard image retention | `kuwai-clip delete/wipe` remove derived thumbnails/open/edit/render files while preserving pins/saved pictures | Baseline source mitigation. Empty-cache listing test passes; destructive deletion fixture with planted synthetic image copies is still needed. No real caches cleaned. |
|13 Removed pacnew values | `kuwai-pacnew` three-way decisions distinguish deletion/commenting from untouched defaults | Baseline mitigation. `test_pacnew.py` removal/comment/unchanged/no-old-default fixtures pass. |
|14 Feed ingestion watermark | `kuwai-feeds` advances only after successful handling, records processed IDs | Baseline mitigation. `tests/feeds/test_feeds.py` failed query/card, retry without duplicates and successful newest-watermark fixtures pass. |
|15 Plan-only inference cap | `kuwai_agent.py` caps consecutive plan-only rounds alongside tool rounds | Baseline mitigation. `test_tools.py test_plan_only_rounds_are_capped` and tool-cap fixture pass with fake provider. |
|16 Unbounded subprocess collection | `kuwai_files.py` bounded collector and sandbox bounded log tail | Baseline mitigation. `test_sandbox_boundary.py` bounded-tail fixture passes. Endless hostile subprocess/runtime cancellation acceptance remains incomplete; byte bounds alone do not prove time/resource containment. |
|17 Render-loop assignment argv | `kuwai-shell` passes each environment assignment as a separate array argument | Baseline source mitigation retained. Bash syntax passes. This batch adds a source revision variable; no live renderer change. Direct launcher argv failure injection is still needed. |
|18 Wi-Fi keyboard tasks | `WifiList.qml` exposes native focus/key/action paths, plus confirmation for Forget | Baseline keyboard paths plus present batch's captured-target Forget confirmation and revalidation. `forget-actions.test.mjs` tests confirmation ownership; real keyboard/AT-SPI tasks and transient network states remain native qualification. |

## Remaining release gates

The05 startup unknown-state gap is repaired at source/fixture level. Actual
capture/privacy lifecycle remains unqualified. The fallback lock path now avoids false success, but a real
positive readiness contract is needed before claiming reliable lock/suspend
recovery. Use a disposable session to qualify privacy/lock/restart/PAM/portal
behavior. Offscreen primitives cannot supply this evidence.

The root update allowlist and installer restoration suites also pass locally;
that does not authorize a root installation or qualify a distributed package.
Keep security provenance in durable state/data rather than deleting it with
rebuildable caches. See [SETTINGS.md](SETTINGS.md) for the settings writer's stated
concurrency/unknown-field boundaries.
