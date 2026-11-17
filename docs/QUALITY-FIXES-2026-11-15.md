# Quality and lifecycle implementation — November 15, 2026

Candidate: uncommitted changes in `fix/quality-and-lifecycle`, based on
`56902918832548f490803911a0689e4c85a8aa62`. Changes are isolated from the original
dirty checkout and the stable/live session. No commit, merge, push, package
installation, activation, live cache cleanup or compositor change was performed.

## Implemented behavior

- **Reviewed updates:** recipe preparation fails before executing makepkg when
  checkout, cleanup, HEAD or clean-tree verification fails. Recipes/provenance
  live in data/state; builds and archives live in cache. Installed baselines
  require a matching durable receipt and installed-package fingerprint rather
  than a guessed newer same-version recipe. PackageBase and requested split
  outputs are explicit. Successful workspaces release sources and retain three
  archive sets; failed owned workspaces retain two per recipe. Cancellation
  closes the root helper and prunes while holding the update lock. Legacy and
  unrecognized caches stay untouched. Review retries/freshness and approval
  withdrawal/persistence now have acknowledged outcomes.
- **Session integrity:** Clear confirms the captured conversation and invalidates
  its active draft without erasing other conversations' queues or a newly entered
  post-Clear prompt. Late deltas, requests and steering from discarded turns are
  ignored. Fork preserves unrelated queued work. Theme/display apply states wait
  for command outcome and readback; old display deadlines cannot clear a newer
  request, and the compositor command has a bounded timeout.
- **Idle/login/recovery:** idle handoff retains shell protection until hypridle
  start/health acknowledgement; launcher/rescue no longer race that owner.
  Greeter launch failure restores a usable locked form and reverses its outro.
  Journal-backed fixed-phase diagnostics correlate the greeter, session startup
  and shell configuration with a nonpersonal handoff ID. This is not proof of a
  first presented frame. Fallback `lock --wait` fails without trusted readiness
  instead of treating a living PID as proof of locking.
- **Privacy:** startup notification previews remain held/redacted until sharing
  state is acknowledged. Both positive and negative compositor replies exist,
  including intentional feature-off, with bounded startup retries. Full capture
  lifecycle and overlapping-event ordering still need native qualification.
- **UI:** island approach detection uses monitor logical bounds; calendar keyboard
  selection handles local calendar days across DST; network/Bluetooth Forget
  confirms and revalidates its captured target; Overview includes XWayland
  windows and keyboard workspace moves. Named/focusable paths were added to
  controls, chat rows and power hold actions. A completed hold resets progress.
  Segmented controls use a native compact fallback; narrow settings rows stack
  without overlap; Vitals reflows/scrolls. Text scale supports200%, accent/danger
  ink uses measured sRGB contrast in shell and auth, and reduced-motion/preview
  playback paths stop unnecessary motion/resources.
- **Settings architecture:** one explicit57-key schema owns defaults, validation
  and search metadata. UI and CLI use the same bounded atomic patch writer,
  preserve unknown fields, merge cooperating edits, remove overrides on reset,
  retain last-good values on malformed reload and expose save errors. Versioned
  migration is explicit, previewable and backed up; it is not run automatically.
  Lossy numeric/ambiguous JSON rewrites are refused. See [SETTINGS.md](SETTINGS.md).
- **Telemetry/testing:** memory samples identify PID/start/config/source revision,
  run and outcome, with atomic bounded per-run retention. Requested render-loop
  configuration is labeled as such. The native test runner uses a private
  namespace, network, home and D-Bus, inert session helpers, offscreen software
  rendering and a real settings writer limited to the private home. Runtime
  exceptions/binding errors fail even if a screenshot was produced.

## Review and test evidence

Meaningful production regressions were observed failing before repairs. The first
independent batch review found delayed Clear deletion, stale display deadlines and
early-return retention bypass; those were repaired with regressions. The settings
review initially hit a usage limit, automatically resumed, then identified empty
XDG fallback, masked CLI errors, integral-number parity and a misrouted bedtime
search; those were also repaired. These are addressed findings, not an independent
approval of the final edited tree. New privacy/fallback-lock changes were checked
by the author with adversarial fixtures; native qualification remains pending.

Final local results: **238 Python tests**, **148 Bun tests /444 assertions**,
**196 QML files parsed**, and all **three Lua suites** pass. Bash syntax,
whitespace and design-token gates pass (sizes61, durations89, hex69 below the
existing70 baseline). Private primitive fixtures pass at100% and200% text; the
private settings lifecycle fixture passes. These counts describe local checks,
not hardware, CI or release approval.

Verification commands:

```sh
PYTHONDONTWRITEBYTECODE=1 python -m pytest -q -p no:cacheprovider tests
bun test ./tests/shell/*.test.mjs ./shell/services/ai/turn.test.mjs
for t in tests/hypr/test_*.lua; do lua "$t" || exit 1; done
bin/rice-tokens --check
git diff --check
bin/rice-ui-test --case primitives --text-scale 1 --output /tmp/kuwai-ui-1x
bin/rice-ui-test --case primitives --text-scale 2 --output /tmp/kuwai-ui-2x
bin/rice-ui-test --case settings-store --output /tmp/kuwai-settings
```

The Python fake-provider suite needs permission for localhost fixture servers.
The native fixtures need permission to create their private namespaces. Neither
permission makes them live-session tests. QML parser and Bash syntax checks also
run locally. The full native component import is **UNQUALIFIED** offscreen:
Caffeine's PanelWindow requires a compositor backend. A FileView dropped-operation
warning remains visible in native logs; the asserted reload/rollback lifecycle
passes, but the warning is not relabeled a clean runtime log.

## Remaining work before a9.5 release claim

No numerical9.5 rating is asserted. All ten plans retain qualification or
implementation work. The next source/product tasks are complete stable
provider/principal/window attention identity and stale/overflow behavior,
reopenable first-run/capability UX, the broader task/state fixture matrix,
remaining adversarial security/recovery cases, and distributable package/receipt
and redacted support export. See the eighteen-item
[security reconciliation](SECURITY-RECONCILIATION-2026-11-15.md).

The successful-login black/monitor-off gap has **no proven root cause yet**.
Use the new monotonic journal phases in a disposable hardware login, together
with accepted modes/GPU/first-frame evidence. Do not label a timer or GPU
hypothesis as the fix. Memory logs now support attribution, but neither a leak
nor its absence is established. Controlled equivalent cycles, process/decoder/GPU
attribution and an eight-hour disposable soak remain required.

Native keyboard/AT-SPI, full640px/mixed-scale/text/motion matrix, PAM/portals,
lock/suspend/hotplug, real package lifecycle, clean VM and an independent second
machine remain unqualified. Integrating this candidate must reconcile the original
checkout's concurrent styling/Idle edits explicitly; copying over them would lose
unrelated work.

## Execution rulings

- Execute the user's later fix authorization despite the earlier audit-only
  workflow; the user requested implementation. Cost of getting scope wrong is
  review churn; all work remains isolated and reversible.
- Keep this worktree and ledger uncommitted and inactive. Cost: fixes are not yet
  present in the user's original/stable checkout, and integration is still needed.
- Replace whole-document JsonAdapter writes with a narrow shared patch helper.
  Cost: one short-lived Python process per change, optimistic UI rollback on save
  failure, and the documented compare/rename limitation for uncooperative editors.
- Fail closed when fallback-lock readiness is unconfirmed. Cost: before-sleep
  callers receive failure while the shell is unavailable until a positive
  readiness adapter is qualified.
- Retain the existing privacy service/IPC seams and add an unknown/acknowledged
  startup state. Cost: overlapping capture/IPC ordering still needs qualification;
  this does not introduce a generic state-machine bus or certify real capture.
