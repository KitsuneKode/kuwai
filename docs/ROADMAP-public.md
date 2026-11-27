# Roadmap (after v0.1.0)

This page lists planned work **not yet shipped** in `v0.1.0`. Internal working notes live in [PLAN-kuwai.md](PLAN-kuwai.md) and [PLAN-launch.md](PLAN-launch.md).

## Reliability and security

- **Lock and suspend hardening:** release the `logind` suspend inhibitor only after lock readiness is confirmed, reacquire on wake, and trigger a standalone fallback locker if the shell crashes while locked.
- **PAM multi-factor and lockout polish:** show arbitrary PAM prompts (such as fingerprint before password) on the login screen and display `pam_faillock` lockout countdowns directly on the lock screen.
- **Lock screen privacy:** require unlock before dismissing hidden chat or one-time-code notifications, and add next-calendar-event previews under the same privacy rules.
- **API key hygiene:** scan named shell rc files for plain-text API keys and migrate them into the system keyring (`secret-tool`) with atomic rewrites.

## System and cleanup

- **System → Activity tab:** group running apps by systemd `app-*.scope` with desktop icons, live CPU deltas from cgroup `cpu.stat`, proportional memory, and Stop/Force Quit actions.
- **Cleanup → Caches additions:** surface Docker image and `journald` disk usage under "check first" with their cleanup commands.
- **Idle memory and dGPU sleep:** reduce long-session shell memory and improve on-demand worker lifecycles so hybrid-GPU laptops suspend the discrete GPU cleanly at rest.

## Screensavers, wallpapers, and themes

- **Screensaver ladder:** make the screensaver a first-class step before idle lock (`saver → fade → lock`), add a long-idle power step (clock on black or DPMS off after an hour), and add a photo-shuffle mode.
- **Live wallpaper polish:** serialize per-monitor `mpvpaper` operations, show a still frame when a live wallpaper is paused, and unify compositor DPMS state handling.
- **Per-monitor and day/night wallpapers:** support different wallpapers per monitor and optional day/night switching, plus additional open-licensed theme packs.
- **Minimal Plymouth boot theme:** optional black boot splash with a single accent ring.

## Agents and dictation

- **Live Activities from terminal panes:** show long builds, test suites, and CI runs as live progress in the island via kittymux.
- **Dictation improvements (with voxtype):** multi-MIME clipboard preservation on paste restore, queued dictations with ordered delivery, and voice control phrases.
- **Notch drop shelf:** drag files onto the island to stash temporarily or send to a phone over KDE Connect.
